//
//  PushEngageService.swift
//  PushEngage
//
//  Created by Abhishek on 25/01/21.
//

import UIKit

public typealias PEnotificationOpenHandler = (PENotificationOpenResult) -> Void

public typealias PEBackgroundTaskCompletionBlock =  ((UIBackgroundFetchResult) -> Void)

public typealias PESilentPushBackgroundHandler = (PENotification, PEBackgroundTaskCompletionBlock?) -> Void

public typealias PENotificationDisplayNotification = (_ notification: PENotification?) -> Void

public typealias PENotificationWillShowInForground
    = (PENotification, _ completion: PENotificationDisplayNotification) -> Void

@objcMembers
@objc final public class PushEngage: NSObject {
    
    // MARK: - public variable
    
    /// This computed variable is flag to enable or disable the logging  implementaion to debug and trouble-shooting
    /// with in the sdk. please disble the logging when host application is in production.
    public static var enableLogs: Bool {
        get {
             PELogger.isLoggingEnable
        }
        set {
            PELogger.isLoggingEnable = newValue
        }
    }
    
    // MARK: - private variable
    private static let shared = PushEngage()
    
    // MARK: - Dependency Injection for the view model in PushEngageServices
    
    internal static let viewModel = DependencyInitialize.getPEViewModelDependency()
    
    // MARK: - private initialization method
    
    private override init() {
        
        super.init()
    }
    
    private static let runOnce: Any? = {
       loadRequriedSizzling()
        _ = shared
        return nil
    }()
    
    // MARK: - public methods
    
    
    /// This is very important method to call for the setup of the SDK
    /// if developer doesn't want to take the over head to handle the setup call this
    /// method  in init method of the Application appdelegate. other wise developer has
    /// to set up the SDK manually.
    @objc public static func swizzleInjection(isEnabled: Bool) {
        if isEnabled {
            _ = Self.runOnce
        }
        viewModel.updateSwizzledStatus(with: isEnabled)
    }
    
    /// Use this static method to set the notification open block which is create while sdk initilization
    /// so  when notification is opened this handler will take requried action and provide deeplinking requried user info
    /// - Parameter block: pass the block type PEnotificationOpenHandler to the parameter
    ///                    so that when notification click action take place.
    @objc public static func setNotificationOpenHandler(block: PEnotificationOpenHandler?) {
        viewModel.setNotificationOpenHandler(block: block)
    }
    
    
    /// Use this static method to set the notifiction handler when notification recives when app is in forground mode.
    /// - Parameter block: pass the notificationForgroundHandler from the appdelegate.
    @objc public static func setNotificationWillShowInForgroundHandler(block: PENotificationWillShowInForground?) {
        viewModel.setNotificationWillShowInForgroundHandler(block: block)
    }
    
    
    /// call this method in appdelegate
    ///  to set the app push id to the SDK to register the subsciber to that app push id.
    /// - Parameter key: App push id.
    @objc public static func setAppId(key: String) {
        
        viewModel.setAppId(key: key)
    }
    
    @objc public static func setEnv(enviroment: Environment) {
        Configuration.enviroment = enviroment
    }
    
    
    /// call this method in appdelegate to start the notification services in the application.
    /// and provide some pre-requisite information to the
    ///  SDK to handle the SDK internal setup.
    /// - Parameters:
    ///   - application: UIApplication instance
    ///   - launchOptions: UiApplication launch options.
    @objc public static func startNotificationServices(for application: UIApplication,
                                                       with launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        viewModel.setIntialInfo(for: application, with: launchOptions)
        viewModel.startNotificationServices()
    }
    /// Description:- This method provides the Notification service extension feature to
    ///  modify the content  to the application. This api will invoke if mutable content = 1
    /// - Parameter request: Parameter is passed from the parent application so that method can modifiy the content.
    @available(iOS 10.0, *)
    @objc public static func didReceiveNotificationExtensionRequest(_ request: UNNotificationRequest,
                                                                    bestContentHandler: UNMutableNotificationContent) {
        viewModel.didReceiveNotificationExtensionRequest(request, bestContentHandler: bestContentHandler)
    }
    
    // update Subsciber Attributes
    
    /// use this api call to update or add the attribute of the subscriber
    /// - Parameters:
    ///   - attributes: attribute supports [String: Any] type. eg.(["name": "bob"]) like that
    ///   - completionHandler: call back response which provide the response as bool true and false with error.
    @objc public static  func add(attributes: Parameters,
                                     completionHandler: ((_ response: Bool,
                                                          _ error: Error?) -> Void)?) {
        viewModel.add(attributes: attributes, completionHandler: completionHandler)
    }
    //  get-subscriber-attributes
    
    
    /// use this method to get the attribute of the subscriber.
    /// - Parameter completionHandler: call back provide the atttribute information which is [String: Any]? type and error.
    @objc public static func getAttribute(completionHandler: @escaping(_ info: [String: Any]?,
                                                                       _ error: Error?) -> Void) {
        viewModel.getAttribute(completionHandler: completionHandler)
    }
    
    // add-profile-id
    
    /// This api is used to set the subscriber id to the server if sdk is successfully initialized in host application.
    /// - Parameters:
    ///   - id: subsciber id aka (user name of the subcriber in host application.)
    ///   - completionHandler: call this block to get the response of the api call which is bool.
    @objc public static func addProfile(for id: String,
                                        completionHandler: ((_ response: Bool,
                                                             _ error: Error?) -> Void)?) {
        viewModel.addProfile(for: id, completionHandler: completionHandler)
    }
    
    // delete Attributes
    
    
    /// This API used to delete the subscriber attriburtes from the pushengage server.
    /// - Parameters:
    ///   - values: Array of string with attribute value or pass empty array to remove compelete info.
    ///   - completionHandler: response call back for the user.
    @objc public static func deleteAttribute(values: [String],
                                             completionHandler: ((_ response: Bool,
                                                                  _ error: Error?) -> Void)?) {
        viewModel.deleteAttribute(values: values, completionHandler: completionHandler)
    }
    
    
    /// This Api used to remove the segments.
    /// - Parameters:
    ///   - segments: Array of String hold the information of segments to be removed.
    ///   - completionHandler: call back with boolean if true operation
    ///   completed sucessfully with error if any error occurs.
    @objc public static func remove(segments: [String], completionHandler: ((_ response: Bool,
                                                                            _ error: Error?) -> Void)?) {
        viewModel.update(segments: segments, with: .remove, completionHandler: completionHandler)
    }
    
    
    /// This Api used to add the segments.
    /// - Parameters:
    ///   - segments: Array of String hold the information of segments to be added.
    ///   - completionHandler: call back with boolean if true operation
    ///   completed sucessfully with error if any error occurs.
    @objc public static func add(segments: [String],
                                 completionHandler: ((_ response: Bool,
                                                      _ error: Error?) -> Void)?) {
        viewModel.update(segments: segments, with: .add,
                         completionHandler: completionHandler)
    }
    
    //  update dynamic segments
    
    /// update the dynamic segement which is created from the pushengage dash board.
    /// - Parameters:
    ///   - segments: Array of dictionary value where key is string type and value can be Any type.
    ///   - completionHandler: call back provide response boolean and Error type.
    @objc public static func add(dynamic segments: [[String: Any]],
                                 completionHandler: ((_ response: Bool,
                                                      _ error: Error?) -> Void)?) {
        viewModel.add(dynamic: segments, completionHandler: completionHandler)
    }
    
    //  update trigger status
    
    
    /// Update the trigger status of the notification
    /// - Parameters:
    ///   - status: boolean flag wheather user has accepted for trigger enabled or not
    ///   - completionHandler: call back provide response boolean and Error type.
    @objc public static func updateTrigger(status: Bool,
                                           completionHandler: ((_ response: Bool,
                                                                _ error: Error?) -> Void)?) {
        viewModel.updateTrigger(status: status, completionHandler: completionHandler)
    }
    
    //  get subscriber details
    
    
    /// Api provides the registered subscriber information.
    /// - Parameters:
    ///   - fields: provide the fields if need field specific information like country to get only country information
    ///             if no fields are provided then api will give complete Subscriber details
    ///   - completionHandler: Call back provides the response as Subscriber details
    @objc public static func getSubscriberDetails(for fields: [String]?,
                                                  completionHandler: ((_ response: SubscriberDetailsData? ,
                                                                       _ error: Error?) -> Void)?) {
        viewModel.getSubscriberDetails(for: fields, completionHandler: completionHandler)
    }
    
    // Trigger Campiagn Handler
    
    /// Use this method to create the trigger for the campiagn
    /// - Parameters:
    ///   - details: provide the insctance of the Trigger campaign object and pass the details on
    ///   - completionHandler: call back provides the response as true or false.
    @objc public static func createTriggerCampaign(for details: TriggerCampaign,
                                                   completionHandler: ((_ response: Bool) -> Void)?) {
        viewModel.createCampaign(for: details, completionHandler: completionHandler)
    }
    
    // best attempt handled
    
    
    /// Use this api in notification service extension for bes attempt to deliver the notification to the device.
    /// - Parameters:
    ///   - request: Notification Request
    ///   - content: Content for the notification
    /// - Returns: returns the UNMutableNotificationContent.
    @available(iOS 10.0, *)
    @objc public static func serviceExtensionTimeWillExpire(_ request: UNNotificationRequest,
                                                            content: UNMutableNotificationContent?)
                                                            -> UNMutableNotificationContent? {
        return viewModel.serviceExtensionTimeWillExpire(request, content: content)
    }
    
    /// Use this api to set the silent notification to handle silent push as it will give 30 sec of time frame to app so that
    /// any app update can be done.
    /// - Parameter completion: pass the silent notification handler to the method if developer doesn't
    ///                         set the completion
    @objc public static func silentPushHandler(_ completion: PESilentPushBackgroundHandler?) {
        viewModel.setbackGroundSilentPushHandler(block: completion)
    }
    
    @available(iOS 10.0, *)
    @objc public static func getCustomUIPayLoad(for request: UNNotificationRequest) -> CustomUIModel {
        viewModel.getCustomUIPayLoad(for: request)
    }
    
    // MARK: - Remote Notification Manually setup methods
    // if developer has not added swizzling in there appdelegate init method the developers
    // has use remote notification manually setup mathods.
    
    // MARK: - Register Device with server method.
    
    /// User has to register the device token to the server.
    /// - Parameter deviceToken: send token as data type.
    @objc public static func registerDeviceToServer(with deviceToken: Data) {
        viewModel.registerDeviceToServer(with: deviceToken)
    }
    
    //  didReciveRemoteNotification silent features.
    
    
    /// Use To handle the remote notification setup from SDK from the manual integration
    /// - Parameters:
    ///   - application: UIApplication instance
    ///   - userInfo: information while get notifiation userinfo to pass to SDK.
    ///   - completionHandler: this is UIBackgroundFetchResult handler user has to send the handler from application.
    /// - Returns:Boolean value as result like any backgound work started if true otherwise false.
    @discardableResult
    @objc public static func recivedRemoteNotification(application: UIApplication,
                                                       userInfo: [AnyHashable: Any],
                                                       completionHandler: ((UIBackgroundFetchResult) -> Void)?) -> Bool {
        viewModel.recivedRemoteNotification(application: application,
                                            userInfo: userInfo,
                                            completionHandler: completionHandler)
    }
    
    // These methods developer has to call if they are going to
    // implements the UNUsernotification Delegate method by them and disable swizzling.
    
    /// Setup method need to integrate in UNNotification delegate method to process the notification after
    /// subscriber performs any action to the notification.
    /// - Parameter notification: UNNotificationresponse of the notification delivered on device only for iOS 10+
    @available(iOS 10.0, *)
    @objc public static func didRecivedRemoteNotification(with notification: UNNotificationResponse) {
        viewModel.processiOS10Open(response: notification)
    }
    
}

// MARK: - Method Swizzling

extension PushEngage {
    
    private static func loadRequriedSizzling() {
        
        // PushEngage selector tagmethod is implemented for checking is whether
        // UIApplication is not loaded twice in runtime for the previous version check.
        // This will not happen in swift because implemented runOnce swift lazy
        // Using Swift's lazy evaluation of a static property we get the same
        // thread-safety and called-once guarantees as dispatch_once provided.
        
        let isExisting = PESelectorHelper.shared
                         .injectSelectorAtRuntime(PushEngageAppDelegate.self,
                                         #selector(PushEngageAppDelegate.pushEngageSELTag),
                                         UIApplication.self,
                                         #selector(PushEngageAppDelegate.pushEngageSELTag))
        if isExisting {
            PELogger.debug(className: String(describing: PushEngageAppDelegate.self),
                           message: "Already swizzled UIApplication.setDelegate")
            return
        }
        
        PESelectorHelper.shared.injectToActualClassAtRuntime(#selector(PushEngageAppDelegate.setPushEngageDelegate),
                                                           #selector(setter: UIApplication.delegate), [],
                                                           PushEngageAppDelegate.self, UIApplication.self)
        if #available(iOS 10.0, *) {
            setUNUserNotificationCenterDelegate()
        }
        
    }
    
    @available(iOS 10.0, *)
    private static func setUNUserNotificationCenterDelegate() {
        if NSClassFromString("UNUserNotificationCenter") == nil {
            return
        }
        PushEngageUNUserNotificationCenter.setup()
    }
}

