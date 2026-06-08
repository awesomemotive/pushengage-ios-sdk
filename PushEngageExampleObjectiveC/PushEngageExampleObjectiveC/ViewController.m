//
//  ViewController.m
//  PushNotificationObjcSample
//
//  Created by Abhishek on 14/06/21.
//

#import "ViewController.h"
@import PushEngage;

@interface ViewController ()
@property (strong, nonatomic) NSArray<NSString *> *datalist;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.navigationItem.title = @"PushEngage Demo";
    self.datalist = @[@"Add Segment",
                      @"Remove segments",
                      @"Add Dynamic Segments",
                      @"Add Subscriber Attributes",
                      @"Delete Attributes",
                      @"Add Profile Id",
                      @"Get Subscriber Details",
                      @"Get Subscriber ID",
                      @"Get Subscriber Attributes",
                      @"Set Subscriber Attributes",
                      @"Send Goal",
                      @"Trigger Campaigns",
                      @"Enable Automated Notification",
                      @"Disable Automated Notification",
                      @"Check Permission Status",
                      @"Unsubscribe",
                      @"Subscribe",
                      @"Get Subscription Status",
                      @"Get Notification Status",
                      @"Track Event",
                      @"Identify",
                      @"Logout"];
    self.textView.text = nil;
    self.textView.layer.borderWidth = 0.5;
    self.textView.layer.borderColor = UIColor.blackColor.CGColor;
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss:)];
    tapGesture.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer: tapGesture];
    UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(requestPermissionTapped:)];
    [self.requestPermissionButton addGestureRecognizer:tapGestureRecognizer];
}

- (void)requestPermissionTapped:(UITapGestureRecognizer *)sender {
    [self.requestPermissionButton sendActionsForControlEvents:UIControlEventTouchUpInside];
    
    [PushEngage requestNotificationPermissionWithCompletion:^(BOOL response, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                NSString *errorMessage = [NSString stringWithFormat:@"❌ Error requesting notification permission: %@", error.localizedDescription];
                self.textView.text = errorMessage;
                NSLog(@"%@", errorMessage);
            } else if (response) {
                NSString *successMessage = @"✅ Notification permission granted successfully!";
                self.textView.text = successMessage;
                NSLog(@"%@", successMessage);
            } else {
                NSString *deniedMessage = @"❌ Notification permission denied by user";
                self.textView.text = deniedMessage;
                NSLog(@"%@", deniedMessage);
            }
        });
    }];
}

- (void)checkPermissionStatus {
    NSString *status = [PushEngage getNotificationPermissionStatus];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *statusMessage;
        if ([status isEqualToString:@"granted"]) {
            statusMessage = @"✅ Notification permission status: GRANTED\nNotifications are allowed";
        } else if ([status isEqualToString:@"denied"]) {
            statusMessage = @"❌ Notification permission status: DENIED\nNotifications are not allowed";
        } else if ([status isEqualToString:@"notYetRequested"]) {
            statusMessage = @"⏳ Notification permission status: NOT YET REQUESTED\nPermission has not been requested from the user";
        } else {
            statusMessage = [NSString stringWithFormat:@"❓ Unknown permission status: %@", status];
        }
        self.textView.text = statusMessage;
        NSLog(@"%@", statusMessage);
    });
}

- (void)unsubscribeFromNotifications {
    [PushEngage unsubscribeWithCompletionHandler:^(BOOL response, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                NSString *errorMessage = [NSString stringWithFormat:@"❌ Error unsubscribing: %@", error.localizedDescription];
                self.textView.text = errorMessage;
                NSLog(@"%@", errorMessage);
            } else if (response) {
                NSString *successMessage = @"✅ Successfully unsubscribed from push notifications\nYou will no longer receive notifications";
                self.textView.text = successMessage;
                NSLog(@"%@", successMessage);
            } else {
                NSString *failureMessage = @"❌ Failed to unsubscribe from push notifications\nPlease try again";
                self.textView.text = failureMessage;
                NSLog(@"%@", failureMessage);
            }
        });
    }];
}

- (void)subscribeToNotifications {
    [PushEngage subscribeWithCompletionHandler:^(BOOL response, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                NSString *errorMessage = [NSString stringWithFormat:@"❌ Error subscribing: %@", error.localizedDescription];
                self.textView.text = errorMessage;
                NSLog(@"%@", errorMessage);
            } else if (response) {
                NSString *successMessage = @"✅ Successfully subscribed to push notifications\nYou will now receive notifications";
                self.textView.text = successMessage;
                NSLog(@"%@", successMessage);
            } else {
                NSString *failureMessage = @"❌ Failed to subscribe to push notifications\nPlease try again";
                self.textView.text = failureMessage;
                NSLog(@"%@", failureMessage);
            }
        });
    }];
}

- (void) dismiss:(UITapGestureRecognizer *)sender {
    [self.textView resignFirstResponder];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return  self.datalist.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell" forIndexPath:indexPath];
    cell.textLabel.text = [self.datalist objectAtIndex:indexPath.row];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    self.textView.text = NULL;
    ViewController * __block blockSelf = self;
    ApiAction action = indexPath.row;
    switch (action) {
        case addAttribute: {
            
            [PushEngage addSubscriberAttributes:@{@"name" : @"Abhishek",
                                                  @"gender" : @"male",
                                                  @"place" : @"banglore",
                                                  @"phoneNo" : @91231114}
                              completionHandler:^(BOOL response, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (response) {
                        blockSelf.textView.text = @"Attribute(s) updated for subscriber successfully";
                    } else {
                        blockSelf.textView.text = [error debugDescription];
                    }
                    blockSelf = nil;
                });
            }];
            break;
        }
        case addSegment: {
            [PushEngage addSegments:@[@"segmentTest1"]
                               completionHandler:^(BOOL response, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (response) {
                        blockSelf.textView.text = @"Subscriber added to segment successfully";
                    } else {
                        blockSelf.textView.text = [error debugDescription];
                    }
                    blockSelf = nil;
                });
            }];
            break;
        }
        case addDynamicSegement: {
            [PushEngage addDynamicSegments:@[@{@"name": @"dynamicOne" ,
                                                     @"duration": @10},
                                                   @{@"name" : @"segemt1",
                                                     @"duration" : @20},
                                                   @{@"name" : @"segemt3",
                                                     @"duration" : @30}]
                               completionHandler:^(BOOL response, NSError * _Nullable error) {
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (response) {
                        blockSelf.textView.text = @"Subscriber added to the dynamic segment successfully";
                    } else {
                        blockSelf.textView.text = [error debugDescription];
                    }
                    blockSelf = nil;
                });
            }];
            break;
        }
        
        case deleteAttribute: {
            [PushEngage deleteSubscriberAttributesFor:@[@"name"]
                               completionHandler:^(BOOL response, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (response) {
                        blockSelf.textView.text = @"Attribute(s) deleted for subscriber successfully";
                    } else {
                        blockSelf.textView.text = [error debugDescription];
                    }
                    blockSelf = nil;
                });
            }];
            break;
        }
            
        case removeSegment: {
            [PushEngage removeSegments:@[@"segmentTest1"]
                              completionHandler:^(BOOL response, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (response) {
                        blockSelf.textView.text = @"Subscriber removed from the segment(s)";
                    } else {
                        blockSelf.textView.text = [error debugDescription];
                    }
                    blockSelf = nil;
                });
            }];
            break;
        }
        case addProfileId: {
            [PushEngage addProfileFor: @"abhishekkumarthakur@gmail.com"
                           completionHandler:^(BOOL response, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (response) {
                        blockSelf.textView.text = @"successfully added profile";
                    } else {
                        blockSelf.textView.text = @"error in adding profile";
                    }
                    blockSelf = nil;
                });
            }];
            break;
        }
            
        case  getSubscriberDetails: {
            [PushEngage getSubscriberDetailsFor: @[]
                               completionHandler:^(SubscriberDetailsData * _Nullable response,
                                                   NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                        if (response) {
                            NSDictionary *raw = response.rawFields;
                            NSArray *segments = raw[@"segments"];
                            NSString *segmentsString = [segments isKindOfClass:[NSArray class]]
                                ? [segments componentsJoinedByString:@", "]
                                : @"(null)";
                            NSString *responseString = [NSString stringWithFormat:@"device: %@, user_agent: %@, country: %@, ts_created: %@, state: %@, city: %@, host: %@, device_type: %@, timezone: %@, segments: %@",
                                                        raw[@"device"] ?: @"(null)",
                                                        raw[@"user_agent"] ?: @"(null)",
                                                        raw[@"country"] ?: @"(null)",
                                                        raw[@"ts_created"] ?: @"(null)",
                                                        raw[@"state"] ?: @"(null)",
                                                        raw[@"city"] ?: @"(null)",
                                                        raw[@"host"] ?: @"(null)",
                                                        raw[@"device_type"] ?: @"(null)",
                                                        raw[@"timezone"] ?: @"(null)",
                                                        segmentsString];

                            self.textView.text = responseString;
                        } else {
                            self.textView.text = error.localizedDescription;
                        }
                        blockSelf = nil;
                    });
            }];
            break;
        }
            
        case getSubscriberId: {
            [PushEngage getSubscriberIdWithCompletion:^(NSString * _Nullable subscriberId) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (subscriberId) {
                        NSString *message = [NSString stringWithFormat:@"Subscriber ID: %@", subscriberId];
                        blockSelf.textView.text = message;
                        NSLog(@"%@", message);
                    } else {
                        NSString *message = @"User is not subscribed (no subscriber ID available)";
                        blockSelf.textView.text = message;
                        NSLog(@"%@", message);
                    }
                    blockSelf = nil;
                });
            }];
            break;
        }
            
        case getAttribute: {
            [PushEngage getSubscriberAttributesWithCompletionHandler:^(NSDictionary<NSString *,id> * _Nullable response,
                                                                   NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (response) {
                        blockSelf.textView.text = [response description];
                    } else {
                        NSLog(@"error message %@", error);
                    }
                    blockSelf = nil;
                });
            }];
            break;
        }
        case setAttributes: {
            [PushEngage setSubscriberAttributes:@{@"gender" : @"male"}
                              completionHandler:^(BOOL response, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (response) {
                        blockSelf.textView.text = @"Attribute(s) set for subscriber successfully";
                    } else {
                        blockSelf.textView.text = [error debugDescription];
                    }
                    blockSelf = nil;
                });
            }];
            break;
        }
        case sendGoal: {
            Goal *goal = [[Goal alloc] initWithName:@"revenue" count:@(1.0) value:@(2.0)];

            [PushEngage sendGoalWithGoal:goal completionHandler:^(BOOL response, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (error) {
                        blockSelf.textView.text = error.localizedDescription;
                    } else {
                        blockSelf.textView.text = @"Goal Added Successfully";
                    }
                    blockSelf = nil;
                });
            }];
            break;
        }
        case triggerCampaigns: {
            TriggerCampaign *triggerCampaign = [[TriggerCampaign alloc] initWithCampaignName:@"promotion" eventName:@"product" referenceId:@"" profileId:@"" data:@{@"title" : @"New Product"}];
            [PushEngage sendTriggerEventWithTriggerCampaign: triggerCampaign completionHandler:^(BOOL response, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (error) {
                        blockSelf.textView.text = error.localizedDescription;
                    } else {
                        blockSelf.textView.text = @"Send Trigger Alert Successfull";
                    }
                    blockSelf = nil;
                });
            }];
            break;
        }
        case enableAutomatedNotification: {
            [PushEngage automatedNotificationWithStatus: TriggerStatusTypeEnabled completionHandler:^(BOOL response, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (error) {
                        blockSelf.textView.text = error.localizedDescription;
                    } else {
                        blockSelf.textView.text = @"Trigger enabled successfully";
                    }
                    blockSelf = nil;
                });
            }];
            break;
        }
        case disableAutomatedNotification: {
            [PushEngage automatedNotificationWithStatus: TriggerStatusTypeDisabled completionHandler:^(BOOL response, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (error) {
                        blockSelf.textView.text = error.localizedDescription;
                    } else {
                        blockSelf.textView.text = @"Trigger disabled successfully";
                    }
                    blockSelf = nil;
                });
            }];
            break;
        }
        case checkPermissionStatus: {
            [self checkPermissionStatus];
            break;
        }
        case unsubscribe: {
            [self unsubscribeFromNotifications];
            break;
        }
        case subscribe: {
            [self subscribeToNotifications];
            break;
        }
        case getSubscriptionStatus: {
            [PushEngage getSubscriptionStatusWithCompletionHandler:^(BOOL isSubscribed, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (error) {
                        NSString *errorMessage = [NSString stringWithFormat:@"❌ Error getting subscription status: %@", error.localizedDescription];
                        blockSelf.textView.text = errorMessage;
                        NSLog(@"%@", errorMessage);
                    } else {
                        NSString *statusIcon = isSubscribed ? @"✅" : @"❌";
                        NSString *statusText = isSubscribed ? @"SUBSCRIBED" : @"UNSUBSCRIBED";
                        NSString *message = [NSString stringWithFormat:@"%@ Subscription Status: %@\n\nThe user is currently %@ push notifications.",
                                           statusIcon, 
                                           statusText,
                                           isSubscribed ? @"subscribed to" : @"unsubscribed from"];
                        blockSelf.textView.text = message;
                        NSLog(@"%@", message);
                    }
                    blockSelf = nil;
                });
            }];
            break;
        }
        case getSubscriptionNotificationStatus: {
            [PushEngage getSubscriptionNotificationStatusWithCompletionHandler:^(BOOL canReceiveNotifications, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (error) {
                        NSString *errorMessage = [NSString stringWithFormat:@"❌ Error getting notification status: %@", error.localizedDescription];
                        blockSelf.textView.text = errorMessage;
                        NSLog(@"%@", errorMessage);
                    } else {
                        NSString *statusIcon = canReceiveNotifications ? @"✅" : @"❌";
                        NSString *statusText = canReceiveNotifications ? @"CAN RECEIVE" : @"CANNOT RECEIVE";
                        NSString *message = [NSString stringWithFormat:@"%@ Notification Status: %@\n\nThe user %@ push notifications.\n\nThis combines both subscription status and notification permission:\n- Must be subscribed (has_unsubscribed = 0 AND notification_disabled = 0)\n- Must have notification permission granted",
                                           statusIcon,
                                           statusText,
                                           canReceiveNotifications ? @"can receive" : @"cannot receive"];
                        blockSelf.textView.text = message;
                        NSLog(@"%@", message);
                    }
                    blockSelf = nil;
                });
            }];
            break;
        }
        case trackEvent: {
            NSDictionary *properties = @{@"amount": @19.99,
                                         @"currency": @"USD",
                                         @"is_trial": @NO,
                                         @"items": @3};
            [PushEngage trackEventWithName:@"MySite.AddToCart"
                                properties:properties
                                 profileId:nil
                                  provider:nil
                                 eventType:nil
                         completionHandler:^(BOOL response, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (response) {
                        blockSelf.textView.text = [NSString stringWithFormat:@"✅ Event 'MySite.AddToCart' tracked with properties:\n%@", properties];
                    } else {
                        blockSelf.textView.text = error.localizedDescription;
                    }
                    blockSelf = nil;
                });
            }];
            break;
        }
        case identify: {
            NSDictionary *fields = @{@"email": @"test@example.com",
                                     @"first_name": @"Alice",
                                     @"profile_id": @"user-42"};
            [PushEngage identifyWithFields:fields
                         completionHandler:^(BOOL response, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (response) {
                        blockSelf.textView.text = [NSString stringWithFormat:@"✅ Subscriber identified with fields:\n%@", fields];
                    } else {
                        blockSelf.textView.text = error.localizedDescription;
                    }
                    blockSelf = nil;
                });
            }];
            break;
        }
        case logout: {
            // Pass nil to use the default PII set (first_name, last_name, email,
            // phone, gender, dob, profile_id); pass a non-empty array to
            // clear specific fields only.
            NSArray<NSString *> *fieldNames = @[@"email", @"profile_id"];
            [PushEngage logoutWithFieldNames:fieldNames
                           completionHandler:^(BOOL response, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (response) {
                        blockSelf.textView.text = [NSString stringWithFormat:@"✅ Logged out fields:\n%@", fieldNames];
                    } else {
                        blockSelf.textView.text = error.localizedDescription;
                    }
                    blockSelf = nil;
                });
            }];
            break;
        }
    }
}

@end
