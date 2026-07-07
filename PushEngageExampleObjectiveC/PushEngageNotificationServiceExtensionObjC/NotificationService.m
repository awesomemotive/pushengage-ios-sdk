//
//  NotificationService.m
//  PushEngageNotificationServiceExtensionObjC
//
//  Created by Himshikhar Gayan on 16/02/24.
//

#import "NotificationService.h"
@import PushEngageExtension;

@interface NotificationService ()

@property (nonatomic, strong) void (^contentHandler)(UNNotificationContent *contentToDeliver);
@property (nonatomic, strong) UNMutableNotificationContent *bestAttemptContent;
@property (nonatomic, strong) UNNotificationRequest *request;

@end

@implementation NotificationService

- (void)didReceiveNotificationRequest:(UNNotificationRequest *)request withContentHandler:(void (^)(UNNotificationContent * _Nonnull))contentHandler {
    self.request = request;
    self.contentHandler = contentHandler;
    self.bestAttemptContent = [request.content mutableCopy];
    
    if (self.bestAttemptContent) {
        [PushEngageExtension didReceiveNotificationExtensionRequest:request bestContentHandler:self.bestAttemptContent];
        contentHandler(self.bestAttemptContent);
    }
}

- (void)serviceExtensionTimeWillExpire {

    if (self.contentHandler && self.request && self.bestAttemptContent) {
        UNNotificationContent *content = [PushEngageExtension serviceExtensionTimeWillExpire:self.request content:self.bestAttemptContent];
        if (content) {
            self.contentHandler(content);
            return;
        }
    }
    self.contentHandler(self.bestAttemptContent);
}

@end
