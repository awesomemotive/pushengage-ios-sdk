//
//  ViewController.h
//  PushNotificationObjcSample
//
//  Created by Abhishek on 14/06/21.
//

#import <UIKit/UIKit.h>

@interface ViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>

@property (weak, nonatomic) IBOutlet UIButton *requestPermissionButton;
@property (strong, nonatomic) IBOutlet UITableView *tableView;
@property (strong, nonatomic) IBOutlet UITextView *textView;
typedef NS_ENUM(NSUInteger, ApiAction) {
    addSegment = 0,
    removeSegment,
    addDynamicSegement,
    addAttribute,
    deleteAttribute,
    addProfileId,
    getSubscriberDetails,
    getAttribute,
    setAttributes,
    sendGoal,
    triggerCampaigns,
    enableAutomatedNotification,
    disableAutomatedNotification
};

@end

