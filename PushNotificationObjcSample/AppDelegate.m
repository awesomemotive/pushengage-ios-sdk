//
//  AppDelegate.m
//  PushNotificationObjcSample
//
//  Created by Abhishek on 14/06/21.
//

#import "AppDelegate.h"
#import "AddToCart.h"
#import "SportsViewcontroller.h"

@import UserNotifications;
@import PushEngage;

@interface AppDelegate ()

@end

@implementation AppDelegate


- (instancetype)init
{
    self = [super init];
    if (self) {
        [PushEngage swizzleInjectionWithIsEnabled: YES];
    }
    return self;
}

typedef void (^PEnotificationOpenHandler)(PENotificationOpenResult * nonnull);
typedef void (^_Nonnull PENotificationDisplayHandler)(PENotification * _Nullable);
typedef void (^_Nullable SilentPushHandler)(UIBackgroundFetchResult);

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    if (@available(iOS 10.0, *)) {
        UNUserNotificationCenter.currentNotificationCenter.delegate = self;
    }
    
    [PushEngage setNotificationWillShowInForegroundHandlerWithBlock:^(PENotification * _Nonnull notification,
                                                                     PENotificationDisplayHandler completion) {
        if (notification.contentAvailable == 1) {
            completion(nil);
        } else {
            completion(notification);
        }
    }];
    
    PEnotificationOpenHandler actionHandler = ^void(PENotificationOpenResult *result) {
        if ([result.notificationAction.actionID isEqualToString: @"ShoesScreen"]) {
            AddToCart *controller = [AddToCart new];
            UINavigationController *navigationController = (UINavigationController *) application.windows.firstObject.rootViewController;
            [navigationController popToRootViewControllerAnimated:YES];
            [navigationController pushViewController:controller animated:YES];
        }
    };
    
    application.applicationIconBadgeNumber = 0;
    [PushEngage setEnvironmentWithEnvironment:EnvironmentStaging];
    [PushEngage setAppIDWithId:@"3ca8257d-1f40-41e0-88bc-ea28dc6495ef"];
    [PushEngage setInitialInfoFor:application with:launchOptions];
    [PushEngage setNotificationOpenHandlerWithBlock:actionHandler];
    [PushEngage setEnableLogging:true];
    return YES;
}


#pragma mark - UISceneSession lifecycle


- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options  API_AVAILABLE(ios(13.0)){
    // Called when a new scene session is being created.
    // Use this method to select a configuration to create the new scene with.
    return [[UISceneConfiguration alloc] initWithName:@"Default Configuration" sessionRole:connectingSceneSession.role];
}


- (void)application:(UIApplication *)application didDiscardSceneSessions:(NSSet<UISceneSession *> *)sceneSessions  API_AVAILABLE(ios(13.0)){
    // Called when the user discards a scene session.
    // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
    // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
}

#pragma mark - UNUsersNotificationDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(UNNotificationResponse *)response withCompletionHandler:(void (^)(void))completionHandler  API_AVAILABLE(ios(10.0)){
    NSLog(@"userinfo  from appdelegate %@", response.notification.request.content.userInfo);
    completionHandler();
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler  API_AVAILABLE(ios(10.0)){
    UNNotificationPresentationOptions option  =  (UNNotificationPresentationOptions)7;
    NSLog(@"will recive notification is from Appdeledate %lu", (unsigned long)option);
    completionHandler(option);
}

#pragma  mark - Remote notification delegate

- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    const unsigned *tokenBytes = [deviceToken bytes];
        NSString *hexToken = [NSString stringWithFormat:@"%08x%08x%08x%08x%08x%08x%08x%08x",
                             ntohl(tokenBytes[0]), ntohl(tokenBytes[1]), ntohl(tokenBytes[2]),
                             ntohl(tokenBytes[3]), ntohl(tokenBytes[4]), ntohl(tokenBytes[5]),
                             ntohl(tokenBytes[6]), ntohl(tokenBytes[7])];
    NSLog(@"device token from appdelegate %@", hexToken);
}

@end
