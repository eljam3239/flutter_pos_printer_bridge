#import "PickerTableView.h"

@interface PickerTableView()
-(void)eventDidPushDone:(id)sender;
@end

@implementation PickerTableView

@synthesize selectIndex = selectIndex_;
@synthesize delegate = delegate_;

- (id)init
{

    self = [super init];
    if (self) {
        selectIndex_ = 0;
    }
    return self;
}

- (void)dealloc
{
    baseView_ = nil;
    backView_ = nil;
}

//set item list
- (void) setItemList:(NSArray *)items
{
    pickerItems_ = items;
}

//get item
- (NSString *) getItem:(NSInteger)position
{
    id tmpObject = [self getObject:position];
    if (tmpObject != nil) {
        return [tmpObject description];
    }
    else {
        return nil;
    }
}

//get object
- (id)getObject:(NSInteger)position
{
    if (pickerItems_ == nil) {
        return nil;
    }
    if (position < [pickerItems_ count]) {
        return pickerItems_[position];

    }
    else {
        return nil;
    }
}

//show pickerview
-(void)show
{
    //create pickerview
    CGRect r = [[UIScreen mainScreen] bounds];
    piverView_ = [[UIPickerView alloc] initWithFrame:CGRectMake(0, 44, r.size.width, 216)];
    piverView_.delegate = self;
    piverView_.dataSource = self;
    piverView_.showsSelectionIndicator = YES;
    piverView_.backgroundColor = [UIColor whiteColor];
    [piverView_ selectRow:selectIndex_ inComponent:0 animated:NO];

    //add Done button
    toolBar_ = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, r.size.width, 44)];
    toolBar_.barStyle = UIBarStyleBlackTranslucent;
    [toolBar_ sizeToFit];
    UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:self action:nil];
    UIBarButtonItem *done = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(eventDidPushDone:)];
    NSArray *items = @[space, done];
    [toolBar_ setItems:items animated:YES];
    toolBar_.barStyle = UIBarStyleBlackTranslucent;

    //create uiview(baseview)
    baseView_ = [[UIView alloc] init];

    [baseView_ addSubview:piverView_];
    [baseView_ addSubview:toolBar_];

    CGSize ScreenSize = UIScreen.mainScreen.bounds.size;
    baseView_.frame = CGRectMake(0.0, 0.0, toolBar_.frame.size.width, piverView_.frame.size.height + toolBar_.frame.size.height);
    baseView_.frame = CGRectMake(0.0, ScreenSize.height - baseView_.frame.size.height, toolBar_.frame.size.width, piverView_.frame.size.height + toolBar_.frame.size.height);

    //create backview
    backView_ = [[UIView alloc] initWithFrame:CGRectMake(0.0, 0.0, ScreenSize.width, ScreenSize.height)];
    backView_.backgroundColor = [UIColor grayColor];
    backView_.alpha = 0.5;

    UIViewController *topController = UIApplication.sharedApplication.keyWindow.rootViewController;
    [topController.view addSubview:backView_];
    [topController.view addSubview:baseView_];

}

//push Done button
-(void)eventDidPushDone:(id)sender
{
    if (delegate_ != nil) {
        selectIndex_ = [piverView_ selectedRowInComponent:0];
        [delegate_ onSelectPickerItem:[piverView_ selectedRowInComponent:0] obj:self];
    }
    //close pickerview
    if (backView_) {
        [backView_ removeFromSuperview];

    }
    if (baseView_) {
        [baseView_ removeFromSuperview];
    }

    piverView_ = nil;

}


//get component number(UIPickerView)
- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView
{
    return 1;
}

//get row numner(UIPickerView)
- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component
{
    if (pickerItems_ == nil) {
        return 0;
    }
    else {
        return [pickerItems_ count];
    }
}

//get picker row string(UIPickerView)
-(NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component
{
    return [self getItem:row];

}

//select changed(UIPickerView)
- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component
{
    selectIndex_ = row;
}

@end
