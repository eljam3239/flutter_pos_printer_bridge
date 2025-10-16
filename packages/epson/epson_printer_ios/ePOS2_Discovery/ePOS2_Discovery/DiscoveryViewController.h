#import <UIKit/UIKit.h>
#import "ePOS2.h"
#import "PickerTableView.h"

@interface DiscoveryViewController : UIViewController<SelectPickerTableDelegate>
{
    NSMutableArray *deviceList_;

    PickerTableView *portTypeList_;
    PickerTableView  *deviceModelList_;
    PickerTableView *deviceTypeList_;

    UIScrollView *scrollBaseView_;
}
@property(weak, nonatomic) IBOutlet UIScrollView *scrollView;
@property(weak, nonatomic) IBOutlet UIView *itemView;
@property(weak, nonatomic) IBOutlet UIButton *buttonStart;
@property(weak, nonatomic) IBOutlet UIButton *buttonStop;
@property(weak, nonatomic) IBOutlet UIButton *buttonPortType;
@property(weak, nonatomic) IBOutlet UITextField *broadcastText;
@property(weak, nonatomic) IBOutlet UIButton *buttonDeviceModel;
@property(weak, nonatomic) IBOutlet UIButton *buttonDeviceType;
@property(weak, nonatomic) IBOutlet UITableView *deviceView;
@end
