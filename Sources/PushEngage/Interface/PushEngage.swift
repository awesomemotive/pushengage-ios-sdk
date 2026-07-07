//
//  PushEngageService.swift
//  PushEngage
//
//  Created by Abhishek on 25/01/21.
//

import UIKit
import PushEngageExtension

public typealias PENotificationOpenHandler = (PENotificationOpenResult) -> Void

public typealias PEBackgroundTaskCompletionBlock =  ((UIBackgroundFetchResult) -> Void)

public typealias PESilentPushBackgroundHandler = (PENotification, PEBackgroundTaskCompletionBlock?) -> Void

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
    /// Set this on each launch (e.g. in `didFinishLaunching`); the value is mirrored to the shared
    /// app-group container for the current session so notification extension processes pick it up —
    /// no separate call in extension code. It is not a durable cross-launch preference.
    /// It is recommended to disable logging when the host application is in production to improve performance.
    public static var enableLogging: Bool {
        get {
             PELogger.isLoggingEnable
        }
        set {
            manager.setLoggingEnabled(newValue)
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

    /// Returns the SDK's release version string (e.g. `"1.0.0"`).
    ///
    /// Useful for surfacing the active SDK version in customer
    /// support / about screens. The value is stable for a given
    /// build and changes with each release.
    ///
    /// - Returns: A semver-formatted version string.
    @objc public static func getSdkVersion() -> String {
        return NetworkConstants.sdkVersion
    }

    /// Sets the wrapper-flavor segment of the SDK User-Agent. Wrappers
    /// (React Native, Flutter, etc.) call this during their own init to
    /// identify themselves to the backend. Pass one of the `PEPlatform`
    /// constants for known wrappers, or any string for custom integrations
    /// — the SDK does not gatekeep new wrappers. Empty string clears the
    /// stored value; the UA then falls back to native `iOS`.
    @objc public static func setPlatform(_ platform: String) {
        manager.setPlatform(platform)
    }

    /// Sets the wrapper-plugin version for the SDK User-Agent. Empty
    /// string clears the stored value; the wrapper-version slot is then
    /// omitted from the UA entirely.
    @objc public static func setWrapperVersion(_ wrapperVersion: String) {
        manager.setWrapperVersion(wrapperVersion)
    }

    /// Sends a custom analytics event to the backend.
    ///
    /// Validation rules:
    /// - `name` must be non-empty.
    /// - `properties` keys must be non-blank.
    /// - `properties` values must be `String`, `NSNumber` (Int/Double/Float),
    ///   or `Bool`. Arrays, dictionaries, dates, and other types are
    ///   rejected client-side via the completion handler.
    /// - `provider` defaults to `"PushEngage"` when nil.
    /// - `eventType` defaults to `"PushEngage.CustomEvent"` when nil.
    ///
    /// - Parameters:
    ///   - name: Event name (required).
    ///   - properties: Optional key/value payload sent in the request body.
    ///   - profileId: Optional subscriber profile id to attribute the event to.
    ///   - provider: Optional provider override.
    ///   - eventType: Optional event-type override.
    ///   - completionHandler: Completion fired with `(success, error)`.
    ///
    /// Example usage:
    /// ```swift
    /// PushEngage.trackEvent(name: "MySite.AddToCart",
    ///                       properties: ["amount": 19.99, "currency": "USD"],
    ///                       profileId: "user-42",
    ///                       provider: nil,
    ///                       eventType: nil) { success, error in
    ///     if success { print("Event tracked") }
    /// }
    /// ```
    @objc public static func trackEvent(name: String,
                                        properties: Parameters?,
                                        profileId: String?,
                                        provider: String?,
                                        eventType: String?,
                                        completionHandler: ((_ response: Bool,
                                                             _ error: Error?) -> Void)?) {
        manager.trackEvent(name: name,
                           properties: properties,
                           profileId: profileId,
                           provider: provider,
                           eventType: eventType,
                           completionHandler: completionHandler)
    }

    /// Lazily-constructed singleton handler for identify / logout. Created on
    /// first access so the SDK doesn't eagerly resolve the network router at
    /// `PushEngage` static-init time.
    private static let subscriberFieldsHandler: PESubscriberFieldsHandler = {
        PESubscriberFieldsHandler(networkRouter: DependencyInitialize.getRouter(),
                                  userDefaults: DependencyInitialize.getUserDefaults())
    }()

    /// Identifies the current subscriber with up to 12 predefined fields:
    /// `first_name`, `last_name`, `email`, `phone`, `gender`, `dob`,
    /// `language`, `profile_id`, `country`, `city`, `state`, `zip`.
    ///
    /// Sends `PUT /subscriber/{hash}` with the supplied field map. Values must
    /// be `String`, `NSNumber` (Int/Double/Float), or `Bool`; numeric
    /// `profile_id` is auto-coerced to its `String` form before transmission
    /// (web SDK parity).
    ///
    /// Repeat calls with the same payload short-circuit locally and fire the
    /// success callback without a network round-trip; the cache is bounded by
    /// a 24h TTL so dashboard-side edits surface within a day.
    ///
    /// - Parameters:
    ///   - fields: Subscriber fields to upsert.
    ///   - completionHandler: Completion fired with `(success, error)`.
    @objc public static func identify(fields: Parameters,
                                      completionHandler: ((_ response: Bool,
                                                           _ error: Error?) -> Void)?) {
        subscriberFieldsHandler.identify(fields: fields) { ok, error in
            completionHandler?(ok, error)
        }
    }

    /// Removes subscriber fields previously set via `identify`. `nil` or an
    /// empty list defaults to the PII set
    /// `[first_name, last_name, email, phone, gender, dob, profile_id]` —
    /// matches the web SDK logout fallback.
    ///
    /// Sends `DELETE /subscriber/{hash}/fields` with `{"fields": [<names>]}`.
    /// If none of the requested names are currently cached locally, fires the
    /// success callback without a network round-trip.
    ///
    /// - Parameters:
    ///   - fieldNames: Subscriber field names to remove, or `nil` for the
    ///                 default PII set.
    ///   - completionHandler: Completion fired with `(success, error)`.
    @objc public static func logout(fieldNames: [String]?,
                                    completionHandler: ((_ response: Bool,
                                                         _ error: Error?) -> Void)?) {
        subscriberFieldsHandler.logout(fieldNames: fieldNames) { ok, error in
            completionHandler?(ok, error)
        }
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
        manager.setNotificationWillShowInForegroundHandler(block: block)
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
    @objc public static func setEnvironment(environment: PEEnvironment) {
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
    /// - Parameter completion: A closure that gets called with the result of the permission request.
    ///                        Returns `true` if permission was granted, `false` if denied, and an optional error.
    @objc public static func requestNotificationPermission(completion: @escaping (_ response: Bool, _ error: Error?) -> Void) {
        manager.handleNotificationPermission(completion: completion)
    }
    
    /// Get the current notification permission status
    ///
    /// Use this method to retrieve the current notification permission status for the application.
    /// This method returns the permission status synchronously as a string.
    ///
    /// - Returns: A `String` indicating the current notification permission state:
    ///   - `"granted"`: The application is authorized to post user notifications
    ///   - `"denied"`: The application is not authorized to post user notifications  
    ///   - `"notYetRequested"`: The user has not yet made a choice regarding notification permissions
    ///
    /// Example usage:
    /// ```
    /// let permissionStatus = PushEngage.getNotificationPermissionStatus()
    /// switch permissionStatus {
    /// case "granted":
    ///     print("Notifications are allowed")
    /// case "denied":
    ///     print("Notifications are denied")
    /// case "notYetRequested":
    ///     print("Permission not yet requested")
    /// default:
    ///     print("Unknown permission status")
    /// }
    /// ```
    @objc public static func getNotificationPermissionStatus() -> String {
        return manager.getNotificationPermissionStatus().rawValue
    }
    
    /// Get the current subscription status
    ///
    /// Use this method to check whether the user is currently subscribed to push notifications.
    ///
    /// - Parameter completionHandler: A closure that provides the subscription status as a boolean value,
    ///                               along with an optional error if the operation fails.
    ///                               Returns `true` if the user is subscribed, `false` if unsubscribed.
    ///
    /// Example usage:
    /// ```
    /// PushEngage.getSubscriptionStatus { isSubscribed, error in
    ///     if let error = error {
    ///         print("Failed to get subscription status: \(error.localizedDescription)")
    ///     } else {
    ///         if isSubscribed {
    ///             print("User is subscribed to push notifications")
    ///         } else {
    ///             print("User is unsubscribed from push notifications")
    ///         }
    ///     }
    /// }
    /// ```
    @objc public static func getSubscriptionStatus(completionHandler: @escaping (_ isSubscribed: Bool, _ error: Error?) -> Void) {
        manager.getSubscriptionStatus(completionHandler: completionHandler)
    }
    
    /// Get whether the user can receive notifications
    ///
    /// Use this method to check whether the user can actually receive push notifications by verifying
    /// both subscription status and notification permission. The user can receive notifications only if
    /// they are subscribed AND the app has notification permission granted.
    ///
    /// - Parameter completionHandler: A closure that provides a boolean value indicating whether the user
    ///                               can receive notifications, along with an optional error if the operation fails.
    ///                               Returns `true` if the user can receive notifications, `false` otherwise.
    ///
    /// Example usage:
    /// ```
    /// PushEngage.getSubscriptionNotificationStatus { canReceiveNotifications, error in
    ///     if let error = error {
    ///         print("Failed to get notification status: \(error.localizedDescription)")
    ///     } else {
    ///         if canReceiveNotifications {
    ///             print("User can receive push notifications")
    ///         } else {
    ///             print("User cannot receive push notifications")
    ///         }
    ///     }
    /// }
    /// ```
    @objc public static func getSubscriptionNotificationStatus(completionHandler: @escaping (_ canReceiveNotifications: Bool, _ error: Error?) -> Void) {
        manager.getSubscriptionNotificationStatus(completionHandler: completionHandler)
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
    @available(*, deprecated, renamed: "addSubscriberAttributes(_:completionHandler:)")
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
    @available(*, deprecated, renamed: "setSubscriberAttributes(_:completionHandler:)")
    @objc public static func set(attributes: Parameters,
                                  completionHandler: ((_ response: Bool,
                                                          _ error: Error?) -> Void)?) {
        manager.set(attributes: attributes, completionHandler: completionHandler)
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
    ///   PushEngage.addSubscriberAttributes(attributes) { success, error in
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
    @objc public static func addSubscriberAttributes(_ attributes: Parameters,
                                                     completionHandler: ((_ response: Bool,
                                                                          _ error: Error?) -> Void)? = nil) {
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
    ///   PushEngage.setSubscriberAttributes(attributes) { success, error in
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
    @objc public static func setSubscriberAttributes(_ attributes: Parameters,
                                                     completionHandler: ((_ response: Bool,
                                                                          _ error: Error?) -> Void)? = nil) {
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
    
    /// Unsubscribe Subscriber
    ///
    /// This method enables you to unsubscribe the current subscriber from receiving push notifications. 
    /// Once unsubscribed, the subscriber will no longer receive any push notifications.
    ///
    /// - Parameter completionHandler: A closure that provides a response indicating whether the operation was successful (`true` if successful, `false` otherwise) and an optional error object if any error occurs during the operation.
    ///
    /// Example usage:
    /// ```
    /// PushEngage.unsubscribe { result, error in
    ///     if result {
    ///         print("Successfully unsubscribed from push notifications")
    ///     } else {
    ///         if let error = error {
    ///             print("Failed to unsubscribe: \(error.localizedDescription)")
    ///         } else {
    ///             print("Unknown error occurred while unsubscribing")
    ///         }
    ///     }
    /// }
    /// ```
    @objc public static func unsubscribe(completionHandler: ((_ response: Bool,
                                                              _ error: Error?) -> Void)?) {
        manager.unsubscribe(completionHandler: completionHandler)
    }
    
    /// Manually subscribe the user to receive push notifications.
    ///
    /// Use this method when you want to manually subscribe a user who has previously unsubscribed.
    ///
    /// - Parameter completionHandler: A completion handler that provides the response of the method call as a boolean value,
    ///                               along with an optional error if the operation fails.
    ///
    /// Example usage:
    /// ```
    /// PushEngage.subscribe { response, error in
    ///     if response {
    ///         print("Successfully subscribed to notifications.")
    ///     } else {
    ///         if let error = error {
    ///             print("Failed to subscribe: \(error.localizedDescription)")
    ///         }
    ///     }
    /// }
    /// ```
    @objc public static func subscribe(completionHandler: ((_ response: Bool,
                                                            _ error: Error?) -> Void)?) {
        manager.subscribe(completionHandler: completionHandler)
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
    
    /// Get Subscriber ID
    ///
    /// Use this method to retrieve the unique subscriber ID for a user. PushEngage generates this ID for every user
    /// based on their subscription data. Sometimes, this ID is referred to as the 'subscriber_hash'. The subscriber ID
    /// remains consistent unless there's a change in the user's subscription. If the user is not subscribed, it will return nil.
    ///
    /// - Returns: A `String?` representing the subscriber ID. Returns `nil` if the user is not subscribed.
    ///
    /// Example usage:
    /// ```
    /// if let subscriberId = PushEngage.getSubscriberId() {
    ///     print("Subscriber ID: \(subscriberId)")
    /// } else {
    ///     print("User is not subscribed")
    /// }
    /// ```
    @objc public static func getSubscriberId(completion: @escaping (_ response: String?) -> Void) {
        manager.getSubscriberId(completion: completion)
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

