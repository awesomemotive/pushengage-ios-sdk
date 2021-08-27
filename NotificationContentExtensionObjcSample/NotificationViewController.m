//
//  NotificationViewController.m
//  NotificationContentExtensionObjcSample
//
//  Created by Abhishek on 26/08/21.
//

#import "NotificationViewController.h"
#import <UserNotifications/UserNotifications.h>
#import <UserNotificationsUI/UserNotificationsUI.h>

@import PushEngage;
@import UIKit;
// https://stackoverflow.com/questions/50575558/ios-notification-content-extension-add-buttons-in-storyboard-and-handle-the-cli

@interface NotificationViewController () <UNNotificationContentExtension>

@property IBOutlet UILabel *label;
@property (weak, nonatomic) IBOutlet UIImageView *imageView;
@property (weak, nonatomic) IBOutlet UIButton *firstButton;
@property (weak, nonatomic) IBOutlet UIButton *secondButton;

@end

@implementation NotificationViewController

- (IBAction)firstbuttonAction:(id)sender {
    // do what action you want to perform.
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any required interface initialization here.
}

- (void)didReceiveNotification:(UNNotification *)notification {
    
    NotificationViewController * __block blockSelf = self;
    CustomUIModel *object = [PushEngage getCustomUIPayLoadFor:notification.request];
    dispatch_async(dispatch_get_main_queue(), ^{
        blockSelf.label.text = object.title;
        blockSelf.imageView.image = object.image;
        [blockSelf.firstButton setTitle:object.buttons.firstObject.text forState:UIControlStateNormal];
        [blockSelf.secondButton setTitle:object.buttons.lastObject.text forState:UIControlStateNormal];
        blockSelf = NULL;
    });
}

@end
