#import <Foundation/Foundation.h>
#import "ePOS2.h"

@interface ShowMsg : NSObject
    //show method error
+ (void)showErrorEpos:(int)result method:(NSString *)method;
@end
