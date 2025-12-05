//
//  EpsonSDKWrapper.h
//

#import <Foundation/Foundation.h>
#import "ePOS2.h"

NS_ASSUME_NONNULL_BEGIN

@interface EpsonSDKWrapper : NSObject <Epos2DiscoveryDelegate, Epos2PtrReceiveDelegate>

@property (nonatomic, strong, nullable) Epos2Printer *printer;
@property (nonatomic, copy, nullable) void (^discoveryCompletionHandler)(NSArray<NSDictionary *> *printers);
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *discoveredPrinters;
@property (nonatomic, assign) BOOL isBluetoothDiscovery; // Track if current discovery is Bluetooth (for early termination)
@property (nonatomic, strong, nullable) dispatch_block_t bluetoothTimeoutBlock; // Track Bluetooth timeout to cancel overlaps

- (void)startDiscoveryWithFilter:(int32_t)filter completion:(void (^)(NSArray<NSDictionary *> *printers))completion;
- (void)startBluetoothDiscoveryWithCompletion:(void (^)(NSArray<NSDictionary *> *printers))completion; // Classic BT only (BLE disabled)
- (void)findPairedBluetoothPrintersWithCompletion:(void (^)(NSArray<NSDictionary *> *printers))completion;
- (void)stopDiscovery;
- (void)cancelBluetoothTimeout;
- (void)forceDiscoveryCleanup;
- (void)forceDiscoveryCleanupWithCompletion:(void (^)(void))completion; // Non-blocking cleanup with callback when fully done
- (BOOL)connectToPrinter:(NSString *)target withSeries:(int32_t)series language:(int32_t)language timeout:(int32_t)timeout;
- (void)disconnect;
- (NSDictionary *)getPrinterStatus;
- (BOOL)printWithCommands:(NSArray<NSDictionary *> *)commands;
- (void)clearCommandBuffer;
- (BOOL)openCashDrawer;
- (void)pairBluetoothDeviceWithCompletion:(void (^)(NSString * _Nullable target, int result))completion;
- (void)detectPaperWidthWithCompletion:(void (^)(NSString * _Nullable paperWidth, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END