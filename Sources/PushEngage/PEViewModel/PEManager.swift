//
//  PEViewModel.swift
//  PushEngage
//
//  Created by Abhishek on 02/04/21.
//

import Foundation
import UserNotifications
import UIKit

protocol DeviceManagerType {
    func getDeviceToken() -> String
    func setDeviceToken(token: String)
    func getDeviceHash() -> String
    func registerDeviceToServer(with deviceToken: Data)
    func setEnvironment(_ environment: PEEnvironment)
}

protocol SubscriberManagerType {
    func getSubscriberId(completion: @escaping (_ response: String?) -> Void)
    func getSubscriberHash() -> String
    func checkSubscriber(completionHandler: ((_ response: CheckSubscriberData?, _ error: PEError?) -> Void)?)
    func getSubscriberDetails(for fields: [String]?,
                              completionHandler: ((_ response: SubscriberDetailsData?, _ error: PEError?) -> Void)?)
    func getSubscriptionStatus(completionHandler: ((_ isSubscribed: Bool, _ error: PEError?) -> Void)?)
    func getSubscriptionNotificationStatus(completionHandler: ((_ canReceiveNotifications: Bool, _ error: PEError?) -> Void)?)
    func unsubscribe(completionHandler: ((_ response: Bool, _ error: PEError?) -> Void)?)
    func subscribe(completionHandler: ((_ response: Bool, _ error: PEError?) -> Void)?)
}

protocol AppInfoManagerType {
    func getAppId() -> Int?
    func setAppId(key: String)
    func onClickRedirect(to launchURL: String?)
}

protocol NotificationManagerType {
    var notificationPermissionStatus: NotificationServiceType { get }
    func setBadgeCount(count: Int)
    func handleNotificationPermission(completion: @escaping (_ response: Bool, _ error: Error?) -> Void)
    func setInitialInfo(for application: UIApplication, with launchOptions: [UIApplication.LaunchOptionsKey: Any]?)
    func getNotificationPermissionStatus() -> PermissionStatus
    func update(notificationType: Int)
    func setNotificationPermissionStatus(status: PermissionStatus)
    func setNotificationOpenHandler(block: PENotificationOpenHandler?)
    func setNotificationWillShowInForgroundHandler(block: PENotificationWillShowInForeground?)
    func receivedNotification(with userInfo: [AnyHashable: Any], isOpened: Bool)
    func handleWillPresentNotificationInForeground(with payLoad: [AnyHashable: Any],
                                                   completionHandler: @escaping PENotificationDisplayNotification)
    @available(iOS 10.0, *)
    func processiOS10Open(response: UNNotificationResponse)
    @available(iOS 10.0, *)
    func didReceiveNotificationExtensionRequest(_ request: UNNotificationRequest,
                                                bestContentHandler: UNMutableNotificationContent)
    @available(iOS 10.0, *)
    func serviceExtensionTimeWillExpire(_ request: UNNotificationRequest,
                                        content: UNMutableNotificationContent?) -> UNMutableNotificationContent?
    func receivedRemoteNotification(application: UIApplication,
                                   userInfo: [AnyHashable: Any],
                                   completionHandler: ((UIBackgroundFetchResult) -> Void)?) -> Bool
    func setbackGroundSilentPushHandler(block: PESilentPushBackgroundHandler?)
    func willPresentNotification(center: UNUserNotificationCenter, notification: UNNotification, completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
}

protocol AttributeManagerType {
    func set(attributes: Parameters, completionHandler: ((_ response: Bool, _ error: PEError?) -> Void)?)
    func add(attributes: Parameters, completionHandler: ((_ response: Bool, _ error: PEError?) -> Void)?)
    func getAttribute(completionHandler: @escaping(_ info: [String: Any]?, _ error: PEError?) -> Void)
    func deleteAttribute(values: [String],
                         completionHandler: ((_ response: Bool, _ error: PEError?) -> Void)?)
    func addProfile(for id: String, completionHandler: ((_ response: Bool, _ error: PEError?) -> Void)?)
}

protocol SegmentManagerType {
    func update(segments: [String], with action: SegmentActions,
                completionHandler: ((_ response: Bool, _ error: PEError?) -> Void)?)
    func add(dynamic segments: [[String: Any]],
             completionHandler: ((_ response: Bool, _ error: PEError?) -> Void)?)
    func updateHashArray(for segmentId: Int,
                         completionHandler: ((_ response: Bool, _ error: PEError?) -> Void)?)
}

protocol CampaignManagerType {
    func automatedNotification(status: TriggerStatusType,
                       completionHandler: ((_ response: Bool, _ error: PEError?) -> Void)?)
    func sendTriggerEvent(trigger: TriggerCampaign, completionHandler: ((_ response: Bool,
                                                                         _ error: PEError?) -> Void)?)
    func addAlert(triggerAlert: TriggerAlert, completionHandler: ((_ response: Bool,
                                                                   _ error: PEError?) -> Void)?)
}

protocol GoalManagerType {
    func sendGoal(goal: Goal, completionHandler: ((_ response: Bool,
                                                   _ error: PEError?) -> Void)?)
}

protocol CustomUIManagerType {
    @available(iOS 10.0, *)
    func getCustomUIPayLoad(for request: UNNotificationRequest) -> CustomUIModel
}

protocol SwizzleManagerType {
    func updateSwizzledStatus(with status: Bool)
}

protocol PEManagerType: DeviceManagerType,
                        SubscriberManagerType,
                        AppInfoManagerType,
                        NotificationManagerType,
                        AttributeManagerType,
                        SegmentManagerType,
                        CampaignManagerType,
                        CustomUIManagerType,
                        SwizzleManagerType,
                        GoalManagerType {}

final class PEManager: PEManagerType {
    
    // MARK: - private variables
    private var applicationService: ApplicationServiceType
    private let notificationService: NotificationServiceType
    private let subscriberService: SubscriberServiceType
    private var userDefaultsService: UserDefaultsType
    private let notificationLifeCycleService: NotificationLifeCycleServiceType
    private let notificationExtensionService: NotificationExtensionType
    private let triggerCampaignService: TriggerCampaignManagerType
    private var application: UIApplication?
    private var launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    private var lastNotificationPayload: [AnyHashable: Any]?
    private var lastNonActiveNotificationReceivedId: String?
    private var lastNotificationIdFromAction: String?
    private var unprocessedNotification: [PENotificationOpenResult]?
    private var silentPushNotificationHandler: PESilentPushBackgroundHandler?
    private var silentCompletionTask: PEBackgroundTaskCompletionBlock?
    private var timer: Timer?
    private static var notificationWillShowInForeground: PENotificationWillShowInForeground?
    private static var notificationOpenHandler: PENotificationOpenHandler?
    private let disposeBag = DisposeBag()
    
    var notificationPermissionStatus: NotificationServiceType {
        return notificationService
    }
    
    init(applicationService: ApplicationServiceType,
         notificationService: NotificationServiceType,
         notificationExtensionService: NotificationExtensionType,
         subscriberService: SubscriberServiceType,
         userDefaultService: UserDefaultsType,
         notificationLifeCycleService: NotificationLifeCycleServiceType,
         triggerCamapaiginService: TriggerCampaignManagerType) {
        self.applicationService = applicationService
        self.notificationService = notificationService
        self.subscriberService = subscriberService
        self.userDefaultsService = userDefaultService
        self.notificationLifeCycleService = notificationLifeCycleService
        self.notificationExtensionService = notificationExtensionService
        self.triggerCampaignService = triggerCamapaiginService
        self.applicationService.notifydelegate = self
        self.setupBindings()
        self.addObservers()
    }
    
    // MARK: - private func

    private func addObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(smartResubscriber),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(retrySiteSyncIfFailedFirstTime),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
    }
    
    private func removeObservers() {
        NotificationCenter.default.removeObserver(self,
                                                  name: UIApplication.didEnterBackgroundNotification,
                                                  object: nil)
        NotificationCenter.default.removeObserver(self,
                                                  name: UIApplication.willEnterForegroundNotification,
                                                  object: nil)
    }
        
    /// Does weekly subscriber sync
    /// - Parameters:
    ///     - backgroundHandler: Background operation handler
    ///     - currentData: Current device date
    private func weeklySyncOperation(backgroundHandler: BackgroundTaskExpirationHandler,
                                     currentData: Date) {
        let dispatchGroup = DispatchGroup()
        guard let siteKey = userDefaultsService.siteKey else {
            PELogger.debug(className: String(describing: PEManager.self),
                           message: "site key is not available")
            backgroundHandler.end()
            return
        }
        dispatchGroup.enter()
        
        subscriberService.syncSiteInfo(for: siteKey) { _, _ in
            dispatchGroup.leave()
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.application?.registerForRemoteNotifications()
        }
        
        _ = dispatchGroup.wait(timeout: DispatchTime.now() + NetworkConstants.requestTimeout)
    
        let siteStatus = SiteStatus(rawValue: userDefaultsService.siteStatus)
        if siteStatus != .active {
            backgroundHandler.end()
            return
        }
        
        let shouldDeleteSubscriberOnDisable = shouldDeleteSubscriberNotificationDisable(backgroundHandler: backgroundHandler,
            now: currentData)
        if shouldDeleteSubscriberOnDisable {
            self.updateSubscriberAction(backgroundHandler: backgroundHandler, now: currentData)
        } else {
            PELogger.error(className: String(describing: PEManager.self),
                              message: "Subscriber was not available so it is added so "
                                       + "not needed to update subscriber.")
        }
    }
    
    private func shouldDeleteSubscriberNotificationDisable(backgroundHandler: BackgroundTaskExpirationHandler,
                                                     now: Date) -> Bool {
        var continueFlag = false
        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        
        // Only update subscriber status if:
        // 1. isDeleteSubscriberOnDisable is true AND
        // 2. Notification permission is not granted
        let shouldRemoveSubscriber = userDefaultsService.isDeleteSubscriberOnDisable == true && 
                                   userDefaultsService.notificationPermissionState != .granted
        
        if shouldRemoveSubscriber {
            let status = 1 // Set to 1 (unsubscribed) when conditions are met
            subscriberService.updateSubscriberStatus(status: status) { [weak self] _, error in
                if case .invalidStatusCode(_, let code) = error, code == 404 {
                    self?.userDefaultsService.isManuallyUnsubscribed = false
                    self?.userDefaultsService.isSubscriberDeleted = false
                    self?.subscriberService.retryAddSubscriberProcess(completion: { _ in
                        backgroundHandler.end()
                    })
                    continueFlag = false
                } else {
                    // Successfully unsubscribed due to notification settings - update flags
                    // Clear manual unsubscription flag since this is automatic unsubscription
                    self?.userDefaultsService.isManuallyUnsubscribed = false
                    self?.userDefaultsService.isSubscriberDeleted = true
                    continueFlag = true
                }
                dispatchGroup.leave()
            }
        } else {
            continueFlag = true
            dispatchGroup.leave()
        }
        _ = dispatchGroup.wait(timeout: DispatchTime.now() + NetworkConstants.requestTimeout)
        return continueFlag
    }
    
    private func updateSubscriberAction(backgroundHandler: BackgroundTaskExpirationHandler,
                                        now: Date) {
        subscriberService.updateSubscriber { [weak self] _, error in
            PELogger.debug(className: String(describing: PEManager.self),
                           message: error == nil ? "successfully updated subsciber."
                           : "failed to update subscriber.")
            self?.userDefaultsService.lastSmartSubscribeDate = now
            backgroundHandler.end()
        }
    }
    
    // MARK: - Smart Re-subscribe SEL.
    
    @objc private func smartResubscriber() {
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            let currentDate = Date()
            guard let application = self?.application else {
                return
            }
            if self?.userDefaultsService.istriedFirstTime == false {
                PELogger.debug(className: String(describing: PEManager.self),
                               message: "As first try is not done so no need to do smart-resusbcribe")
                return
            }
            BackgroundTaskExpirationHandler.run(application: application) { [weak self] backgroundHandler in
                let lastResubDate = self?.userDefaultsService.lastSmartSubscribeDate
                if lastResubDate == nil || (lastResubDate != nil && currentDate.days(from: lastResubDate!) >= 7) {
                    self?.weeklySyncOperation(backgroundHandler: backgroundHandler, currentData: currentDate)
                } else {
                    PELogger.debug(className: String(describing: PEManager.self),
                                   message: "Weekly subscriber is"
                                  + " not called because this is day ->"
                                  + " \(lastResubDate != nil ? "\(currentDate.days(from: lastResubDate!))" : "not valid")"
                                  + " after last update.")
                    backgroundHandler.end()
                }
            }
        }
    }
    
    /// Retry site sync if failed the first time
    @objc private func retrySiteSyncIfFailedFirstTime() {
        if userDefaultsService.istriedFirstTime
          && !userDefaultsService.deviceToken.isEmpty
          && userDefaultsService.getObject(for: SyncAPIData.self,
                                          key: UserDefaultConstant.pushEngageSyncApi) == nil {
            guard let siteKey = userDefaultsService.siteKey else {
                return
            }
            subscriberService.syncSiteInfo(for: siteKey) { _, error in
                if error != nil {
                    PELogger.debug(className: String(describing: PEManager.self),
                                   message: error?.localizedDescription ?? "")
                }
            }
        } else {
            PELogger.debug(className: String(describing: PEManager.self),
                           message: "retryForSiteSyncIfFailedforFirstTime not needed")
        }
    }
    
    /// Determine notification subscriber changes
    /// - Parameters:
    ///     - status: Notification permission status
    private func determineNotificationSubscriberChanges(status: PermissionStatus) {
        
        let previousStatus = userDefaultsService.notificationPermissionState
        userDefaultsService.notificationPermissionState = status
        if userDefaultsService.notificationPermissionState == .notYetRequested {
            PELogger.debug(className: String(describing: PEManager.self),
                           message: "Permission not determined so" +
                                    "Notification permission alert will prompt.")
            return
        }
        
        if userDefaultsService.notificationPermissionState == .granted,
            userDefaultsService.isSubscriberDeleted,
            !userDefaultsService.isManuallyUnsubscribed {
            subscriberService.retryAddSubscriberProcess { error in
                if error != nil {
                    PELogger.error(className: String(describing: PEManager.self),
                                   message: "failed to add subscriber")
                }
            }
            return
        }
         
        if previousStatus != userDefaultsService.notificationPermissionState {
            if userDefaultsService.ispermissionAlerted == true {
                subscriberService.updateSettingPermission(status: status)
            } else {
                PELogger.debug(className: String(describing: PEManager.self),
                               message: "Alert hasn't prompted.")
            }
        }
    }
    
    private func setupBindings() {
        notificationService
            .notificationPermissionStatus.subscribe { [weak self] (status) in
            PELogger.info(className: String(describing: PEManager.self), message: status.rawValue)
            self?.determineNotificationSubscriberChanges(status: status)
        }.disposed(by: disposeBag)
    }
    
    func setEnvironment(_ environment: PEEnvironment) {
        userDefaultsService.environment = environment
    }
    
    func setBadgeCount(count: Int) {
        userDefaultsService.badgeCount = count
        if #available(iOS 17, *) {
            UNUserNotificationCenter.current().setBadgeCount(count)
        } else {
            UIApplication.shared.applicationIconBadgeNumber = count
        }
    }
    
    func getDeviceToken() -> String {
        return userDefaultsService.deviceToken
    }
    
    func setDeviceToken(token: String) {
        userDefaultsService.deviceToken = token
    }
    
    func getSubscriberId(completion: @escaping (_ response: String?) -> Void) {
        self.getSubscriptionStatus { isSubscribed, error in
            if error != nil {
                completion(nil)
                return
            }
            if isSubscribed && !self.userDefaultsService.subscriberHash.isEmpty {
                completion(self.userDefaultsService.subscriberHash)
                return
            }
            completion(nil)
        }
    }
    
    func getSubscriberHash() -> String {
        return userDefaultsService.subscriberHash
    }
    
    func getAppId() -> Int? {
        return userDefaultsService.appId
    }
    
    func setAppId(key: String) {
        userDefaultsService.siteKey = key
    }

    func handleNotificationPermission(completion: @escaping (_ response: Bool, _ error: Error?) -> Void) {
        guard let application = application else {
            PELogger.debug(className: String(describing: PEManager.self),
                           message: "application is not available...")
            completion(false, PEError.siteKeyNotAvailable)
            return
        }
        notificationService
        .handleNotificationPermission(for: application) { response, error in
            completion(response, error)
        }
    }
    
    func setInitialInfo(for application: UIApplication,
                       with launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        self.application = application
        self.launchOptions = launchOptions

    }
    
    func onClickRedirect(to launchURL: String?) {
        if let url = launchURL, url.starts(with: NetworkConstants.https) || url.starts(with: NetworkConstants.http) {
            let url = URL(string: url)
            if #available(iOS 10.0, *) {
                Utility.inAppPermissionStatus ? Utility.loadWKWebView(with: url)
                    : Utility.loadWithSafari(url: url)
            } else {
                Utility.loadWKWebView(with: url)
            }
        } else {
            PELogger.debug(className: String(describing: PEManager.self),
                           message: "invalid URL..")
        }
    }
    
    // Result is discardable result.
    /// prerequesite check for the api calls to happen for the developers
    /// - Parameter block: after prevalidation success case block will be called.
    @discardableResult
    private func prerequesiteNetworkCallCheck(block: () -> Void) -> PEError? {
        let siteStatus = SiteStatus(rawValue: userDefaultsService.siteStatus)
        let permissionStatus = userDefaultsService.notificationPermissionState
        let subscriberDeletedStatus = userDefaultsService.isSubscriberDeleted
        if case .active = siteStatus,
           permissionStatus == .granted || permissionStatus == .denied,
           subscriberDeletedStatus == false {
            block()
            return nil
        } else {
            return siteStatus != .active ? .stiteStatusNotActive : .subscriberNotAvailable
        }
    }
    
    func getDeviceHash() -> String {
        return userDefaultsService.subscriberHash
    }
    
    func getNotificationPermissionStatus() -> PermissionStatus {
        return userDefaultsService.notificationPermissionState
    }
    
    func setNotificationPermissionStatus(status: PermissionStatus) {
        userDefaultsService.notificationPermissionState = status
    }
    
    
    @available(iOS 10.0, *)
    func didReceiveNotificationExtensionRequest(_ request: UNNotificationRequest,
                                                bestContentHandler: UNMutableNotificationContent) {
        notificationExtensionService.didReceiveNotificationExtensionRequest(request,
                                                                            bestContentHandler: bestContentHandler)
    }
    
    // MARK: - add Subscriber Attributes
    
    func set(attributes: Parameters, completionHandler: ((_ response: Bool, _ error: PEError?) -> Void)?) {
        let error = prerequesiteNetworkCallCheck {
            subscriberService.setSubscriberAttributes(attributes: attributes, completionHandler: completionHandler)
        }
        if error != nil {
            completionHandler?(false, error)
        }
    }
    
    func add(attributes: Parameters, completionHandler: ((_ response: Bool, _ error: PEError?) -> Void)?) {
        let error = prerequesiteNetworkCallCheck {
            subscriberService.addSubscriberAttributes(attributes: attributes, completionHandler: completionHandler)
        }
        if error != nil {
            completionHandler?(false, error)
        }
    }
    
    // MARK: - get-subscriber-attributes
    func getAttribute(completionHandler: @escaping(_ info: [String: Any]?, _ error: PEError?) -> Void) {
        let error = prerequesiteNetworkCallCheck {
            subscriberService.getAttribute(completionHandler: completionHandler)
        }
        if error != nil {
            completionHandler(nil, error)
        }
    }
    
    // MARK: - add-profile-id
    
    func addProfile(for id: String, completionHandler: ((_ response: Bool, _ error: PEError?) -> Void)?) {
        
        let error = prerequesiteNetworkCallCheck {
            subscriberService.addProfile(id: id, completionHandler: completionHandler)
        }
        
        if error != nil {
            completionHandler?(false, error)
        }
    }
    
    // MARK: - delete Attributes
    func deleteAttribute(values: [String],
                         completionHandler: ((_ response: Bool, _ error: PEError?) -> Void)?) {
        let error = prerequesiteNetworkCallCheck {
            subscriberService.deleteAttribute(with: values, completionHandler: completionHandler)
        }
        
        if error != nil {
            completionHandler?(false, error)
        }
    }
    
    // MARK: - update segments
    func update(segments: [String], with action: SegmentActions,
                completionHandler: ((_ response: Bool, _ error: PEError?) -> Void)?) {
        let error = prerequesiteNetworkCallCheck {
            subscriberService.update(segments: segments,
                                     action: action,
                                     completionHandler: completionHandler)
        }
        if error != nil {
            completionHandler?(false, error)
        }
    }
    
    // MARK: - add dynamic segments
    func add(dynamic segments: [[String: Any]],
             completionHandler: ((_ response: Bool, _ error: PEError?) -> Void)?) {
        let error = prerequesiteNetworkCallCheck {
            subscriberService.update(dynamic: segments,
                                     completionHandler: completionHandler)
        }
        if error != nil {
            completionHandler?(false, error)
        }
    }
    
    // MARK: - update segment hash Array
    func updateHashArray(for segmentId: Int,
                         completionHandler: ((_ response: Bool, _ error: PEError?) -> Void)?) {
        let error = prerequesiteNetworkCallCheck {
            subscriberService.segmentHashArray(for: segmentId, completionHandler: completionHandler)
        }
        if error != nil {
            completionHandler?(false, error)
        }
    }
    
    // MARK: - get subscriber details
   func getSubscriberDetails(for fields: [String]?,
                             completionHandler: ((_ response: SubscriberDetailsData?, _ error: PEError?) -> Void)?) {
        let error = prerequesiteNetworkCallCheck {
            subscriberService.getSubscriber(for: fields, completionHandler: completionHandler)
        }
        if error != nil {
            completionHandler?(nil, error)
        }
    }
    
    // MARK: - get subscription status
    func getSubscriptionStatus(completionHandler: ((_ isSubscribed: Bool, _ error: PEError?) -> Void)?) {
        let siteStatus = SiteStatus(rawValue: userDefaultsService.siteStatus)
        let permissionStatus = userDefaultsService.notificationPermissionState
        let isManuallyUnsubscribed = userDefaultsService.isManuallyUnsubscribed
        let isSubscriberDeleted = userDefaultsService.isSubscriberDeleted
        let subscriberHash = userDefaultsService.subscriberHash
        
        if siteStatus != .active {
            PELogger.debug(className: String(describing: PEManager.self),
                           message: "getSubscriptionStatus - site not active")
            completionHandler?(false, .stiteStatusNotActive)
            return
        }
        
        if isManuallyUnsubscribed {
            PELogger.debug(className: String(describing: PEManager.self),
                           message: "getSubscriptionStatus - manually unsubscribed")
            completionHandler?(false, nil)
            return
        }
        
        if subscriberHash.isEmpty {
            PELogger.debug(className: String(describing: PEManager.self),
                           message: "getSubscriptionStatus - no subscriber hash, not subscribed yet")
            completionHandler?(false, nil)
            return
        }
        
        if permissionStatus == .notYetRequested {
            PELogger.debug(className: String(describing: PEManager.self),
                           message: "getSubscriptionStatus - permission not requested, not subscribed")
            completionHandler?(false, .permissionNotDetermined)
            return
        }
        
        if !isSubscriberDeleted && permissionStatus == .granted {
            PELogger.debug(className: String(describing: PEManager.self),
                           message: "getSubscriptionStatus - local data indicates subscribed, returning true")
            completionHandler?(true, nil)
            return
        }
        
        subscriberService.getSubscriber(for: ["has_unsubscribed", "notification_disabled"]) { response, error in
            if let error = error {
                PELogger.error(className: String(describing: PEManager.self),
                               message: "getSubscriptionStatus - API call failed: \(error.localizedDescription)")
                completionHandler?(false, error)
                return
            }
            
            guard let subscriberData = response else {
                completionHandler?(false, .parsingError)
                return
            }
            
            // - User is subscribed only when both hasUnsubscribed = 0 AND notification_disabled = 0
            let isSubscribed = ((subscriberData.hasUnsubscribed ?? 0) == 0 ) && ((subscriberData.notificationDisabled ?? 0) == 0)
            
            PELogger.debug(className: String(describing: PEManager.self),
                           message: "getSubscriptionStatus - hasUnsubscribed: \(subscriberData.hasUnsubscribed ?? -1), notificationDisabled: \(subscriberData.notificationDisabled ?? -1), result: isSubscribed: \(isSubscribed)")
            completionHandler?(isSubscribed, nil)
        }
    }
    
    // MARK: - get subscription notification status
    func getSubscriptionNotificationStatus(completionHandler: ((_ canReceiveNotifications: Bool, _ error: PEError?) -> Void)?) {
        
        // First check subscription status
        getSubscriptionStatus { [weak self] isSubscribed, error in
            if let error = error {
                PELogger.error(className: String(describing: PEManager.self),
                               message: "getSubscriptionNotificationStatus - subscription check failed: \(error.localizedDescription)")
                completionHandler?(false, error)
                return
            }
            
            // If not subscribed, user cannot receive notifications
            guard isSubscribed else {
                PELogger.debug(className: String(describing: PEManager.self),
                               message: "getSubscriptionNotificationStatus - user not subscribed, cannot receive notifications")
                completionHandler?(false, nil)
                return
            }
            
            // Check notification permission status
            let permissionStatus = self?.getNotificationPermissionStatus() ?? .notYetRequested
            let hasNotificationPermission = permissionStatus == .granted
            
            // User can receive notifications only if subscribed AND has permission
            let canReceiveNotifications = isSubscribed && hasNotificationPermission
            
            PELogger.debug(className: String(describing: PEManager.self),
                           message: "getSubscriptionNotificationStatus - isSubscribed: \(isSubscribed), permissionStatus: \(permissionStatus.rawValue), canReceiveNotifications: \(canReceiveNotifications)")
            
            completionHandler?(canReceiveNotifications, nil)
        }
    }
    
    func checkSubscriber(completionHandler: ((_ response: CheckSubscriberData?, _ error: PEError?) -> Void)?) {
        let error = prerequesiteNetworkCallCheck {
            subscriberService.checkSubscriber(completionHandler: completionHandler)
        }
        if error != nil {
            completionHandler?(nil, error)
        }
    }
    
    func sendGoal(goal: Goal, completionHandler: ((_ response: Bool, _ error: PEError?) -> Void)?) {
        let error = prerequesiteNetworkCallCheck {
            subscriberService.sendGoal(goal: goal, completionHandler: completionHandler)
        }
        
        if error != nil {
            completionHandler?(false, error)
        }
    }
    
    // MARK: - Trigger Campaign
    func automatedNotification(status: TriggerStatusType,
                               completionHandler: ((_ response: Bool, _ error: PEError?) -> Void)?) {
        let error = prerequesiteNetworkCallCheck {
            subscriberService.automatedNotification(status: status,
                                                    completionHandler: completionHandler)
        }
        if error != nil {
            completionHandler?(false, error)
        }
    }
    
    func sendTriggerEvent(trigger: TriggerCampaign,
                          completionHandler: ((_ response: Bool, _ error: PEError?) -> Void)?) {
        let error = prerequesiteNetworkCallCheck {
            triggerCampaignService.sendTriggerEvent(trigger: trigger, completion: completionHandler)
        }
        
        if error != nil {
            completionHandler?(false, error)
        }
    }
    
    func addAlert(triggerAlert: TriggerAlert,
                  completionHandler: ((_ response: Bool,
                                       _ error: PEError?) -> Void)?) {
        let error = prerequesiteNetworkCallCheck {
            triggerCampaignService.addAlert(triggerAlert: triggerAlert, completionHandler: completionHandler)
        }
        
        if error != nil {
            completionHandler?(false, error)
        }
    }
    
    // MARK: - Subscriber Status
    func unsubscribe(completionHandler: ((_ response: Bool, _ error: PEError?) -> Void)?) {
        let error = prerequesiteNetworkCallCheck {
            subscriberService.updateSubscriberStatus(status: 1) { [weak self] response, error in
                if response {
                    // Mark as manually unsubscribed to prevent automatic re-subscription
                    self?.userDefaultsService.isManuallyUnsubscribed = true
                    self?.userDefaultsService.isSubscriberDeleted = true
                }
                completionHandler?(response, error)
            }
        }
        if error != nil {
            completionHandler?(false, error)
        }
    }
    
    func subscribe(completionHandler: ((_ response: Bool, _ error: PEError?) -> Void)?) {
        let permissionStatus = userDefaultsService.notificationPermissionState
        let subscriberHash = userDefaultsService.subscriberHash
        
        // If notification permission is granted AND we have subscriber data, call update
        if permissionStatus == .granted && !subscriberHash.isEmpty {
            PELogger.debug(className: String(describing: PEManager.self),
                           message: "Permission granted and subscriber data exists - calling updateSubscriberStatus(status: 0)")
            
            subscriberService.updateSubscriberStatus(status: 0) { [weak self] response, error in
                if case .invalidStatusCode(_, let code) = error, code == 404 {
                    self?.userDefaultsService.isManuallyUnsubscribed = false
                    self?.subscriberService.retryAddSubscriberProcess(completion: { error in
                        if let error = error {
                            PELogger.error(className: String(describing: PEManager.self),
                                           message: "Retrying to add subscriber failed: \(error)")
                            completionHandler?(false, error)
                            return
                        }
                        completionHandler?(response, error)
                    })
                } else if response {
                    // Clear flags after successful subscription
                    self?.userDefaultsService.isManuallyUnsubscribed = false
                    self?.userDefaultsService.isSubscriberDeleted = false
                    PELogger.debug(className: String(describing: PEManager.self),
                                   message: "Manual subscription successful via update")
                    completionHandler?(response, error)
                }
            }
        } else {
            guard permissionStatus != .denied else {
                completionHandler?(false, .permissionNotGranted)
                return
            }
            guard permissionStatus == .notYetRequested else {
                completionHandler?(false, .permissionNotDetermined)
                return
            }
            // Go through notification permission request flow
            PELogger.debug(className: String(describing: PEManager.self),
                           message: "Permission not granted or no subscriber data - requesting notification permission. Permission: \(permissionStatus.rawValue), hasSubscriberHash: \(!subscriberHash.isEmpty)")
            
            handleNotificationPermission { [weak self] permissionGranted, error in
                if let error = error {
                    completionHandler?(false, error as? PEError ?? .permissionNotDetermined)
                    return
                }
                
                completionHandler?(permissionGranted, .permissionNotGranted)
            }
        }
    }
    
    // MARK: - best attempt handled
    @available(iOS 10.0, *)
    func serviceExtensionTimeWillExpire(_ request: UNNotificationRequest,
                                        content: UNMutableNotificationContent?) -> UNMutableNotificationContent? {
        return notificationExtensionService.serviceExtensionTimeWillExpire(request, content: content)
    }
    
    // MARK: - Add subscriber
    
    @available(iOS 10.0, *)
    func getCustomUIPayLoad(for request: UNNotificationRequest) -> CustomUIModel {
        notificationExtensionService.getContentExtensionInfo(for: request)
    }
    
    deinit {
        disposeBag.disposedValue()
        Self.notificationOpenHandler = nil
        Self.notificationWillShowInForeground = nil
        self.removeObservers()
    }
    
}
// MARK: - Swizzling and manually setup methods.

extension PEManager {
    
    func registerDeviceToServer(with deviceToken: Data) {
        applicationService.registerDeviceToServer(with: deviceToken)
    }
    
    func receivedRemoteNotification(application: UIApplication,
                                   userInfo: [AnyHashable: Any],
                                   completionHandler: ((UIBackgroundFetchResult) -> Void)?) -> Bool {
        applicationService.receivedRemoteNotification(application: application,
                                                     userInfo: userInfo,
                                                     completionHandler: completionHandler)
    }
    
    func willPresentNotification(center: UNUserNotificationCenter, notification: UNNotification, completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        applicationService.willPresentNotification(center: center, notification: notification, completionHandler: completionHandler)
    }
    
    public func setNotificationOpenHandler(block: PENotificationOpenHandler?) {
        Self.notificationOpenHandler = block
        self.handleNotificationForUnprocessedEvent()
    }
    
    public func setNotificationWillShowInForgroundHandler(block: PENotificationWillShowInForeground?) {
        Self.notificationWillShowInForeground = block
    }
    
    public func receivedNotification(with userInfo: [AnyHashable: Any], isOpened: Bool) {
        guard Utility.isPEPayload(userInfo: userInfo) else {
            PELogger.debug(className: String(describing: PEManager.self),
                           message: "Notification is not pushengage payload")
            return
        }
        PELogger.debug(className: String(describing: PEManager.self), message: "\(isOpened)")
        self.lastNotificationPayload = userInfo
        if isOpened {
            let newNotifyId = Utility.checkForDuplicateProcess(infoDict: userInfo,
                                                            lastRecivedNotifyId: lastNonActiveNotificationReceivedId ?? "")
            if newNotifyId == PayloadConstants.duplicate {
                PELogger.debug(className: String(describing: PEManager.self), message: "duplicate notifications.")
                return
            }
            lastNonActiveNotificationReceivedId = newNotifyId
            var type: ActionType = .opened
            if userInfo[userInfo: PayloadConstants
                            .custom]?[userInfo: PayloadConstants
                                        .additionalData]?[string: PayloadConstants.actionSelected] != nil {
                type = .taken
            }
            handleNotificationOpened(userInfo, with: type)
        }
    }
    
    public func handleWillPresentNotificationInForeground(with payLoad: [AnyHashable: Any],
                                                         completionHandler: @escaping PENotificationDisplayNotification) {
        if !Utility.isPEPayload(userInfo: payLoad) ||
            application?.applicationState == .background {
            return
        }
        
        let notification = PENotification(userInfo: payLoad)
        if notification.isSponsered == 1 {
            self.handleWillShowInForegoundHandler(for: notification) { _ in
                completionHandler(notification)
            }
        } else {
            self.handleWillShowInForegoundHandler(for: notification, with: completionHandler)
        }
    }
    
    private func handleWillShowInForegoundHandler(for notification: PENotification,
                                                 with completionHandler: @escaping PENotificationDisplayNotification) {
        
        notification.setCompletion(for: completionHandler)
        if Self.notificationWillShowInForeground != nil {
            notification.timeOutTimerSetup()
            notification.startTimeoutTimer()
            let block = notification.getCompletionBlock()
            Self.notificationWillShowInForeground?(notification, block)
        } else {
            completionHandler(notification)
        }
    }
    
    private func getUnprocessedOpenedNotification() -> [PENotificationOpenResult] {
        return unprocessedNotification ?? []
    }
    
    private func handleNotificationOpened(_ customDict: [AnyHashable: Any], with actionType: ActionType) {
        let custom = customDict[userInfo: PayloadConstants.custom] as? [String: Any]
        let notifId = custom?[string: PayloadConstants.tag] ?? ""
        let appState = application?.applicationState == .active

        PELogger.debug(className: String(describing: PEManager.self),
                       message: "notification opened for id \(notifId) and appstate is \(appState)")
        
        self.lastNotificationPayload = customDict

        var actionId: String?
        if actionType == .taken {
             actionId = (custom?[userInfo: PayloadConstants.additionalData] as? [String: Any])?[string: PayloadConstants.actionSelected]
        }

        if actionId == .defaultActionIdentifier {
            PELogger.debug(className: String(describing: PEManager.self),
                           message: "__DEFAULT_ACTION__")
            
            let deepLink = custom?[string: PayloadConstants.deeplinking]
            let launchURL = custom?[string: PayloadConstants.launchUrlKey]
            
            actionId = handleDeepLinkOrLaunchURL(deepLink: deepLink, launchURL: launchURL)
            
        }
        
        let notification = PENotification(userInfo: lastNotificationPayload ?? [:])
        
        if Utility.autoHandleDeeplinkURL, (notification.isSponsered == 0), let url = actionId, url.starts(with: NetworkConstants.https) || url.starts(with: NetworkConstants.http) {
            self.onClickRedirect(to: url)
            actionId = nil
        }
        
        self.handleNotificationAction(for: actionType, actionId: actionId)
    }
    
    private func handleDeepLinkOrLaunchURL(deepLink: String?, launchURL: String?) -> String? {
        let urlToHandle = deepLink ?? launchURL
        let notification = PENotification(userInfo: lastNotificationPayload ?? [:])
        
        if Utility.autoHandleDeeplinkURL, (notification.isSponsered == 0), let url = urlToHandle, url.starts(with: NetworkConstants.https) || url.starts(with: NetworkConstants.http) {
            self.onClickRedirect(to: url)
            return nil
        } else {
            return urlToHandle
        }
    }
        
     private func handleNotificationAction(for actionType: ActionType, actionId: String?) {
        var clickedButton: String?
        let notification = PENotification(userInfo: lastNotificationPayload ?? [:])
        if let buttons = notification.actionButtons,
           let id = actionId,
           notification.isSponsered == 0 {
            for (index, button) in buttons.enumerated()
                where button.id == id {
                clickedButton = "action\(index + 1)"
            }
        }
        notificationLifeCycleService.withRetrynotificationLifecycleUpdate(with: .clicked,
                                                                 deviceHash: userDefaultsService.subscriberHash,
                                                                 notificationId: notification.tag,
                                                                 actionid: clickedButton,
                                                                 completionHandler: nil)
        if notification.isSponsered == 1 {
            self.onClickRedirect(to: notification.launchURL)
            PELogger.debug(className: String(describing: PEManager.self),
                           message: "Sponsered Notification.")
            return
        }
        
        let actionCreated = PEnotificationAction(actionID: actionId, actionType: actionType)
        let notificationResult = PENotificationOpenResult(notification: notification,
                                                          notficationAction: actionCreated)
        if notification.tag == lastNotificationIdFromAction {
            return
        }
        lastNotificationIdFromAction = notification.tag
        if Self.notificationOpenHandler == nil {
            self.addUnprocessedNotification(result: notificationResult)
            return
        }
        Self.notificationOpenHandler?(notificationResult)
    }
    
    private func addUnprocessedNotification(result: PENotificationOpenResult) {
        if unprocessedNotification == nil {
            unprocessedNotification = []
        }
        unprocessedNotification?.append(result)
    }
    
    private func handleNotificationForUnprocessedEvent() {
        if Self.notificationOpenHandler == nil {
            return
        }
        for value in unprocessedNotification ?? [] {
            Self.notificationOpenHandler?(value)
        }
        unprocessedNotification = []
    }
    
    @available(iOS 10.0, *)
    func processiOS10Open(response: UNNotificationResponse) {
        if self.getAppId() == nil {
            return
        }
        
        if Utility.isDismissEvent(response: response) {
            PELogger.debug(className: String(describing: PushEngageUNUserNotificationCenter.self),
                           message: "Notification Dismissed by the subscriber.")
            return
        }
        
        var parseuserInfo =  response.notification.request.content.userInfo
        if  parseuserInfo[userInfo: PayloadConstants.custom]?[userInfo: PayloadConstants.additionalData] != nil {
            parseuserInfo[userInfo: PayloadConstants.custom]?[userInfo: PayloadConstants.additionalData]?
                .updateValue(response.actionIdentifier, forKey: PayloadConstants.actionSelected)
        } else {
            let identifier = [PayloadConstants.actionSelected: response.actionIdentifier]
            parseuserInfo[userInfo: PayloadConstants.custom]?
            .updateValue(identifier, forKey: PayloadConstants.additionalData)
        }
       self.receivedNotification(with: parseuserInfo, isOpened: true)
    }
}

// MARK: - LastNotificationSetDelagate
extension PEManager: LastNotificationSetDelegate {

    func silentRemoteNotificationRecivedNotification(with userInfo: [AnyHashable: Any], isOpened: Bool) {
        self.receivedNotification(with: userInfo, isOpened: true)
    }
    
    func setLast(notification infoDict: [AnyHashable: Any],
                 completionHandler: ((UIBackgroundFetchResult) -> Void)?) {
        self.lastNotificationPayload = infoDict
        let notification = PENotification(userInfo: infoDict)
        if notification.contentAvailable == 1
            && application?.applicationState == .background
            && !Utility.isNotifiyIsDisplayable(userInfo: infoDict) {
            if let block = completionHandler {
                setSilentNotificationTaskBlock(block)
                if silentPushNotificationHandler != nil {
                     timer = Timer.init(timeInterval: 29.0, target: self,
                                                   selector: #selector(completeTaskBacgroundSilentTask),
                                                   userInfo: nil, repeats: false)
                    startTimerForSilentPush()
                    let block = getSilentNotificationTaskBlock()
                    silentPushNotificationHandler?(notification, block)
                    silentCompletionTask = { result in
                        completionHandler?(result)
                    }
                } else {
                    completionHandler?(.noData)
                }
            }
        } else {
            completionHandler?(.noData)
        }
    }
}

extension PEManager {
    
    private func startTimerForSilentPush() {
        
        guard let unWrappedTimer = timer else {
            PELogger.debug(className: String(describing: PEManager.self),
                           message: "Timer for silent push is nil")
            return
        }
        RunLoop.current.add(unWrappedTimer, forMode: .common)
    }
    
    @objc private func completeTaskBacgroundSilentTask() {
        if silentCompletionTask != nil {
            silentCompletionTask?(.noData)
            silentCompletionTask = nil
            PELogger.debug(className: String(describing: PEManager.self),
                           message: "As developer didn't set the completion(UIBackgroundFetchResult) auto release has done.")
        }
       resetTimer()
    }
    
    private func setSilentNotificationTaskBlock(_ completion: @escaping PEBackgroundTaskCompletionBlock) {
        self.silentCompletionTask = completion
    }
    
    private func getSilentNotificationTaskBlock() -> PEBackgroundTaskCompletionBlock? {
        let block = { [weak self] (result: UIBackgroundFetchResult) -> Void in
            self?.silentCompletionTask?(result)
            PELogger.debug(className: String(describing: PEManager.self),
                           message: "Developer provided the completion()")
            self?.resetTimer()
        }
        return block
    }
    
    private func resetTimer() {
        self.timer?.invalidate()
        self.timer = nil
    }
    
    func setbackGroundSilentPushHandler(block: PESilentPushBackgroundHandler?) {
        self.silentPushNotificationHandler = block
    }
}

// MARK: - iOS 9 version work around.

extension PEManager {
    func update(notificationType: Int) {
        
        PELogger.debug(className: String(describing: PEManager.self),
                       message: "For iOS version less then 9 is asked")
        self.notificationService.registerToApns(for: application)
        self.notificationService.onNotificationPromptResponse(notification: notificationType)
    }
    
    func updateSwizzledStatus(with status: Bool) {
        userDefaultsService.isSwizzled = status
    }
}
