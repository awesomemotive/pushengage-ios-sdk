//
//  AddToCart.m
//  PushNotificationObjcSample
//
//  Created by Abhishek on 14/06/21.
//

#import "AddToCart.h"
#import "SportsViewcontroller.h"

@import PushEngage;
@interface AddToCart ()
@property (strong, nonatomic) UIButton *addToCart;
@property (strong, nonatomic) UIButton *checkout;
@end

@implementation AddToCart

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.whiteColor;
    self.navigationItem.title = @"Add To Cart";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"next" style:UIBarButtonItemStylePlain target:self action:@selector(navigateToSports:)];
    [self setupButton];
}

- (void) navigateToSports:(id) sender {
    SportsViewcontroller *sports = [SportsViewcontroller new];
    [self.navigationController pushViewController:sports animated:YES];
}

- (void) setupButton {
    
    self.addToCart = [[UIButton alloc] init];
    [self.addToCart setTitle:@"add To Cart" forState:UIControlStateNormal];
    [self.addToCart setTintColor:UIColor.blackColor];
    [self.addToCart setBackgroundColor:UIColor.linkColor];
    [self.addToCart addTarget:self action:@selector(addToCartAction:) forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[[self.addToCart.heightAnchor constraintEqualToConstant:80],
                                              [self.addToCart.widthAnchor constraintEqualToConstant:150]]];

    self.checkout = [[UIButton alloc] init];
    [self.checkout setTitle:@"checkout" forState:UIControlStateNormal];
    [self.checkout setTintColor:UIColor.blackColor];
    [self.checkout setBackgroundColor:UIColor.linkColor];
    [self.checkout addTarget:self action:@selector(checkoutAction:) forControlEvents:UIControlEventTouchUpInside];
    [NSLayoutConstraint activateConstraints:@[[self.checkout.heightAnchor constraintEqualToConstant:80],
                                              [self.checkout.widthAnchor constraintEqualToConstant:150]]];
    
    
    
    UIStackView *stackView = [[UIStackView alloc] initWithArrangedSubviews:@[self.addToCart,
                                                                             self.checkout]];
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.distribution = UIStackViewDistributionFillEqually;
    stackView.spacing = 20;
    stackView.alignment = UIStackViewAlignmentCenter;
    stackView.translatesAutoresizingMaskIntoConstraints = false;
    [self.view addSubview:stackView];
    [NSLayoutConstraint activateConstraints:@[[stackView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
                                             [stackView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor]]];
}

- (void)addToCartAction:(id)sender {
    AddToCart * __block object =  self;
    
    TriggerCampaign *campaign = [[TriggerCampaign alloc] initWithCampaignName:@"Shopping"
                                                         eventName:@"add to cart" notificationDetails:@[[[TriggerNotification alloc] initWithNotificationURL:[[Input alloc] initWithKey: @"url"value:@"www.google.com"] title:[[Input alloc] initWithKey:@"shoes" value:@"Puma shoes"] message:[[Input alloc] initWithKey:@"message" value:@"check out the sale 50%"] notificationImage:[[Input alloc] initWithKey:@"image_url" value:@"https://images.unsplash.com/photo-1494548162494-384bba4ab999?ixlib=rb-1.2.1&ixid=eyJhcHBfaWQiOjEyMDd9&w=1000&q=80"] bigImage:nil actions:[[Input alloc] initWithKey:@"Okay" value:@"check out the sale 90%"]],
        [[TriggerNotification alloc] initWithNotificationURL:[[Input alloc] initWithKey:@"checkout url" value:@"www.amazon.com"] title:[[Input alloc] initWithKey:@"imported shoes" value:@"Nike shoes"] message:[[Input alloc] initWithKey:@"messages" value:@"check out the sale 90%"] notificationImage:nil bigImage:nil actions:[[Input alloc] initWithKey:@"Grab a shoes" value:@"www.pushengage.com"]]
         ] data:nil];
    
    [PushEngage createTriggerCampaignFor:campaign completionHandler:^(BOOL response) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (response) {
                [object showAlert:[NSString stringWithFormat:@"successfully for add to cart."]];
                object = nil;
            } else {
                NSLog(@"error to add trigger");
            }
        });
    }];
}

- (void) showAlert:(NSString *) message {
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Info Alert"
                                   message:message
                                   preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"dismiss" style:UIAlertActionStyleDefault
       handler:^(UIAlertAction * action) {}];

    [alert addAction:defaultAction];
    [self presentViewController:alert animated:YES completion:nil];
}

-(void)checkoutAction:(id)sender {
    AddToCart * __block object =  self;
    
    TriggerCampaign *campaign = [[TriggerCampaign alloc] initWithCampaignName:@"Shopping"
                                                         eventName:@"checkout"
                                                         notificationDetails:nil data:@{@"revenue" : @"40"}];
    [PushEngage createTriggerCampaignFor:campaign completionHandler:^(BOOL response) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (response) {
                [object showAlert:[NSString stringWithFormat:@" sucessfully checkout trigger added."]];
                object = nil;
            } else {
                NSLog(@"error add checkout trigger");
            }
        });
    }];
}


@end
