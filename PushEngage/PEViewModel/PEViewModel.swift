//
//  PEViewModel.swift
//  PushEngage
//
//  Created by Abhishek on 02/04/21.
//

import Foundation
import UserNotifications
import UIKit

class PEViewModel {
    
    // MARK: - private variables
    private var applicationService: ApplicationProtocol
    private var notificationService: NotificationProtocol
    private var subscriberService: SubscriberService
    private var userDefaultService: UserDefaultProtocol
    private var notificationLifeCycleService: NotificationLifeCycleService
    private var notificationExtensionService: NotificationExtensionProtocol
    private var locationService: LocationInfoProtocol
    private var triggerCamapaiginService: TriggerCampaignProtocol
    private var application: UIApplication?
    private var launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    var notificationPermissionStatus: NotificationProtocol {
        return notificationService
    }
    private let disposeBag = DisposeBag()
    private static var notificationWillShowInForground: PENotificationWillShowInForground?
    private static var notificationOpenHandler: PEnotificationOpenHandler?
    private var lastNotifyPayload: [AnyHashable: Any]?
    private var lastNonActiveNotifyRecivedId: String?
    private var lastNotifyIdFromAction: String?
    private var unprocessedNotification: [PENotificationOpenResult]?
    private var silentPushNotificationHandler: PESilentPushBackgroundHandler?
    private var silentCompletionTask: PEBackgroundTaskCompletionBlock?
    private var timer: Timer?
    
    init(applicationService: ApplicationProtocol,
         notificationService: NotificationProtocol,
         notificationExtensionService: NotificationExtensionProtocol,
         subscriberService: SubscriberService,
         userDefaultService: UserDefaultProtocol,
         notificationLifeCycleService: NotificationLifeCycleService,
         locationService: LocationInfoProtocol,
         triggerCamapaiginService: TriggerCampaignProtocol) {
        self.applicationService = applicationService
        self.notificationService = notificationService
        self.subscriberService = subscriberService
        self.userDefaultService = userDefaultService
        self.notificationLifeCycleService = notificationLifeCycleService
        self.notificationExtensionService = notificationExtensionService
        self.locationService = locationService
        self.triggerCamapaiginService = triggerCamapaiginService
        self.applicationService.notifydelegate = self
        setupBinding()
        NotificationCenter.default.addObserver(self, selector: #selector(smartResubscriber),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(retryForSiteSyncIfFailedforFirstTime),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
    }
    
    deinit {
        disposeBag.disposedValue()
        Self.notificationOpenHandler = nil
        Self.notificationWillShowInForground = nil
        NotificationCenter.default.removeObserver(self,
                                                  name: UIApplication.didEnterBackgroundNotification,
                                                  object: nil)
        NotificationCenter.default.removeObserver(self,
                                                  name: UIApplication.willEnterForegroundNotification,
                                                  object: nil)
    }
    
    // MARK: - private func
    
    /* Weekly Sync operation will try to call after every week if diff btw curr sync date
     and last sync date is greater than 7 then it will call the weekly sync api */
    
    private func weeklySyncOperation(backgroundHandler: BackgroundTaskExpirationHandler,
                                     now: Date) {
        let dispatchGroup = DispatchGroup()
        guard let siteKey = userDefaultService.siteKey else {
            PELogger.debug(className: String(describing: PEViewModel.self),
                           message: "site key is not available")
            backgroundHandler.end()
            return
        }
        dispatchGroup.enter()
        let deleteOnDisablePrev = userDefaultService.isDeleteSubscriberOnDisable
        subscriberService.syncSiteInfo(for: siteKey) { _, _ in
            dispatchGroup.leave()
        }
        _ = dispatchGroup.wait(timeout: DispatchTime.now() + NetworkConstants.requestTimeout)
    
        let siteStatus = SiteStatus(rawValue: userDefaultService.siteStatus)
        if siteStatus != .active {
            backgroundHandler.end()
            return
        }
        
        let result = isDeleteSubscriberOnDisableDiffer(backgroundHandler: backgroundHandler,
                                                       deleteOnDisablePrev,
                                                       now: now)
        result ? updateSubscriberaction(backgroundHandler: backgroundHandler, now: now)
               : PELogger.error(className: String(describing: PEViewModel.self),
                                 message: "Subscriber was not available so it is added so "
                                          + "not needed to update subscriber.")
    }
    
    private func isDeleteSubscriberOnDisableDiffer(backgroundHandler: BackgroundTaskExpirationHandler,
                                                   _ deleteOnDisablePrev: Bool?,
                                                   now: Date) -> Bool {
        var continueFlag = false
        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        if deleteOnDisablePrev != userDefaultService.isDeleteSubscriberOnDisable {
            let status = userDefaultService.notificationPermissionState == .granted ? 0 : 1
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
    
    private func updateSubscriberaction(backgroundHandler: BackgroundTaskExpirationHandler,
                                        now: Date) {
        subscriberService.updateSubsciber { [weak self] _, error in
            PELogger.debug(className: String(describing: PEViewModel.self),
                           message: error == nil ? "successfully updated subsciber."
                           : "failed to update subscriber.")
            self?.userDefaultService.lastSmartSubscribeDate = now
            backgroundHandler.end()
        }
    }
    
    // MARK: - Smart Re-subscribe SEL.
    
    @objc private func smartResubscriber() {
        
        DispatchQueue.global(qos: .background).async { [weak self] in
            let now = Date()
            guard let application = self?.application else {
                return
            }
            if self?.userDefaultService.istriedFirstTime == false {
                PELogger.debug(className: String(describing: PEViewModel.self),
                               message: "As first try is not done so no need to do smart-resusbcribe")
                return
            }
            BackgroundTaskExpirationHandler.run(application: application) { [weak self] backgroundHandler in
                let lastResubDate = self?.userDefaultService.lastSmartSubscribeDate
                if lastResubDate == nil || (lastResubDate != nil  &&  now.days(from: lastResubDate!) >= 7) {
                    self?.weeklySyncOperation(backgroundHandler: backgroundHandler, now: now)
                } else {
                    PELogger.debug(className: String(describing: PEViewModel.self),
                                   message: "Weekly subsciber is"
                                  + " not called because this is day ->"
                                  + " \(lastResubDate != nil ? "\(now.days(from: lastResubDate!))" : "not valid")"
                                  + " after last update.")
                    backgroundHandler.end()
                }
            }
        }
    }
    
    // if site sync failed for first time
    
    @objc private func retryForSiteSyncIfFailedforFirstTime() {
        if userDefaultService.istriedFirstTime
          && !userDefaultService.deviceToken.isEmpty
          && userDefaultService.getObject(for: SyncAPIData.self,
                                          key: UserDefaultConstant.pushEngageSyncApi) == nil {
            guard let siteKey = userDefaultService.siteKey else {
                return
            }
            subscriberService.syncSiteInfo(for: siteKey) { _, error in
                if error != nil {
                    PELogger.debug(className: String(describing: PEViewModel.self),
                                   message: error?.localizedDescription ?? "")
                }
            }
        } else {
            PELogger.debug(className: String(describing: PEViewModel.self),
                           message: "retryForSiteSyncIfFailedforFirstTime not needed")
        }
    }
    
    private func notificationSettingsOperation(status: PermissonStatus) {
        
        let previousStatus = userDefaultService.notificationPermissionState
        userDefaultService.notificationPermissionState = status
        if  userDefaultService.notificationPermissionState == .notYetRequested {
            PELogger.debug(className: String(describing: PEViewModel.self),
                           message: "Permission not determined so" +
                                    "Notification permission alert will prompt.")
            return
        }
        
        if  userDefaultService.notificationPermissionState == .granted,
            userDefaultService.isSubscriberDeleted {
            subscriberService.retryAddSubscriberProcess { error in
                if error != nil {
                    PELogger.error(className: String(describing: PEViewModel.self),
                                   message: "failed to add subscriber")
                }
            }
            return
        }
         
        if previousStatus != userDefaultService.notificationPermissionState {
            if userDefaultService.ispermissionAlerted == true {
                subscriberService.updateSettingPermission(status: status)
            } else {
                PELogger.debug(className: String(describing: PEViewModel.self),
                               message: "Alert hasn't prompted.")
            }
        }
    }
    
    private func setupBinding() {
        notificationService
            .notificationPermissionStatus.subscribe { [weak self] (status) in
            PELogger.info(className: String(describing: PEViewModel.self), message: status.rawValue)
            self?.notificationSettingsOperation(status: status)
        }.disposed(by: disposeBag)
        // Observer for location update.
        locationService.locationInfoObserver.subscribe { [weak self] (geoInfo) in
            self?.userDefaultService.save(object: geoInfo,
                                          for: UserDefaultConstant.locationCoordinates)
        }.disposed(by: disposeBag)
        
    }
    
    func getDeviceToken() -> String {
        return userDefaultService.deviceToken
    }
    
    func setDeviceToken(token: String) {
        userDefaultService.deviceToken = token
    }
    
    func getSubsciberHash() -> String {
        return userDefaultService.subscriberHash
    }
    
    func getAppId() -> Int? {
        return userDefaultService.appId
    }
    
    func setAppId(key: String) {
        userDefaultService.siteKey = key
    }

    func startNotificationServices() {
        guard let application = application else {
            PELogger.debug(className: String(describing: PEViewModel.self),
                           message: "application is not available...")
            return
        }
        notificationService
        .startRemoteNotificationService(for: application)
    }
    
    func setIntialInfo(for application: UIApplication,
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
            PELogger.debug(className: String(describing: PEViewModel.self),
                           message: "invalid URL..")
        }
    }
    
    // Result is discardable result.
    /// prerequesite check for the api calls to happen for the developers
    /// - Parameter block: after prevalidation success case block will be called.
    @discardableResult
    func prerequesiteNetworkCallCheck(block : () -> Void) -> PEError? {
        let siteStatus = SiteStatus(rawValue: userDefaultService.siteStatus)
        let permissionStatus = userDefaultService.notificationPermissionState
        let subscriberDeletedStatus = userDefaultService.isSubscriberDeleted
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
        return userDefaultService.subscriberHash
    }
    
    func getNotificationPermissionStatus() -> PermissonStatus {
        return userDefaultService.notificationPermissionState
    }
    
    func setNotificationPermissionStatus(status: PermissonStatus) {
        userDefaultService.notificationPermissionState = status
    }
    
    
    @available(iOS 10.0, *)
    func didReceiveNotificationExtensionRequest(_ request: UNNotificationRequest,
                                                bestContentHandler: UNMutableNotificationContent) {
        notificationExtensionService.didReceiveNotificationExtensionRequest(request,
                                                                            bestContentHandler: bestContentHandler)
    }
    
    // MARK: - add Subsciber Attributes
    
    func add(attributes: Parameters, completionHandler: ((_ response: Bool, _ error: PEError?) -> Void)?) {
        let error = prerequesiteNetworkCallCheck {
            subscriberService.update(attributes: attributes, completionHandler: completionHandler)
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
    
    // MARK: - update trigger status
  func updateTrigger(status: Bool,
                     completionHandler: ((_ response: Bool, _ error: PEError?) -> Void)?) {
    let error = prerequesiteNetworkCallCheck {
        subscriberService.updateTrigger(status: status,
                                        completionHandler: completionHandler)
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
    
    // MARK: - Trigger Campaign
    func createCampaign(for details: TriggerCampaign,
                        completionHandler: ((_ response: Bool) -> Void)?) {
        let error = prerequesiteNetworkCallCheck {
            triggerCamapaiginService.createCampaign(for: details, completionHandler: completionHandler)
        }
        if error != nil {
            completionHandler?(false)
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
}
// MARK: - Swizzling and manually setup methods.

extension PEViewModel {
    
    func registerDeviceToServer(with deviceToken: Data) {
        applicationService.registerDeviceToServer(with: deviceToken)
    }
    
    func recivedRemoteNotification(application: UIApplication,
                                   userInfo: [AnyHashable: Any],
                                   completionHandler: ((UIBackgroundFetchResult) -> Void)?) -> Bool {
        applicationService.recivedRemoteNotification(application: application,
                                                     userInfo: userInfo,
                                                     completionHandler: completionHandler)
    }
    
    public func setNotificationOpenHandler(block: PEnotificationOpenHandler?) {
        Self.notificationOpenHandler = block
        self.handleNotificationForUnprocessedEvent()
    }
    
    public func setNotificationWillShowInForgroundHandler(block: PENotificationWillShowInForground?) {
        Self.notificationWillShowInForground = block
    }
    
    public func recivedNotification(with userInfo: [AnyHashable: Any], isOpened: Bool) {
        guard Utility.isPEPayload(userInfo: userInfo) else {
            PELogger.debug(className: String(describing: PEViewModel.self),
                           message: "Notification is not pushengage payload")
            return
        }
        PELogger.debug(className: String(describing: PEViewModel.self), message: "\(isOpened)")
        self.lastNotifyPayload = userInfo
        if isOpened {
            let newNotifyId = Utility.checkForDuplicateProcess(infoDict: userInfo,
                                                            lastRecivedNotifyId: lastNonActiveNotifyRecivedId ?? "")
            if newNotifyId == PayloadConstants.duplicate {
                PELogger.debug(className: String(describing: PEViewModel.self), message: "duplicate notifications.")
                return
            }
            lastNonActiveNotifyRecivedId = newNotifyId
            var type: ActionType = .opened
            if userInfo[userInfo: PayloadConstants
                            .custom]?[userInfo: PayloadConstants
                                        .additionalData]?[string: PayloadConstants.actionSelected] != nil {
                type = .taken
            }
            handleNotificationOpened(userInfo, with: type)
        }
    }
    
    public func handleWillPresentNotificationInForground(with payLoad: [AnyHashable: Any],
                                                         completionHandler: @escaping PENotificationDisplayNotification) {
        if !Utility.isPEPayload(userInfo: payLoad) ||
            application?.applicationState == .background {
            return
        }
        
        let notification = PENotification(userInfo: payLoad)
        if notification.isSponsered == 1 {
            self.handleWillShowInForgoundHandler(for: notification) { _ in
                completionHandler(notification)
            }
        } else {
            self.handleWillShowInForgoundHandler(for: notification, with: completionHandler)
        }
    }
    
    private func handleWillShowInForgoundHandler(for notification: PENotification,
                                                 with completionHandler: @escaping PENotificationDisplayNotification) {
        
        notification.setCompletion(for: completionHandler)
        if Self.notificationWillShowInForground != nil {
            notification.timeOutTimerSetup()
            notification.startTimeoutTimer()
            let block = notification.getCompletionBlock()
            Self.notificationWillShowInForground?(notification, block)
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
        PELogger.debug(className: String(describing: PEViewModel.self),
                       message: "notification opened for id \(notifId) and appstate is \(appState)")
        let launchURL = customDict[userInfo: PayloadConstants.custom]?[string: PayloadConstants.launchUrlKey]
        var actionId: String?
        if actionType == .taken {
             actionId = customDict[userInfo:PayloadConstants
                        .custom]?[userInfo:PayloadConstants
                        .additionalData]?[string:PayloadConstants
                        .actionSelected]
        }
        
        self.lastNotifyPayload = customDict
        if actionId == .defaultActionIdentifer {
            PELogger.debug(className: String(describing: PEViewModel.self),
                           message: "__DEFAUTL_ACTION__")
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
        let notification = PENotification(userInfo: lastNotifyPayload ?? [:])
        if let buttons = notification.actionButtons,
           let id = actionId,
           notification.isSponsered == 0 {
            for (index, button) in buttons.enumerated()
                where button.id == id {
                clickedButton = "action\(index + 1)"
            }
        }
        notificationLifeCycleService.withRetrynotificationLifecycleUpdate(with: .clicked,
                                                                 deviceHash: userDefaultService.subscriberHash,
                                                                 notificationId: notification.tag,
                                                                 actionid: clickedButton,
                                                                 completionHandler: nil)
        if actionId == userDefaultService.sponseredIdKey ,
           notification.isSponsered == 1 {
            self.onClickRedirect(to: notification.launchURL)
            PELogger.debug(className: String(describing: PEViewModel.self),
                           message: "Sponsered Notification.")
            return
        }
        
        let actionCreated = PEnotificationAction(actionID: actionId, actionType: actionType)
        let notificationResult = PENotificationOpenResult(notification: notification,
                                                          notficationAction: actionCreated)
        if notification.tag == lastNotifyIdFromAction {
            return
        }
        lastNotifyIdFromAction = notification.tag
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
        for value  in unprocessedNotification ?? [] {
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
       self.recivedNotification(with: parseuserInfo, isOpened: true)
    }
}

// MARK: - LastNotificationSetDelagate
extension PEViewModel: LastNotificationSetDelagate {

    func silentRemoteNotificationRecivedNotification(with userInfo: [AnyHashable: Any], isOpened: Bool) {
        self.recivedNotification(with: userInfo, isOpened: true)
    }
    
    func setLast(notification infoDict: [AnyHashable: Any],
                 completionHandler: ((UIBackgroundFetchResult) -> Void)?) {
        self.lastNotifyPayload = infoDict
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

extension PEViewModel {
    
    private func startTimerForSilentPush() {
        
        guard let unWrappedTimer = timer else {
            PELogger.debug(className: String(describing: PEViewModel.self),
                           message: "Timer for silent push is nil")
            return
        }
        RunLoop.current.add(unWrappedTimer, forMode: .common)
    }
    
    @objc private func completeTaskBacgroundSilentTask() {
        if silentCompletionTask != nil {
            silentCompletionTask?(.noData)
            silentCompletionTask = nil
            PELogger.debug(className: String(describing: PEViewModel.self),
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
            PELogger.debug(className: String(describing: PEViewModel.self),
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

extension PEViewModel {
    func update(notificationType: Int) {
        
        PELogger.debug(className: String(describing: PEViewModel.self),
                       message: "For iOS version less then 9 is asked")
        self.notificationService.registerToApns(for: application)
        self.notificationService.onNotificationPromptResponse(notification: notificationType)
    }
    
    func updateSwizzledStatus(with status: Bool) {
        userDefaultService.isSwizziled = status
    }
}
