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
    func setEnvironment(_ environment: Environment)
}

protocol SubscriberManagerType {
    func getSubscriberId() -> String
    func getSubscriberHash() -> String
    func checkSubscriber(completionHandler: ((_ response: CheckSubscriberData?, _ error: PEError?) -> Void)?)
    func getSubscriberDetails(for fields: [String]?,
                              completionHandler: ((_ response: SubscriberDetailsData?, _ error: PEError?) -> Void)?)
}

protocol AppInfoManagerType {
    func getAppId() -> Int?
    func setAppId(key: String)
    func onClickRedirect(to launchURL: String?)
}

protocol NotificationManagerType {
    var notificationPermissionStatus: NotificationServiceType { get }
    func setBadgeCount(count: Int)
    func handleNotificationPermission()
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
        let deleteOnDisablePrev = userDefaultsService.isDeleteSubscriberOnDisable
        subscriberService.syncSiteInfo(for: siteKey) { _, _ in
            dispatchGroup.leave()
        }
        _ = dispatchGroup.wait(timeout: DispatchTime.now() + NetworkConstants.requestTimeout)
    
        let siteStatus = SiteStatus(rawValue: userDefaultsService.siteStatus)
        if siteStatus != .active {
            backgroundHandler.end()
            return
        }
        
        let shouldDeleteSubscriberOnDisable = shouldDeleteSubscriberOnDisableDiffer(backgroundHandler: backgroundHandler,
                                                       deleteOnDisablePrev,
                                                       now: currentData)
        if shouldDeleteSubscriberOnDisable {
            self.updateSubscriberAction(backgroundHandler: backgroundHandler, now: currentData)
        } else {
            PELogger.error(className: String(describing: PEManager.self),
                              message: "Subscriber was not available so it is added so "
                                       + "not needed to update subscriber.")
        }
    }
    
    private func shouldDeleteSubscriberOnDisableDiffer(backgroundHandler: BackgroundTaskExpirationHandler,
                                                   _ deleteOnDisablePrev: Bool?,
                                                     now: Date) -> Bool {
        var continueFlag = false
        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        if deleteOnDisablePrev != userDefaultsService.isDeleteSubscriberOnDisable {
            let status = userDefaultsService.notificationPermissionState == .granted ? 0 : 1
            subscriberService.updateSubscriberStatus(status: status) { [weak self] _, error in
                if case .invalidStatusCode(_, let code) = error, code == 404 {
                    self?.subscriberService.retryAddSubscriberProcess(completion: { _ in
                        backgroundHandler.end()
                    })
                    continueFlag = false
                } else {
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
                                   message: "Weekly subsciber is"
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
            userDefaultsService.isSubscriberDeleted {
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
    
    func setEnvironment(_ environment: Environment) {
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
    
    func getSubscriberId() -> String {
        userDefaultsService.subscriberHash
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

    func handleNotificationPermission() {
        guard let application = application else {
            PELogger.debug(className: String(describing: PEManager.self),
                           message: "application is not available...")
            return
        }
        notificationService
        .handleNotificationPermission(for: application)
    }
    
    func setInitialInfo(for application: UIApplication,
                       with launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        self.application = application
        self.launchOptions = launchOptions

    }
    
    func onClickRedirect(to launchURL: String?) {
        if let url = launchURL, url.contains(NetworkConstants.https) || url.contains(NetworkConstants.http) {
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
        prerequesiteNetworkCallCheck {
            subscriberService.getSubscriber(for: fields, completionHandler: completionHandler)
        }
    }
    
    // This API is not exposed to the Host Application.
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
        let notifId = customDict[userInfo: PayloadConstants.custom]?[string: PayloadConstants.tag] ?? ""
        let appState = application?.applicationState == .active
        PELogger.debug(className: String(describing: PEManager.self),
                       message: "notification opened for id \(notifId) and appstate is \(appState)")
        let launchURL = customDict[userInfo: PayloadConstants.custom]?[string: PayloadConstants.launchUrlKey]
        var actionId: String?
        if actionType == .taken {
             actionId = customDict[userInfo: PayloadConstants
                        .custom]?[userInfo: PayloadConstants
                        .additionalData]?[string: PayloadConstants
                        .actionSelected]
        }
        
        self.lastNotificationPayload = customDict
        if actionId == .defaultActionIdentifer {
            PELogger.debug(className: String(describing: PEManager.self),
                           message: "__DEFAULT_ACTION__")
            if let deepLink = customDict[userInfo: PayloadConstants.custom]?[string: PayloadConstants.deeplinking] {
                if deepLink.contains(NetworkConstants.https) || deepLink.contains(NetworkConstants.http) {
                    self.onClickRedirect(to: deepLink)
                    actionId = nil
                } else {
                    actionId = deepLink
                }
            } else {
                self.onClickRedirect(to: launchURL)
                actionId = nil
            }
        }
        
        if actionId?.contains(NetworkConstants.https) == true
           || actionId?.contains(NetworkConstants.http) == true {
            self.onClickRedirect(to: actionId)
            actionId = nil
        }
        self.handleNotificationAction(for: actionType, actionId: actionId)
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
        if actionId == userDefaultsService.sponseredIdKey ,
           notification.isSponsered == 1 {
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
