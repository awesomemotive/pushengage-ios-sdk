//
//  ViewController.m
//  PushNotificationObjcSample
//
//  Created by Abhishek on 14/06/21.
//

#import "ViewController.h"
#import "AddToCart.h"
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
                      @"Get Subscriber Attributes",
                      @"Set Subscriber Attributes" ];
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
    [PushEngage requestNotificationPermission];
}

- (void) navigateToAddToCart {
    AddToCart *controller = [AddToCart new];
    [self.navigationController pushViewController:controller animated:YES];
    
}

- (void) nextView:(id) sender {
    [self navigateToAddToCart];
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
            
            [PushEngage addWithAttributes:@{@"name" : @"Abhishek",
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
        
//        case trigger: {
//            [PushEngage updateTriggerWithStatus: NO
//                               completionHandler:^(BOOL response, NSError * _Nullable error) {
//                dispatch_async(dispatch_get_main_queue(), ^{
//                    if (response) {
//                        blockSelf.textView.text = @"added trigger successfully";
//                    } else {
//                        blockSelf.textView.text = [error debugDescription];
//                    }
//                    blockSelf = nil;
//                });
//            }];
//            break;
//        }
            
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
            [PushEngage getSubscriberDetailsFor: @[@"country"]
                               completionHandler:^(SubscriberDetailsData * _Nullable response,
                                                   NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                        if (response) {
                            NSString *responseString = [NSString stringWithFormat:@"device: %@, user_agent: %@, country: %@, ts_created: %@, state: %@, city: %@, host: %@, device_type: %@, timezone: %@, segments: %@",
                                                        response.device ?: @"(null)",
                                                        response.userAgent ?: @"(null)",
                                                        response.country ?: @"(null)",
                                                        response.tsCreated ?: @"(null)",
                                                        response.state ?: @"(null)",
                                                        response.city ?: @"(null)",
                                                        response.host ?: @"(null)",
                                                        response.deviceType ?: @"(null)",
                                                        response.timezone ?: @"(null)",
                                                        [response.segments componentsJoinedByString:@", "] ?: @"(null)"];
                            
                            self.textView.text = responseString;
                        } else {
                            self.textView.text = error.localizedDescription;
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
            [PushEngage setWithAttributes:@{@"gender" : @"male"}
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
    }
}

@end
