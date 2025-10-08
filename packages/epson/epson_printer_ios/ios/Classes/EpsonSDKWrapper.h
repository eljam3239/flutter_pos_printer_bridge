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

- (void)startDiscoveryWithFilter:(int32_t)filter completion:(void (^)(NSArray<NSDictionary *> *printers))completion;
- (void)startBluetoothDiscoveryWithCompletion:(void (^)(NSArray<NSDictionary *> *printers))completion;
- (void)findPairedBluetoothPrintersWithCompletion:(void (^)(NSArray<NSDictionary *> *printers))completion;
- (void)stopDiscovery;
- (BOOL)connectToPrinter:(NSString *)target withSeries:(int32_t)series language:(int32_t)language timeout:(int32_t)timeout;
- (void)disconnect;
- (NSDictionary *)getPrinterStatus;
- (BOOL)printWithCommands:(NSArray<NSDictionary *> *)commands;
- (void)clearCommandBuffer;
- (BOOL)openCashDrawer;
- (void)pairBluetoothDeviceWithCompletion:(void (^)(NSString * _Nullable target, int result))completion;

@end

NS_ASSUME_NONNULL_END
