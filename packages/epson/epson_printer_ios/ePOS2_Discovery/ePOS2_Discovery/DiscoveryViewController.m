#import "DiscoveryViewController.h"
#import "ShowMsg.h"

@interface DiscoveryViewController()<UITableViewDataSource, UITableViewDelegate, Epos2DiscoveryDelegate>
@end

@implementation DiscoveryViewController

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    _deviceView.dataSource = self;
    _deviceView.delegate = self;

    portTypeList_ = [[PickerTableView alloc] init];
    NSMutableArray *items = [[NSMutableArray alloc] init];
    [items addObject:NSLocalizedString(@"porttype_all", @"")];
    [items addObject:NSLocalizedString(@"porttype_tcp", @"")];
    [items addObject:NSLocalizedString(@"porttype_bluetooth", @"")];
    [items addObject:NSLocalizedString(@"porttype_usb", @"")];
    [items addObject:NSLocalizedString(@"porttype_bluetooth_le", @"")];

    [portTypeList_ setItemList:items];
    [_buttonPortType setTitle:[portTypeList_ getItem:0] forState:UIControlStateNormal];
    portTypeList_.delegate = self;

    deviceModelList_ = [[PickerTableView alloc] init];
    items = [[NSMutableArray alloc] init];
    [items addObject:NSLocalizedString(@"model_all", @"")];

    [deviceModelList_ setItemList:items];
    [_buttonDeviceModel setTitle:[deviceModelList_ getItem:0] forState:UIControlStateNormal];
    deviceModelList_.delegate = self;

    deviceTypeList_ = [[PickerTableView alloc] init];
    items = [[NSMutableArray alloc] init];
    [items addObject:NSLocalizedString(@"type_all", @"")];

    [deviceTypeList_ setItemList:items];
    [_buttonDeviceType setTitle:[deviceTypeList_ getItem:0] forState:UIControlStateNormal];
    deviceTypeList_.delegate = self;

    _broadcastText.text = @"255.255.255.255";

    scrollBaseView_ = self.scrollView;
    self.scrollView.contentSize = _itemView.frame.size;
    
    _buttonStop.enabled = NO;

    [self setDoneToolbar];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSInteger rowNumber = [deviceList_ count];
    return rowNumber;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *identifier = @"basis-cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier];
    }

    if (indexPath.row >= 0 && indexPath.row < [deviceList_ count]) {
        cell.textLabel.text = [(Epos2DeviceInfo *)deviceList_[indexPath.row] getDeviceName];
        cell.detailTextLabel.text = [(Epos2DeviceInfo *)deviceList_[indexPath.row] getTarget];
    }

    return cell;
}

- (void)onSelectPickerItem:(NSInteger)position obj:(id)obj
{
    if (obj == portTypeList_) {
        [_buttonPortType setTitle:[portTypeList_ getItem:position] forState:UIControlStateNormal];
    }
    else if (obj == deviceModelList_) {
        [_buttonDeviceModel setTitle:[deviceModelList_ getItem:position] forState:UIControlStateNormal];
    }
    else if (obj == deviceTypeList_) {
        [_buttonDeviceType setTitle:[deviceTypeList_ getItem:position] forState:UIControlStateNormal];
    }
    else {
        ; //do nothing
    }
}

- (void)setDoneToolbar
{
    UIToolbar *doneToolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 44)];
    doneToolbar.barStyle = UIBarStyleBlackTranslucent;

    [doneToolbar sizeToFit];
    UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:self action:nil];
    UIBarButtonItem *doneButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(doneKeyboard:)];

    NSMutableArray *items = [NSMutableArray arrayWithObjects:space, doneButton, nil];
    [doneToolbar setItems:items animated:YES];
    _broadcastText.inputAccessoryView = doneToolbar;
}

- (void)doneKeyboard:(id)sender
{
    [_broadcastText resignFirstResponder];
}

- (int)getPortType:(long)index
{
    int result = EPOS2_PORTTYPE_ALL;
    switch (index) {
        case 1:
            result = EPOS2_PORTTYPE_TCP;
            break;
        case 2:
            result = EPOS2_PORTTYPE_BLUETOOTH;
            break;
        case 3:
            result = EPOS2_PORTTYPE_USB;
            break;
        case 4:
            result = EPOS2_PORTTYPE_BLUETOOTH_LE;
            break;
        case 0:
        default:
            result = EPOS2_PORTTYPE_ALL;
            break;
    }
    return result;
}

- (int)getDeviceModel:(long)index
{
    int result = EPOS2_MODEL_ALL;
    switch (index) {
        case 0:
        default:
            result = EPOS2_MODEL_ALL;
            break;
    }
    return result;
}

- (int)getDeviceType:(long)index
{
    int result = EPOS2_TYPE_ALL;
    switch (index) {
        case 0:
        default:
            result = EPOS2_TYPE_ALL;
            break;
    }
    return result;
}

- (IBAction)eventButtonDidPush:(id)sender
{
    switch (((UIView *)sender).tag) {
        case 0:
            [self startDiscovery];
            break;
        case 1:
            [self stopDiscovery];
            break;
        case 2:
            [portTypeList_ show];
            break;
        case 3:
            [deviceModelList_ show];
            break;
        case 4:
            [deviceTypeList_ show];
            break;
        default:
            break;
    }
}

- (void)startDiscovery
{
    int result = EPOS2_SUCCESS;
    Epos2FilterOption *filterOption = nil;

    deviceList_ = [[NSMutableArray alloc] init];
    if (_deviceView != nil) {
        [_deviceView reloadData];
    }

    filterOption = [[Epos2FilterOption alloc] init];
    [filterOption setPortType:[self getPortType:portTypeList_.selectIndex]];
    [filterOption setBroadcast:_broadcastText.text];
    [filterOption setDeviceModel:[self getDeviceModel:deviceModelList_.selectIndex]];
    [filterOption setDeviceType:[self getDeviceType:deviceTypeList_.selectIndex]];

    result = [Epos2Discovery start:filterOption delegate:self];
    if (result != EPOS2_SUCCESS) {
        [ShowMsg showErrorEpos:result method:@"start"];
        return;
    }
    
    _buttonStart.enabled = NO;
    _buttonStop.enabled = YES;
}

- (void)stopDiscovery
{
    int result = EPOS2_SUCCESS;

    result = [Epos2Discovery stop];

    if (result != EPOS2_SUCCESS) {
        [ShowMsg showErrorEpos:result method:@"stop"];
        return;
    }
    
    _buttonStart.enabled = YES;
    _buttonStop.enabled = NO;
}

- (void) onDiscovery:(Epos2DeviceInfo *)deviceInfo
{
    [deviceList_ addObject:deviceInfo];
    [_deviceView reloadData];
}

@end
