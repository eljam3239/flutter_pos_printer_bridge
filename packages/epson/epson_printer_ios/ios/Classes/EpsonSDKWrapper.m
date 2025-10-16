//
//  EpsonSDKWrapper.m
//

#import "EpsonSDKWrapper.h"
#import <UIKit/UIKit.h>

// Private interface
@interface EpsonSDKWrapper ()
- (void)tryBluetoothDiscovery:(int)portType withFallback:(BOOL)useFallback;
@end

@implementation EpsonSDKWrapper

- (instancetype)init {
    self = [super init];
    if (self) {
        _discoveredPrinters = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)startDiscoveryWithFilter:(int32_t)filter completion:(void (^)(NSArray<NSDictionary *> *))completion {
    NSLog(@"Starting discovery with filter: %d", filter);
    if (!completion) { NSLog(@"ERROR: No completion handler provided for discovery"); return; }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            // CRITICAL: Always stop any previous discovery first to ensure clean state
            // This is especially important after printer disconnect where SDK state may be corrupted
            NSLog(@"Ensuring no previous discovery is running...");
            int32_t stopResult = [Epos2Discovery stop];
            NSLog(@"Pre-discovery stop result: %d (EPOS2_ERR_PARAM_5=expected if nothing running)", stopResult);
            
            [self.discoveredPrinters removeAllObjects];
            self.discoveryCompletionHandler = completion;
            self.isBluetoothDiscovery = NO; // LAN/TCP discovery - no early termination
            
            Epos2FilterOption *filterOption = [[Epos2FilterOption alloc] init];
            if (!filterOption) { NSLog(@"ERROR: Failed to create filter option"); completion(@[]); self.discoveryCompletionHandler = nil; return; }
            
            [filterOption setDeviceType:EPOS2_TYPE_PRINTER];
            if (filter != EPOS2_PARAM_UNSPECIFIED) {
                [filterOption setPortType:filter];
            }
            
            NSLog(@"Created filter option (deviceType=PRINTER, portType=%d), starting discovery...", filter);
            int32_t result = [Epos2Discovery start:filterOption delegate:self];
            NSLog(@"Discovery start result: %d (EPOS2_SUCCESS=0)", result);
            if (result != EPOS2_SUCCESS) { completion(@[]); self.discoveryCompletionHandler = nil; return; }
            
            // Timeout: 5s then stop and complete
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSLog(@"Discovery timeout reached, stopping discovery...");
                [Epos2Discovery stop];
                
                if (self.discoveryCompletionHandler) {
                    self.discoveryCompletionHandler([self.discoveredPrinters copy]);
                    self.discoveryCompletionHandler = nil;
                }
            });
        } @catch (NSException *exception) {
            NSLog(@"Exception in startDiscovery: %@", exception);
            completion(@[]);
            self.discoveryCompletionHandler = nil;
        }
    });
}- (void)stopDiscovery {
    dispatch_async(dispatch_get_main_queue(), ^{
        int result = EPOS2_SUCCESS;
        do { result = [Epos2Discovery stop]; } while (result == EPOS2_ERR_PROCESSING);
    });
}

- (void)cancelBluetoothTimeout {
    if (self.bluetoothTimeoutBlock) {
        NSLog(@"Cancelling pending Bluetooth timeout from previous discovery");
        dispatch_block_cancel(self.bluetoothTimeoutBlock);
        self.bluetoothTimeoutBlock = nil;
    }
}

- (void)forceDiscoveryCleanup {
    NSLog(@"Force cleaning Discovery SDK state (wrapper)...");
    if ([NSThread isMainThread]) {
        [self performDiscoveryCleanup];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{ [self performDiscoveryCleanup]; });
    }
}

- (void)forceDiscoveryCleanupWithCompletion:(void (^)(void))completion {
    NSLog(@"Force cleaning Discovery SDK state (wrapper, with completion)...");
    void (^safeCompletion)(void) = [completion copy];
    if ([NSThread isMainThread]) {
        [self performDiscoveryCleanupWithCompletion:safeCompletion];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{ [self performDiscoveryCleanupWithCompletion:safeCompletion]; });
    }
}

// Proper standalone non-blocking cleanup routine
- (void)performDiscoveryCleanup {
    static BOOL inProgress = NO;
    if (inProgress) {
        NSLog(@"performDiscoveryCleanup: already in progress - skipping");
        return;
    }
    inProgress = YES;
    NSLog(@"performDiscoveryCleanup: starting iterative stop sequence");
    __block int attempt = 0;
    __weak typeof(self) weakSelf = self;
    __block void (^attemptStop)(void) = nil;
    attemptStop = ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) { inProgress = NO; return; }
        int32_t result = [Epos2Discovery stop];
        NSLog(@"performDiscoveryCleanup: stop attempt %d => %d", attempt + 1, result);
        attempt++;
        if (attempt < 5) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), attemptStop);
            return;
        }
        if (strongSelf.bluetoothTimeoutBlock) {
            dispatch_block_cancel(strongSelf.bluetoothTimeoutBlock);
            strongSelf.bluetoothTimeoutBlock = nil;
        }
        strongSelf.discoveryCompletionHandler = nil;
        strongSelf.isBluetoothDiscovery = NO;
        [strongSelf.discoveredPrinters removeAllObjects];
        NSLog(@"performDiscoveryCleanup: complete; SDK should be clean");
        inProgress = NO;
    };
    attemptStop();
}

// Completion-capable variant used by Swift to defer new discovery until fully clean
- (void)performDiscoveryCleanupWithCompletion:(void (^)(void))completion {
    static BOOL inProgress2 = NO;
    if (inProgress2) {
        NSLog(@"performDiscoveryCleanupWithCompletion: already in progress - will invoke completion after current run");
        if (completion) { dispatch_async(dispatch_get_main_queue(), completion); }
        return;
    }
    inProgress2 = YES;
    NSLog(@"performDiscoveryCleanupWithCompletion: starting iterative stop sequence");
    __block int attempt = 0;
    __weak typeof(self) weakSelf = self;
    __block void (^attemptStop)(void) = nil;
    attemptStop = ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) { inProgress2 = NO; if (completion) completion(); return; }
        int32_t result = [Epos2Discovery stop];
        NSLog(@"performDiscoveryCleanupWithCompletion: stop attempt %d => %d", attempt + 1, result);
        attempt++;
        if (attempt < 5) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), attemptStop);
            return;
        }
        if (strongSelf.bluetoothTimeoutBlock) {
            dispatch_block_cancel(strongSelf.bluetoothTimeoutBlock);
            strongSelf.bluetoothTimeoutBlock = nil;
        }
        strongSelf.discoveryCompletionHandler = nil;
        strongSelf.isBluetoothDiscovery = NO;
        [strongSelf.discoveredPrinters removeAllObjects];
        NSLog(@"performDiscoveryCleanupWithCompletion: complete; SDK should be clean");
        inProgress2 = NO;
        if (completion) { completion(); }
    };
    attemptStop();
}

- (BOOL)connectToPrinter:(NSString *)target withSeries:(int32_t)series language:(int32_t)language timeout:(int32_t)timeout {
    NSLog(@"Connecting to printer with target: %@, series: %d, language: %d, timeout: %d", target, series, language, timeout);
    
    if (self.printer) {
        NSLog(@"Disconnecting existing printer connection...");
        [self.printer disconnect];
        self.printer = nil;
    }
    
    NSLog(@"Creating new printer instance...");
    self.printer = [[Epos2Printer alloc] initWithPrinterSeries:series lang:language];
    if (!self.printer) {
        NSLog(@"ERROR: Failed to create printer instance");
        return NO;
    }
    
    NSLog(@"Setting receive event delegate...");
    [self.printer setReceiveEventDelegate:self];
    
    NSLog(@"Attempting to connect to target: %@", target);
    int32_t result;
    if ([target hasPrefix:@"BLE:"]) {
        NSLog(@"Using BLE connection with 30s timeout");
        result = [self.printer connect:target timeout:30000]; // 30 second timeout for BLE
    } else {
        NSLog(@"Using standard connection with %d ms timeout", timeout);
        result = [self.printer connect:target timeout:timeout];
    }
    
    NSLog(@"Connection result: %d", result);
    
    if (result != EPOS2_SUCCESS) {
        NSLog(@"Connection failed with result: %d", result);
        
        // Log detailed error information
        switch (result) {
            case EPOS2_ERR_PARAM:
                NSLog(@"ERROR: Invalid parameter");
                break;
            case EPOS2_ERR_CONNECT:
                NSLog(@"ERROR: Connection error - printer may be offline or unreachable");
                break;
            case EPOS2_ERR_TIMEOUT:
                NSLog(@"ERROR: Connection timeout");
                break;
            case EPOS2_ERR_MEMORY:
                NSLog(@"ERROR: Memory allocation error");
                break;
            case EPOS2_ERR_ILLEGAL:
                NSLog(@"ERROR: Illegal operation");
                break;
            case EPOS2_ERR_PROCESSING:
                NSLog(@"ERROR: Processing error");
                break;
            default:
                NSLog(@"ERROR: Unknown error code: %d", result);
                break;
        }
        
        self.printer = nil;
        return NO;
    }
    
    NSLog(@"Successfully connected to printer!");
    return YES;
}

- (void)disconnect {
    if (self.printer) {
        NSLog(@"Disconnecting printer...");
        
        // Clear delegate first to prevent callbacks during cleanup
        [self.printer setReceiveEventDelegate:nil];
        
        [self.printer disconnect];
        [self.printer clearCommandBuffer];
        self.printer = nil;
        
        NSLog(@"Printer disconnected successfully");
    }
}

- (NSDictionary *)getPrinterStatus {
    if (!self.printer) {
        return @{};
    }
    
    Epos2PrinterStatusInfo *status = [self.printer getStatus];
    
    return @{
        @"isOnline": @(status.online == EPOS2_TRUE),
        @"status": status.online == EPOS2_TRUE ? @"online" : @"offline",
        @"errorMessage": [NSNull null],
        @"paperStatus": @(status.paper),
        @"drawerStatus": @(status.drawer),
        @"batteryLevel": @(status.batteryLevel),
        @"isCoverOpen": @(status.coverOpen == EPOS2_TRUE),
        @"errorCode": @(status.errorStatus),
        @"connection": @(status.connection == EPOS2_TRUE),
        @"paperFeed": @(status.paperFeed == EPOS2_TRUE),
        @"panelSwitch": @(status.panelSwitch)
    };
}

- (BOOL)printWithCommands:(NSArray<NSDictionary *> *)commands {
    NSLog(@"Starting print with %lu commands", (unsigned long)commands.count);
    
    if (!self.printer) {
        NSLog(@"ERROR: No printer connected");
        return NO;
    }
    
    NSLog(@"Clearing command buffer...");
    [self.printer clearCommandBuffer];
    
    for (NSDictionary *command in commands) {
        NSString *type = command[@"type"];
        NSLog(@"Processing command type: %@", type);

        // Handle both old format (addText) and new format (text)
        if ([type isEqualToString:@"addText"] || [type isEqualToString:@"text"]) {
            NSDictionary *parameters = command[@"parameters"];
            NSString *text = parameters[@"data"];
            if (text) {
                NSLog(@"Adding text: %@", text);
                [self.printer addText:text];
            } else {
                NSLog(@"WARNING: Text command missing data parameter");
            }
        } else if ([type isEqualToString:@"addTextLn"]) {
            NSDictionary *parameters = command[@"parameters"];
            NSString *text = parameters[@"data"];
            if (text) {
                NSLog(@"Adding text with newline: %@", text);
                [self.printer addText:text];
                [self.printer addFeedLine:1];
            }
        } else if ([type isEqualToString:@"addFeedLine"] || [type isEqualToString:@"feed"]) {
            NSDictionary *parameters = command[@"parameters"];
            NSNumber *lines = parameters[@"line"];
            int lineCount = lines ? lines.intValue : 1;
            NSLog(@"Adding feed lines: %d", lineCount);
            [self.printer addFeedLine:lineCount];
        } else if ([type isEqualToString:@"addCut"] || [type isEqualToString:@"cut"]) {
            NSLog(@"Adding cut command");
            [self.printer addCut:EPOS2_CUT_FEED];
        } else if ([type isEqualToString:@"image"]) {
            NSDictionary *parameters = command[@"parameters"];
            NSString *imagePath = parameters[@"imagePath"];
            if (!imagePath || imagePath.length == 0) {
                NSLog(@"WARNING: Image command missing imagePath");
                continue;
            }
            BOOL debug = NO;
            id debugVal = parameters[@"debug"];
            if ([debugVal isKindOfClass:[NSNumber class]]) { debug = [debugVal boolValue]; }
            NSString *align = parameters[@"align"] ?: @"left";
            NSNumber *targetWidthNum = parameters[@"targetWidth"];
            int targetWidth = targetWidthNum ? targetWidthNum.intValue : 0; // in dots/pixels

            if (debug) { [self.printer addText:@"[IOS_IMG_START]\n"]; }
            NSLog(@"IMAGE: Loading image at path: %@ (targetWidth=%d)", imagePath, targetWidth);

            UIImage *image = [UIImage imageWithContentsOfFile:imagePath];
            if (!image) {
                NSLog(@"ERROR: Failed to load image from path: %@", imagePath);
                if (debug) { [self.printer addText:@"[IOS_IMG_DECODE_FAILED]\n"]; }
                continue;
            }

            // Convert to a working copy and optionally scale
            UIImage *working = image;
            int originalPixelWidth = (int)(image.size.width * image.scale);
            if (targetWidth > 0 && originalPixelWidth > targetWidth) {
                CGFloat scaleFactor = (CGFloat)targetWidth / (CGFloat)originalPixelWidth;
                CGSize newSize = CGSizeMake(image.size.width * scaleFactor, image.size.height * scaleFactor);
                UIGraphicsBeginImageContextWithOptions(newSize, NO, 1.0); // 1.0 so width in points == target pixel width
                [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
                UIImage *scaled = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
                if (scaled) {
                    working = scaled;
                    NSLog(@"IMAGE: Scaled from %dpx to %dpx", originalPixelWidth, targetWidth);
                } else {
                    NSLog(@"WARNING: Scaling failed, using original image");
                }
            }

            // Alignment (affects subsequent render until changed). Keep simple as Android implementation.
            if ([align.lowercaseString isEqualToString:@"center"]) {
                [self.printer addTextAlign:EPOS2_ALIGN_CENTER];
            } else if ([align.lowercaseString isEqualToString:@"right"]) {
                [self.printer addTextAlign:EPOS2_ALIGN_RIGHT];
            } else {
                [self.printer addTextAlign:EPOS2_ALIGN_LEFT];
            }

            // Determine width/height in pixels for addImage
            int finalPixelWidth = (int)(working.size.width * working.scale);
            int finalPixelHeight = (int)(working.size.height * working.scale);

            // Epson expects width/height arguments; we pass actual pixel dims.
            int addResult = [self.printer addImage:working
                                                x:0
                                                y:0
                                            width:finalPixelWidth
                                           height:finalPixelHeight
                                             color:EPOS2_COLOR_1
                                              mode:EPOS2_MODE_MONO
                                          halftone:EPOS2_HALFTONE_DITHER
                                         brightness:1.0
                                          compress:EPOS2_COMPRESS_AUTO];
            NSLog(@"IMAGE: addImage result=%d", addResult);
            if (addResult != EPOS2_SUCCESS) {
                NSLog(@"ERROR: addImage failed with code %d", addResult);
                if (debug) { [self.printer addText:[NSString stringWithFormat:@"[IOS_IMG_ADD_FAIL %d]\n", addResult]]; }
            } else if (debug) {
                [self.printer addText:@"[IOS_IMG_END]\n"]; // marker after successful add
            }
        } else {
            NSLog(@"WARNING: Unknown command type: %@", type);
        }
    }
    
    NSLog(@"Sending print data to printer...");
    int32_t result = [self.printer sendData:EPOS2_PARAM_DEFAULT];
    NSLog(@"Print result: %d (EPOS2_SUCCESS=0)", result);
    // Important: Clear buffer after send to prevent subsequent operations (e.g., drawer pulse)
    // from re-sending the previous print content.
    [self.printer clearCommandBuffer];
    if (result == EPOS2_SUCCESS) {
        NSLog(@"Print job sent successfully");
        return YES;
    } else {
        NSLog(@"Print failed with result=%d", result);
        return NO;
    }
}

// MARK: - Bluetooth Discovery (Classic only; BLE disabled)

- (void)startBluetoothDiscoveryWithCompletion:(void (^)(NSArray<NSDictionary *> *printers))completion {
    if (!completion) { NSLog(@"ERROR: No completion handler for Bluetooth discovery"); return; }
    [self cancelBluetoothTimeout];
    self.discoveryCompletionHandler = completion;
    [self startClassicBluetoothDiscovery];
}

- (void)startClassicBluetoothDiscovery {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"Starting Classic Bluetooth discovery (BLE disabled)");
        [Epos2Discovery stop];
        self.isBluetoothDiscovery = YES;
        [self.discoveredPrinters removeAllObjects];
        Epos2FilterOption *filter = [[Epos2FilterOption alloc] init];
        [filter setPortType:EPOS2_PORTTYPE_BLUETOOTH];
        int32_t result = [Epos2Discovery start:filter delegate:self];
        NSLog(@"BT discovery start result: %d (EPOS2_SUCCESS=0)", result);
        if (result != EPOS2_SUCCESS) {
            if (self.discoveryCompletionHandler) { self.discoveryCompletionHandler(@[]); self.discoveryCompletionHandler = nil; }
            return;
        }
        // Timeout for classic BT can be shorter (6s) since we early-stop after first device.
        __weak typeof(self) weakSelf = self;
        self.bluetoothTimeoutBlock = dispatch_block_create(0, ^{
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            NSLog(@"BT discovery timeout reached, stopping discovery...");
            int sret = EPOS2_SUCCESS;
            do { sret = [Epos2Discovery stop]; } while (sret == EPOS2_ERR_PROCESSING);
            if (strongSelf.discoveryCompletionHandler) {
                strongSelf.discoveryCompletionHandler([strongSelf.discoveredPrinters copy]);
                strongSelf.discoveryCompletionHandler = nil;
            }
            strongSelf.bluetoothTimeoutBlock = nil;
            strongSelf.isBluetoothDiscovery = NO;
        });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(6.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), self.bluetoothTimeoutBlock);
    });
}

- (void)clearCommandBuffer {
    if (self.printer) { [self.printer clearCommandBuffer]; }
}

- (BOOL)openCashDrawer {
    if (!self.printer) { NSLog(@"openCashDrawer: no printer"); return NO; }
    // Ensure buffer is clean so we don't accidentally resend prior print data
    [self.printer clearCommandBuffer];
    // EPOS2_DRAWER_1 does not exist; using EPOS2_DRAWER_2PIN as default (most common)
    int addRes = [self.printer addPulse:EPOS2_DRAWER_2PIN time:EPOS2_PULSE_100];
    if (addRes != EPOS2_SUCCESS) { NSLog(@"addPulse failed: %d", addRes); return NO; }
    int sendRes = [self.printer sendData:EPOS2_PARAM_DEFAULT];
    NSLog(@"openCashDrawer sendData result=%d", sendRes);
    return sendRes == EPOS2_SUCCESS;
}

- (void)findPairedBluetoothPrintersWithCompletion:(void (^)(NSArray<NSDictionary *> *printers))completion {
    NSLog(@"findPairedBluetoothPrintersWithCompletion called - looking for already paired devices");
    
    if (!completion) {
        NSLog(@"ERROR: No completion handler provided for paired Bluetooth discovery");
        return;
    }
    
    // Ensure Epson discovery start/stop runs on the main thread (Epson SDK expects main thread)
    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            // Stop any existing discovery first
            [Epos2Discovery stop];
            
            [self.discoveredPrinters removeAllObjects];
            __block BOOL discoveryCompleted = NO;
            
            // Store completion handler
            void (^savedCompletion)(NSArray<NSDictionary *> *) = [completion copy];
            
            // Set up discovery completion
            self.discoveryCompletionHandler = ^(NSArray<NSDictionary *> *printers) {
                if (!discoveryCompleted) {
                    discoveryCompleted = YES;
                    NSLog(@"Paired Bluetooth discovery completed with %lu devices", (unsigned long)printers.count);
                    savedCompletion(printers);
                }
            };
            
            // Try BLE discovery first (for paired devices, this should find BD addresses)
            NSLog(@"Starting paired device discovery with BLE (main thread)...");
            
            Epos2FilterOption *bleFilter = [[Epos2FilterOption alloc] init];
            [bleFilter setPortType:EPOS2_PORTTYPE_BLUETOOTH_LE];
            
            int32_t result = [Epos2Discovery start:bleFilter delegate:self];
            NSLog(@"Paired BLE discovery result: %d", result);
            
            if (result != EPOS2_SUCCESS) {
                // Try classic Bluetooth if BLE fails
                NSLog(@"BLE discovery failed, trying classic Bluetooth for paired devices (main thread)...");
                
                Epos2FilterOption *btFilter = [[Epos2FilterOption alloc] init];
                [btFilter setPortType:EPOS2_PORTTYPE_BLUETOOTH];
                
                result = [Epos2Discovery start:btFilter delegate:self];
                NSLog(@"Paired BT discovery result: %d", result);
            }
            
            if (result != EPOS2_SUCCESS) {
                NSLog(@"Both BLE and BT discovery failed for paired devices");
                if (!discoveryCompleted) {
                    discoveryCompleted = YES;
                    savedCompletion(@[]);
                }
                return;
            }
            
            // Set timeout for paired device discovery
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSLog(@"Paired device discovery timeout reached");
                [Epos2Discovery stop];
                
                if (!discoveryCompleted) {
                    discoveryCompleted = YES;
                    NSLog(@"Found %lu paired devices", (unsigned long)self.discoveredPrinters.count);
                    savedCompletion([self.discoveredPrinters copy]);
                }
            });
            
        } @catch (NSException *exception) {
            NSLog(@"Exception in findPairedBluetoothPrinters: %@", exception);
            completion(@[]);
        }
    });
}

- (void)pairBluetoothDeviceWithCompletion:(void (^)(NSString * _Nullable target, int result))completion {
    NSLog(@"pairBluetoothDeviceWithCompletion called");
    if (!completion) { return; }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @try {
            Epos2BluetoothConnection *bt = [[Epos2BluetoothConnection alloc] init];
            if (!bt) {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, EPOS2_BT_ERR_FAILURE); });
                return;
            }
            NSMutableString *mac = [NSMutableString string];
            int ret = [bt connectDevice:mac];
            NSLog(@"connectDevice returned: %d, mac: %@", ret, mac);
            if (ret == EPOS2_BT_SUCCESS || ret == EPOS2_BT_ERR_ALREADY_CONNECT) {
                NSString *macStr = [mac copy];
                // If SDK already returns a scheme (BT:/BLE:), use it as-is. Otherwise, prefix with BT:
                NSString *upper = [macStr uppercaseString];
                BOOL hasScheme = [upper hasPrefix:@"BT:"] || [upper hasPrefix:@"BLE:"] || [upper hasPrefix:@"TCP:"] || [upper hasPrefix:@"TCPS:"] || [upper hasPrefix:@"USB:"];
                NSString *target = hasScheme ? macStr : [NSString stringWithFormat:@"BT:%@", macStr];
                dispatch_async(dispatch_get_main_queue(), ^{ completion(target, ret); });
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, ret); });
            }
        } @catch (NSException *ex) {
            NSLog(@"Exception in pairBluetoothDeviceWithCompletion: %@", ex);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, EPOS2_BT_ERR_FAILURE); });
        }
    });
}

#pragma mark - Epos2DiscoveryDelegate

- (void)onDiscovery:(Epos2DeviceInfo *)deviceInfo {
    NSLog(@"Discovery found device: %@ (target: %@, IP: %@)", deviceInfo.deviceName, deviceInfo.target, deviceInfo.ipAddress);
    
    NSDictionary *printerInfo = @{
        @"target": deviceInfo.target ?: @"",
        @"deviceName": deviceInfo.deviceName ?: @"",
        @"deviceType": @(deviceInfo.deviceType),
        @"ipAddress": deviceInfo.ipAddress ?: @"",
        @"macAddress": deviceInfo.macAddress ?: @"",
    };
    
    [self.discoveredPrinters addObject:printerInfo];
    
    // Early termination: ONLY for Bluetooth discovery, stop after finding first device (faster UX)
    // DO NOT do this for LAN/TCP discovery - multiple stop() calls corrupt SDK state
    if (self.isBluetoothDiscovery && self.discoveredPrinters.count == 1) {
        NSLog(@"First Bluetooth device found, stopping discovery early for faster response");
        
        // Cancel the timeout since we're completing early
        if (self.bluetoothTimeoutBlock) {
            dispatch_block_cancel(self.bluetoothTimeoutBlock);
            self.bluetoothTimeoutBlock = nil;
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            int sret = EPOS2_SUCCESS;
            do { sret = [Epos2Discovery stop]; } while (sret == EPOS2_ERR_PROCESSING);
            if (self.discoveryCompletionHandler) {
                self.discoveryCompletionHandler([self.discoveredPrinters copy]);
                self.discoveryCompletionHandler = nil;
            }
            self.isBluetoothDiscovery = NO;
        });
    }
}

- (void)onComplete {
    NSLog(@"Discovery completed. Found %lu printers", (unsigned long)self.discoveredPrinters.count);
    
    // Don't call completion here, let the timer handle it
    // The onComplete can be called before all devices are found
}

#pragma mark - Epos2PtrReceiveDelegate

- (void)onPtrReceive:(Epos2Printer *)printerObj code:(int32_t)code status:(Epos2PrinterStatusInfo *)status printJobId:(NSString *)printJobId {
    NSLog(@"Print job completed with code: %d", code);
}

@end