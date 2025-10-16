#import <UIKit/UIKit.h>

@protocol SelectPickerTableDelegate
- (void)onSelectPickerItem:(NSInteger)position obj:(id)obj;
@end

@interface PickerTableView : NSObject<UIPickerViewDelegate, UIPickerViewDataSource>
{
    id<SelectPickerTableDelegate> __unsafe_unretained delegate_;  //add "__unsafe_unretained" before delegate_
    UIView *baseView_;
    UIPickerView *piverView_;
    UIToolbar *toolBar_;

    UIView *backView_;
    NSArray *pickerItems_;
    long selectIndex_;
}

@property(assign, nonatomic) long selectIndex;
@property(assign, nonatomic) id<SelectPickerTableDelegate> delegate;

//set item list
- (void) setItemList:(NSArray *)items;

//get item
- (NSString *) getItem:(NSInteger)position;

//get object
- (id) getObject:(NSInteger)position;

//show pickerview
-(void)show;

@end
