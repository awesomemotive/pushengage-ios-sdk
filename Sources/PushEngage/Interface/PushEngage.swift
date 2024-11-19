//
//  PushEngageService.swift
//  PushEngage
//
//  Created by Abhishek on 25/01/21.
//

import UIKit

public typealias PENotificationOpenHandler = (PENotificationOpenResult) -> Void

public typealias PEBackgroundTaskCompletionBlock =  ((UIBackgroundFetchResult) -> Void)

public typealias PESilentPushBackgroundHandler = (PENotification, PEBackgroundTaskCompletionBlock?) -> Void

public typealias PENotificationDisplayNotification = (_ notification: PENotification?) -> Void

public typealias PENotificationWillShowInForeground
    = (PENotification, _ completion: PENotificationDisplayNotification) -> Void

@objc public enum TriggerStatusType: Int {
    case enabled = 1
    case disabled = 0
}

@objcMembers
@objc final public class PushEngage: NSObject {
    
    // MARK: - Private properties
    
    private static let shared = PushEngage()
    
    private static let runOnce: Any? = {
        loadRequiredSizzling()
        _ = shared
        return nil
    }()
    
    /// Dependency injection for PushEngage manager
    internal static let manager = DependencyInitialize.getPEManagerDependency()
    
    private override init() {
        super.init()
    }
    
    // MARK: - Public properties
    
    /// A boolean flag to enable or disable logging within the SDK for debugging and troubleshooting purposes.
    /// It is recommended to disable logging when the host application is in production to improve performance.
    public static var enableLogging: Bool {
        get {
             PELogger.isLoggingEnable
        }
        set {
            PELogger.isLoggingEnable = newValue
        }
    }
    
    // MARK: - Public methods
    /// Sets the badge count for the application icon.
    ///
    /// This method allows you to update the numeric badge displayed on the application's icon.
    /// The badge is typically used to indicate the number of pending notifications or updates.
    ///
    /// - Parameters:
    ///   - count: An integer value representing the number to be displayed as the badge.
    ///            Use 0 to remove the badge.
    @objc public static func setBadgeCount(count: Int) {
        manager.setBadgeCount(count: count)
    }
    
    /// This method is crucial for setting up the SDK. If the developer prefers not to handle the setup manually,
    /// calling this method in the `init` method of the Application AppDelegate is essential. Otherwise, the SDK
    /// must be set up manually.
    ///
    /// - Parameters:
    ///   - isEnabled: A boolean value indicating whether to enable the SDK setup through method swizzling.
    @objc public static func swizzleInjection(isEnabled: Bool) {
        if isEnabled {
            _ = Self.runOnce
        }
        manager.updateSwizzledStatus(with: isEnabled)
    }
    
    /// Use this static method to set the notification open handler, which is created during SDK initialization.
    /// When a notification is opened, this handler will take the necessary action and provide the required
    /// user information for deep linking.
    ///
    /// - Parameter block: The block of type `PENotificationOpenHandler` to be set as the notification open handler.
    @objc public static func setNotificationOpenHandler(block: PENotificationOpenHandler?) {
        manager.setNotificationOpenHandler(block: block)
    }
    
    /// Use this static method to set the notification handler for when notifications are received while the app is in foreground mode.
    ///
    /// - Parameter block: Pass the `PENotificationWillShowInForeground` block from the `AppDelegate` to handle notifications when the app is active.
    @objc public static func setNotificationWillShowInForegroundHandler(block: PENotificationWillShowInForeground?) {
        manager.setNotificationWillShowInForgroundHandler(block: block)
    }
    
    /// Call this method in the `AppDelegate` to set the app push ID in the SDK, registering the subscriber to that specific app push ID.
    ///
    /// - Parameter key: The app push ID to be set.
    @objc public static func setAppID(id: String) {
        manager.setAppId(key: id)
    }
    
    /// Set the environment for the SDK, allowing developers to switch between different environments (e.g., staging, production).
    ///
    /// - Parameter environment: The desired environment to be set (e.g., .staging, .production).
    @objc public static func setEnvironment(environment: Environment) {
        manager.setEnvironment(environment)
    }
    
    /// Provide necessary pre-requisite information to the SDK for internal setup.
    ///
    /// - Parameters:
    ///   - application: The UIApplication instance of the host application.
    ///   - launchOptions: The launch options passed to the application during launch.
    @objc public static func setInitialInfo(for application: UIApplication,
                                                       with launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        manager.setInitialInfo(for: application, with: launchOptions)
    }
    
    /// Request notification permission
    @objc public static func requestNotificationPermission() {
        manager.handleNotificationPermission()
    }
    
    /// Updates attributes of a subscriber. If an attribute with the specified key already exists, the existing value
    /// will be replaced.
    ///
    /// - Parameters:
    ///   - attributes: Attributes to be added. Should be in the format ["attributeName": attributeValue].
    ///   - completionHandler: A closure that gets called after the update operation is completed.
    ///                         Provides a response boolean indicating success or failure and an optional error.
    ///
    /// - Note: The `attributes` parameter supports [String: Any] type, for example: ["name": "Bob"].
    ///
    /// - Example usage:
    ///   ```
    ///   let attributes = ["name": "Bob", "age": 30]
    ///   PushEngage.add(attributes: attributes) { success, error in
    ///       if success {
    ///           print("Attributes added/updated successfully.")
    ///       } else {
    ///           if let error = error {
    ///               print("Error occurred: \(error.localizedDescription)")
    ///           } else {
    ///               print("Unknown error occurred.")
    ///           }
    ///       }
    ///   }
    ///   ```
    @objc public static func add(attributes: Parameters,
                                  completionHandler: ((_ response: Bool,
                                                          _ error: Error?) -> Void)?) {
        manager.add(attributes: attributes, completionHandler: completionHandler)
    }
    
    /// Sets attributes of a subscriber replacing any previously associated attributes.
    ///
    /// - Parameters:
    ///   - attributes: Attributes to be added. Should be in the format ["attributeName": attributeValue].
    ///   - completionHandler: A closure that gets called after the update operation is completed.
    ///                         Provides a response boolean indicating success or failure and an optional error.
    ///
    /// - Note: The `attributes` parameter supports [String: Any] type, for example: ["name": "Bob"].
    ///
    /// - Example usage:
    ///   ```
    ///   let attributes = ["name": "Bob", "age": 30]
    ///   PushEngage.set(attributes: attributes) { success, error in
    ///       if success {
    ///           print("Attributes added/updated successfully.")
    ///       } else {
    ///           if let error = error {
    ///               print("Error occurred: \(error.localizedDescription)")
    ///           } else {
    ///               print("Unknown error occurred.")
    ///           }
    ///       }
    ///   }
    ///   ```
    @objc public static func set(attributes: Parameters,
                                  completionHandler: ((_ response: Bool,
                                                          _ error: Error?) -> Void)?) {
        manager.set(attributes: attributes, completionHandler: completionHandler)
    }
    
    /// Retrieve the attributes of the subscriber.
    ///
    /// Use this method to get the attributes associated with the subscriber.
    ///
    /// - Parameters:
    ///   - completionHandler: A completion handler that provides the attribute information as [String: Any]?,
    ///                         along with an optional error if the operation fails.
    ///
    @objc public static func getSubscriberAttributes(completionHandler: @escaping(_ info: [String: Any]?,
                                                                       _ error: Error?) -> Void) {
        manager.getAttribute(completionHandler: completionHandler)
    }
    
    /// Add a subscriber profile ID.
    ///
    /// Use this method to associate a subscriber ID (e.g., the username of the subscriber in the host application) with the SDK.
    ///
    /// - Parameters:
    ///   - id: The subscriber ID to associate with the SDK.
    ///   - completionHandler: A completion handler that provides the response of the method call as a boolean value,
    ///                        along with an optional error if the operation fails.
    ///
    /// Example usage:
    /// ```
    /// PushEngage.addProfile(for: "your-unique-ID") { response, error in
    ///     if response {
    ///         print("Subscriber profile added successfully.")
    ///     } else {
    ///         if let error = error {
    ///             print("Failed to add subscriber profile: \(error.localizedDescription)")
    ///         } else {
    ///             print("Unknown error occurred while adding subscriber profile.")
    ///         }
    ///     }
    /// }
    ///
    /// ```
    @objc public static func addProfile(for id: String,
                                        completionHandler: ((_ response: Bool,
                                                             _ error: Error?) -> Void)?) {
        manager.addProfile(for: id, completionHandler: completionHandler)
    }
    
    /// Delete Subscriber Attributes.
    ///
    /// Use this method to remove specific subscriber attributes from the PushEngage server.
    ///
    /// - Parameters:
    ///   - keys: An array of strings representing the attribute keys to be removed.
    ///             Pass an empty array to remove all subscriber attributes associated with the device.
    ///   - completionHandler: A completion handler that provides the response of the API call as a boolean value,
    ///                        along with an optional error if the operation fails.
    ///
    /// Example usage:
    /// ```
    /// PushEngage.deleteSubscriberAttributes(["AttributeKeyToDelete"]) { response, error in
    ///     if response {
    ///         print("Attributes deleted successfully.")
    ///     } else {
    ///         if let error = error {
    ///             print("Failed to delete attributes: \(error.localizedDescription)")
    ///         } else {
    ///             print("Unknown error occurred while deleting attributes.")
    ///         }
    ///     }
    /// }
    ///
    /// ```
    @objc public static func deleteSubscriberAttributes(for keys: [String],
                                                        completionHandler: ((_ response: Bool,
                                                                             _ error: Error?) -> Void)?) {
        manager.deleteAttribute(values: keys, completionHandler: completionHandler)
    }
    
    /// Remove Segments for Subscriber.
    ///
    /// Use this method to remove specific segments associated with the subscriber.
    ///
    /// - Parameters:
    ///   - segments: An array of strings representing the segment names to be removed from the subscriber.
    ///   - completionHandler: A completion handler that provides the response of the method call as a boolean value,
    ///                        along with an optional error if the operation fails.
    /// Example usage:
    /// ```
    /// PushEngage.removeSegments(["SegmentToRemove"]) { response, error in
    ///     if response {
    ///         print("Segments removed successfully.")
    ///     } else {
    ///         if let error = error {
    ///             print("Failed to remove segments: \(error.localizedDescription)")
    ///         } else {
    ///             print("Unknown error occurred while removing segments.")
    ///         }
    ///     }
    /// }
    ///
    /// ```
    @objc public static func removeSegments(_ segments: [String], completionHandler: ((_ response: Bool,
                                                                            _ error: Error?) -> Void)?) {
        manager.update(segments: segments, with: .remove, completionHandler: completionHandler)
    }
    
    
    /// Adds subscriber to segments.
    ///
    /// This method is used to add the subscriber to segments.
    ///
    /// - Parameters:
    ///   - segments: An array of strings containing segment information to be added to the subscriber's profile.
    ///   - completionHandler: A closure that provides a response indicating whether the operation was successful (`true` if successful, `false` otherwise) and an optional error object if any error occurs during the operation.
    ///     - response: A boolean value indicating the success of the operation.
    ///     - error: An optional error object describing the error that occurred during the operation, if any.
    ///
    /// Example usage:
    /// ```
    /// PushEngage.addSegments(["Segment1", "Segment2"]) { response, error in
    ///     if response {
    ///         print("Segments added successfully.")
    ///     } else {
    ///         if let error = error {
    ///             print("Failed to add segments: \(error.localizedDescription)")
    ///         } else {
    ///             print("Unknown error occurred while adding segments.")
    ///         }
    ///     }
    /// }
    ///
    /// ```
    @objc public static func addSegments(_ segments: [String],
                                 completionHandler: ((_ response: Bool,
                                                      _ error: Error?) -> Void)?) {
        manager.update(segments: segments, with: .add,
                         completionHandler: completionHandler)
    }
    
    /// Add subscriber to dynamic segments
    ///
    /// Use this method to add subscriber to segments created from the PushEngage dashboard for a particular duration.
    ///
    /// - Parameters:
    ///   - dynamicSegments: An array of dictionaries where the keys are strings and the values can be of any type.
    ///   - completionHandler: A closure that provides a boolean response indicating whether the operation was successful (`true` if successful, `false` otherwise) and an optional error object if any error occurs during the operation.
    ///
    /// Example usage:
    /// ```
    /// let dynamicSegments: [[String: Any]] = [
    ///     ["name": "Cricket", "duration": 3],
    ///     ["name": "Tennis", "duration": 7],
    /// ]
    ///
    /// PushEngage.addDynamicSegments(dynamicSegments) { response, error in
    ///     if response {
    ///         print("Dynamic segments updated successfully.")
    ///     } else {
    ///         if let error = error {
    ///             print("Failed to update dynamic segments: \(error.localizedDescription)")
    ///         } else {
    ///             print("Unknown error occurred while updating dynamic segments.")
    ///         }
    ///     }
    /// }
    /// ```
    @objc public static func addDynamicSegments(_ dynamicSegments: [[String: Any]],
                                 completionHandler: ((_ response: Bool,
                                                      _ error: Error?) -> Void)?) {
        manager.add(dynamic: dynamicSegments, completionHandler: completionHandler)
    }
    
    /// Update trigger campaign status
    /// - Parameters:
    ///   - status: status type to enable or disable trigger campaign status
    ///   - completionHandler: A closure that provides a response indicating whether the operation was successful (`true` if successful, `false` otherwise) and an optional error object if any error occurs during the operation.
    ///
    /// Example usage:
    /// ```
    ///   PushEngage.automatedNotification(status: .enabled) { result, error in
    ///      if result {
    ///         print("Trigger enabled successfully")
    ///      } else {
    ///         print("Failure")
    ///      }
    ///   }
    /// ```
    @objc public static func automatedNotification(status: TriggerStatusType,
                                                   completionHandler: ((_ response: Bool,
                                                                        _ error: Error?) -> Void)?) {
        manager.automatedNotification(status: status, completionHandler: completionHandler)
    }
    
    /// Sends a goal event with the provided callback for handling the response.
    ///  - Parameters:
    ///     - goal: Goal object representing the goal to be tracked.
    ///     - completionHandler: A closure that provides a response indicating whether the operation was successful (`true` if successful, `false` otherwise) and an optional error object if any error occurs during the operation.
    ///
    /// Example usage:
    /// ```
    ///   let goal = Goal(name: "revenue", count: 1, value: 10.0)
    ///   PushEngage.sendGoal(goal: goal) { result, error in
    ///      if result {
    ///         print("Goal Added Successfully")
    ///      } else {
    ///         print("Failure")
    ///      }
    ///   }
    /// ```
    @objc public static func sendGoal(goal: Goal,
                                      completionHandler: ((_ response: Bool,
                                                           _ error: Error?) -> Void)?) {
        manager.sendGoal(goal: goal, completionHandler: completionHandler)
    }
    
    /// Sends a trigger event for a specific campaign with the provided callback for handling the response.
    /// - Parameters:
    ///   - triggerCampaign: The TriggerCampaign object representing the campaign event to be triggered.
    ///   - completionHandler: A closure that provides a response indicating whether the operation was successful (`true` if successful, `false` otherwise) and an optional error object if any error occurs during the operation.
    ///
    /// Example usage:
    /// ```
    ///  let triggerCampaign = TriggerCampaign(campaignName: "name_of_campaign", eventName: "name_of_event", data: ["title": "New Subscriber"])
    ///
    ///   PushEngage.sendTriggerEvent(triggerCampaign: triggerCampaign) { result, error in
    ///      if result {
    ///         print("Send Trigger Alert Successful")
    ///      } else {
    ///         print("Failure")
    ///      }
    ///   }
    /// ```
    @objc public static func sendTriggerEvent(triggerCampaign: TriggerCampaign,
                                              completionHandler: ((_ response: Bool,
                                                                   _ error: Error?) -> Void)?) {
        manager.sendTriggerEvent(trigger: triggerCampaign, completionHandler: completionHandler)
    }
    
    /// Adds an alert to be triggered with the provided callback for handling the response.
    ///  - Parameters:
    ///     - triggerAlert: The TriggerAlert object representing the alert to be added.
    ///     - completionHandler: A closure that provides a response indicating whether the operation was successful (`true` if successful, `false` otherwise) and an optional error object if any error occurs during the operation.
    ///
    /// Example usage:
    /// ```
    ///  let triggerAlert = TriggerAlert(type: .inventory, productId: "279a", link: "www.pushengage.com/products", price: 100.0, data: ["title": "New Subscriber"])
    ///
    ///   PushEngage.addAlert(triggerAlert: triggerAlert) { result, error in
    ///      if result {
    ///         print("Add Alert Successful")
    ///      } else {
    ///         print("Failure")
    ///      }
    ///   }
    /// ```
    @objc public static func addAlert(triggerAlert: TriggerAlert, completionHandler: ((_ response: Bool,
                                                                                       _ error: Error?) -> Void)?) {
        manager.addAlert(triggerAlert: triggerAlert, completionHandler: completionHandler)
    }
    
    /// Get Subscriber Details
    ///
    /// Use this method to retrieve information about the registered subscriber.
    ///
    /// - Parameters:
    ///   - keys: An optional array of strings specifying the specific keys of information to retrieve for the subscriber.
    ///           If no keys are provided, the API will return complete subscriber details. (Optional)
    ///   - completionHandler: A closure that provides the response as a `SubscriberDetailsData` object representing the subscriber details, or an optional error object if any error occurs during the operation.
    ///
    /// Example usage:
    /// ```
    /// let specificKeys = ["country", "age"] // Optional: Retrieve specific keys like country and age.
    ///
    /// PushEngage.getSubscriberDetails(for: specificKeys) { response, error in
    ///     if let subscriberDetails = response {
    ///         print("Subscriber Details: \(subscriberDetails)")
    ///     } else {
    ///         if let error = error {
    ///             print("Failed to retrieve subscriber details: \(error.localizedDescription)")
    ///         } else {
    ///             print("Unknown error occurred while retrieving subscriber details.")
    ///         }
    ///     }
    /// }
    /// ```
    @objc public static func getSubscriberDetails(for keys: [String]?,
                                                  completionHandler: ((_ response: SubscriberDetailsData?,
                                                                       _ error: Error?) -> Void)?) {
        manager.getSubscriberDetails(for: keys, completionHandler: completionHandler)
    }
    
    /// Silent Push Notification Handler
    ///
    /// Use this method to set the silent notification handler to handle silent push notifications.
    /// It will give 30 seconds of time frame to the app so that any app update can be done.
    ///
    /// - Parameter completion: A closure that provides the silent push notification content.
    ///
    /// Use this method in your application to handle silent push notifications. Silent push notifications are notifications
    /// that don't display any visible content to the user but allow your app to perform tasks in the background. When a silent
    /// push notification is received, the provided closure will be called, allowing you to process the notification's content
    /// and perform necessary background tasks.
    @objc private static func silentPushHandler(_ completion: PESilentPushBackgroundHandler?) {
        manager.setbackGroundSilentPushHandler(block: completion)
    }
    
    // MARK: Notification Content Extension methods
    
    /// Get Custom UI Payload for Notification
    ///
    /// Use this method to get the custom UI payload associated with a notification request.
    ///
    /// - Parameter request: The UNNotificationRequest object for which you want to retrieve the custom UI payload.
    /// - Returns: A CustomUIModel object containing the custom UI payload for the given notification request.
    @available(iOS 10.0, *)
    @objc public static func getCustomUIPayLoad(for request: UNNotificationRequest) -> CustomUIModel {
        manager.getCustomUIPayLoad(for: request)
    }
    
    // MARK: Notification Service Extension methods
    
    /// Modify the notification content received from the parent application in the Notification Service Extension.
    ///
    /// - Parameters:
    ///   - request: The UNNotificationRequest received from the parent application.
    ///   - bestContentHandler: The UNMutableNotificationContent that can be modified to customize the notification.
    @available(iOS 10.0, *)
    @objc public static func didReceiveNotificationExtensionRequest(_ request: UNNotificationRequest,
                                                                    bestContentHandler: UNMutableNotificationContent) {
        manager.didReceiveNotificationExtensionRequest(request, bestContentHandler: bestContentHandler)
    }
    
    /// Service Extension Time Will Expire Handler
    ///
    /// Use this method in the notification service extension to handle best attempts to deliver the notification to the device.
    ///
    /// - Parameters:
    ///   - request: The original `UNNotificationRequest` received by the extension.
    ///   - content: The mutable content for the notification. This content can be modified as needed before delivery.
    ///
    /// - Returns: The modified `UNMutableNotificationContent` that will be delivered to the user
    ///
    /// When the notification service extension time is about to expire, this method should be called to allow the SDK to modify the
    /// notification content before delivery.
    @available(iOS 10.0, *)
    @objc public static func serviceExtensionTimeWillExpire(_ request: UNNotificationRequest,
                                                            content: UNMutableNotificationContent?)
                                                            -> UNMutableNotificationContent? {
        return manager.serviceExtensionTimeWillExpire(request, content: content)
    }
    
    // MARK: - Remote Notification manual setup methods

    /// Register Device Token Manually
    ///
    /// Use this method to manually register the device token with the PushEngage server if swizzling is not used.
    ///
    /// - Parameter deviceToken: The device token obtained from Apple Push Notification service (APNs) as Data.
    ///
    /// Call this method in your app delegate's `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)` method
    /// to register the device token with the PushEngage server manually.
    ///
    /// Example usage:
    /// ```
    /// func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    ///     PushEngage.registerDeviceToServer(with: deviceToken)
    /// }
    /// ```
    ///
    /// - Note: If you are using swizzling, you do not need to manually register the device token.
    @objc public static func registerDeviceToServer(with deviceToken: Data) {
        manager.registerDeviceToServer(with: deviceToken)
    }
    
    /// Handle Remote Notifications Manually
    ///
    /// Use this method to handle remote notifications manually if swizzling is not used or if you want to
    /// customize the notification handling behavior.
    ///
    /// - Parameters:
    ///   - application: UIApplication instance.
    ///   - userInfo: The remote notification payload received from APNs as [AnyHashable: Any].
    ///   - completionHandler: The completion handler provided by the host application for background fetch completion.
    ///                        This handler must be called after processing the notification.
    ///
    /// - Returns: A boolean value indicating if any background work was started by the SDK.
    ///
    /// Call this method in your app delegate's `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` method.
    ///
    /// Example usage:
    /// ```
    /// func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    ///                  fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    ///     let didStartBackgroundWork = PushEngage.receivedRemoteNotification(application: application,
    ///                                                                         userInfo: userInfo,
    ///                                                                         completionHandler: completionHandler)
    ///     if !didStartBackgroundWork {
    ///         // Handle the notification in the foreground, if required.
    ///     }
    /// }
    /// ```
    ///
    /// - Note: If you are using swizzling, you do not need to manually handle remote notifications.
    @discardableResult
    @objc public static func receivedRemoteNotification(application: UIApplication,
                                                       userInfo: [AnyHashable: Any],
                                                       completionHandler: ((UIBackgroundFetchResult) -> Void)?) -> Bool {
        manager.receivedRemoteNotification(application: application,
                                            userInfo: userInfo,
                                            completionHandler: completionHandler)
    }
    
    /**
     Handles the remote notification interaction for devices running iOS 10.0 and above.

     This method should be implemented in the application's UNUserNotificationCenterDelegate to process the user's response to a remote notification.
     When a user interacts with a notification, this method should be called to handle the response and perform appropriate actions based on the user's interaction.

     - Note: This method should only be implemented if the application chooses to handle UNNotificationResponse objects manually and has disabled method swizzling for notification handling.

     - Parameter notification: The UNNotificationResponse object representing the user's response to a remote notification. It contains information about the notification.
     */
    @available(iOS 10.0, *)
    @objc public static func didReceiveRemoteNotification(with notification: UNNotificationResponse) {
        manager.processiOS10Open(response: notification)
    }
    
    /**
     Handles the presentation of a notification while the app is in the foreground for devices running iOS 10.0 and above.

     This method should be implemented in the application's UNUserNotificationCenterDelegate to manage how a notification is presented when the app is in the foreground. By default, notifications may not be shown when the app is active, but this method allows you to control whether they should be presented.

     - Note: This method should only be implemented if the application chooses to handle the presentation of notifications manually and has disabled method swizzling for notification handling.

     - Parameters:
        - center: The UNUserNotificationCenter responsible for delivering the notification.
        - notification: The UNNotification object containing the notification information that was delivered.
        - completionHandler: A completion handler to execute with the desired notification presentation options. You can choose options like alert, sound, and badge to determine how the notification is presented.
     */
    @objc public static func willPresentNotification(center: UNUserNotificationCenter, notification: UNNotification, completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        manager.willPresentNotification(center: center, notification: notification, completionHandler: completionHandler)
    }
        
}

// MARK: - Method Swizzling
extension PushEngage {
    /**
     Loads the required method swizzling for PushEngage SDK during the application's runtime initialization.

     This method performs method swizzling to ensure proper integration of PushEngage SDK within the application.
     It checks if the swizzling has already been performed to prevent duplicating the process.
     */
    private static func loadRequiredSizzling() {
        /**
         Checks if the `UIApplication` delegate methods are loaded twice during runtime, ensuring proper version compatibility.

         The implementation utilizes Swift's lazy evaluation of a static property, ensuring thread-safety and guaranteeing that the code within the property is executed only once, providing similar behavior to `dispatch_once`.
         */
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
    
    /**
     Sets the delegate for UNUserNotificationCenter, enabling the handling of notifications for devices running iOS 10 and above.

     This method checks if the UNUserNotificationCenter class is available (introduced in iOS 10) to ensure compatibility.
     If the class is available, it initializes and sets up the PushEngageUNUserNotificationCenter, enabling the app to handle notifications using the User Notifications framework.
     */
    @available(iOS 10.0, *)
    private static func setUNUserNotificationCenterDelegate() {
        if NSClassFromString("UNUserNotificationCenter") == nil {
            return
        }
        PushEngageUNUserNotificationCenter.setup()
    }
}

