//
//  SportsViewcontroller.m
//  PushNotificationObjcSample
//
//  Created by Abhishek on 15/06/21.
//

#import "SportsViewcontroller.h"

@interface SportsViewcontroller ()
@property (strong, nonatomic) UIImageView *sportsImage;
@end

@implementation SportsViewcontroller

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.title = @"Sports view.";
    self.view.backgroundColor = UIColor.whiteColor;
    [self setupView];
    // Do any additional setup after loading the view.
}

- (void) setupView {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    UIImage *imageOfSports = [UIImage imageNamed:@"sport" inBundle:bundle withConfiguration:nil];
    self.sportsImage = [[UIImageView alloc] initWithImage:imageOfSports];
    [self.sportsImage sizeToFit];
    self.sportsImage.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.sportsImage];
    [NSLayoutConstraint activateConstraints:@[[self.sportsImage.centerXAnchor constraintEqualToAnchor: self.view.centerXAnchor],
                                             [self.sportsImage.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
                                             [self.sportsImage.heightAnchor constraintEqualToConstant:300],
                                             [self.sportsImage.widthAnchor constraintEqualToConstant:400]]];
}

@end
