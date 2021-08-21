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
    self.datalist = @[@"Add Segment", @"Remove segment",@"Add dynamic",
                    @"AddAttribute", @"Delete attribute",@"Trigger", @"add profileId", @"getSubscriberDetails",
                    @"getAttribute", @"check subscriber" ];
    self.textView.text = nil;
    self.textView.layer.borderWidth = 0.5;
    self.textView.layer.borderColor = UIColor.blackColor.CGColor;
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismiss:)];
    tapGesture.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer: tapGesture];
    UIBarButtonItem *button = [[UIBarButtonItem alloc] initWithTitle:@"next"
                                                       style:UIBarButtonItemStylePlain
                                                       target:self
                                                       action:@selector(nextView:)];
    self.navigationItem.rightBarButtonItem = button;
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
            
            [PushEngage updateWithAttributes:@{@"name" : @"Abhishek",
                                                     @"gender" : @"male",
                                                     @"place" : @"banglore",
                                                     @"phoneNo" : @91231114}
                               completionHandler:^(BOOL response, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (response) {
                        blockSelf.textView.text = @"added attribute succesfully";
                    } else {
                        blockSelf.textView.text = [error debugDescription];
                    }
                    blockSelf = nil;
                });
            }];
            break;
        }
        case addSegment: {
            [PushEngage updateWithSegments:@[@"segmentTest1"] with:SegmentActionsUpdate
                               completionHandler:^(BOOL response, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (response) {
                        blockSelf.textView.text = @"added segment successfully";
                    } else {
                        blockSelf.textView.text = [error debugDescription];
                    }
                    blockSelf = nil;
                });
            }];
            break;
        }
        case addDynamicSegement: {
            [PushEngage updateWithDynamic:@[@{@"name": @"dynamicOne" ,
                                                     @"duration": @10},
                                                   @{@"name" : @"segemt1",
                                                     @"duration" : @20},
                                                   @{@"name" : @"segemt3",
                                                     @"duration" : @30}]
                               completionHandler:^(BOOL response, NSError * _Nullable error) {
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (response) {
                        blockSelf.textView.text = @"successfully added dynamic segment";
                    } else {
                        blockSelf.textView.text = [error debugDescription];
                    }
                    blockSelf = nil;
                });
            }];
            break;
        }
        
        case deleteAttribute: {
            [PushEngage deleteAttributeWithValues:@[@"name"]
                               completionHandler:^(BOOL response, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (response) {
                        blockSelf.textView.text = @"deleted attribute successfull";
                    } else {
                        blockSelf.textView.text = [error debugDescription];
                    }
                    blockSelf = nil;
                });
            }];
            break;
        }
            
        case removeSegment: {
            [PushEngage updateWithSegments:@[@"segmentTest1"] with:SegmentActionsRemove
                              completionHandler:^(BOOL response, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (response) {
                        blockSelf.textView.text = @"Segment added successfully";
                    } else {
                        blockSelf.textView.text = [error debugDescription];
                    }
                    blockSelf = nil;
                });
            }];
            break;
        }
        
        case trigger: {
            [PushEngage updateTriggerWithStatus: NO
                               completionHandler:^(BOOL response, NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (response) {
                        blockSelf.textView.text = @"added trigger successfully";
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
            [PushEngage getSubscriberDetailsFor: @[@"country"]
                               completionHandler:^(SubscriberDetailsData * _Nullable response,
                                                   NSError * _Nullable error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (response) {
                        blockSelf.textView.text = [response description];
                    } else {
                        blockSelf.textView.text = @"error to get subscription details";
                    }
                    blockSelf = nil;
                });
            }];
            break;
        }
            
        case getAttribute: {
            [PushEngage getAttributeWithCompletionHandler:^(NSDictionary<NSString *,id> * _Nullable response,
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
    }
}

@end
