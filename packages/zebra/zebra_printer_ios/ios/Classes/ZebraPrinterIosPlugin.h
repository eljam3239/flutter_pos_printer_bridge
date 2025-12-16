#import <Flutter/Flutter.h>

// Forward declaration to avoid header dependencies
@protocol ZebraPrinterConnection;

@interface ZebraPrinterIosPlugin : NSObject<FlutterPlugin>

// Active connection to the currently connected Zebra printer (if any)
@property (nonatomic, strong) id<ZebraPrinterConnection> activeConnection;

@end