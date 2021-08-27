//
//  Utility.swift
//  PushEngage
//
//  Created by Abhishek on 25/02/21.
//

import Foundation
import UIKit

enum RetryApi {
    case allow
    case denied
}

struct Utility {
    
    static var getBundleIdentifier: String {
        return Bundle.main.bundleIdentifier ?? ""
    }
    
    static var getApplicationName: String {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        return appName ?? ""
    }
    
    static var getPhoneName: String {
        return UIDevice.current.model
    }
    
    static var getOSInfo: String {
        let os = ProcessInfo().operatingSystemVersion
        return String(os.majorVersion) + "." + String(os.minorVersion) + "." + String(os.patchVersion)
    }
    
    static var getCurrentDeviceVersion: String {
        return UIDevice.current.systemVersion
    }
    
    static var getAppVersionInfo: String {
        let dictionary = Bundle.main.infoDictionary!
        let version = dictionary["CFBundleShortVersionString"] as? String ?? ""
        let build = dictionary["CFBundleVersion"] as? String ?? ""
        return version + "(" + build + ")"
    }
    
    static var timeOffSet: String {
        let timeZone = TimeZone(secondsFromGMT: TimeZone.autoupdatingCurrent.secondsFromGMT())
        let timeZoneIdentifier = timeZone!.identifier
        let timeOffset = String(timeZoneIdentifier.dropFirst(3))
        var offset = ""
        for (index, value) in timeOffset.enumerated() {
            offset.append(value)
            if timeOffset.count - index == 3 {
                offset.append(":")
            }
        }
        return offset
    }
    
    static func convert(data: Data) throws -> Parameters? {
        let jsonDic =  try JSONSerialization.jsonObject(with: data, options: .allowFragments)
        return jsonDic as? Parameters
        
    }
    
    
    static var totalScrWidthHeight: String {
        return "\(UIScreen.main.bounds.width) x \(UIScreen.main.bounds.height)"
    }
    
    static var inAppPermissionStatus: Bool {
        let permissionValue = Bundle
                              .main.object(forInfoDictionaryKey: InfoPlistConstants.PushEngageInAppEnabled) as? Bool
        return permissionValue ?? false
    }
    
    static var isLocationPrivcyEnabled: Bool {
        if let path = Bundle.main.path(forResource: "Info", ofType: "plist") {
            let dictinory = NSDictionary(contentsOfFile: path)
            let isArrayOfKeycontains = dictinory?.allKeys.compactMap { key -> String? in
                if let value = key as? String {
                    return value
                } else {
                    return nil
                }
            }.contains { (value) -> Bool in
                if value == InfoPlistConstants.loactionAllow || value == InfoPlistConstants.locationWhenInUse {
                    return true
                } else {
                    return false
                }
            }
            return isArrayOfKeycontains ?? false
        } else {
            return false
        }
    }
    
    
    static var getAppGroupInfo: String {
        if let appGroup = Bundle
                          .main.object(forInfoDictionaryKey: InfoPlistConstants.pushEngageAppGroupKey) as? String {
            return appGroup
        } else {
            return String(format: "group.%@.pushEngage", Utility.getBundleIdentifier)
        }
    }
    
    static func getFlatValue(for value: [[String: String]]) -> [String: String] {
        return value.flatMap {$0}.reduce([String: String]()) { (dict, tuple) in
            var nextDict = dict
            nextDict.updateValue(tuple.1, forKey: tuple.0)
            return nextDict
        }
    }
    
    static func update(dictionary dict: inout [AnyHashable: Any], at keys: [AnyHashable], with value: Any) {

        if keys.count < 2 {
            for key in keys { dict[key] = value }
            return
        }

        var levels: [[AnyHashable: Any]] = []

        for key in keys.dropLast() {
            if let lastLevel = levels.last {
                if let currentLevel = lastLevel[key] as? [AnyHashable: Any] {
                    levels.append(currentLevel)
                } else if lastLevel[key] != nil, levels.count + 1 != keys.count {
                    break
                } else { return }
            } else {
                if let firstLevel = dict[keys[0]] as? [AnyHashable: Any] {
                    levels.append(firstLevel )
                } else { return }
            }
        }

        if levels[levels.indices.last!][keys.last!] != nil {
            levels[levels.indices.last!][keys.last!] = value
        } else { return }

        for index in levels.indices.dropLast().reversed() {
            levels[index][keys[index + 1]] = levels[index + 1]
        }
        dict[keys[0]] = levels[0]
    }
    
    static func parse<T: Codable>(typeof: T.Type, payload: [AnyHashable: Any]) -> T? {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)
            let payLoad = try JSONDecoder().decode(typeof.self, from: jsonData)
            return payLoad
        } catch let error {
            PELogger.error(className: String(describing: Utility.self), message: error.localizedDescription)
            return nil
        }
    }
    
    static func decodeData<T: Codable>(tyeof: T.Type, data: Data) -> T? {
        do {
            let object = try JSONDecoder().decode(tyeof.self, from: data)
            return object
        } catch let error {
            PELogger.debug(className: String(describing: Utility.self), message: error.localizedDescription)
            return nil
        }
    }
    
    static func lesserThaniOS(version: String) -> Bool {
        return Self.getCurrentDeviceVersion.compare(version, options: .numeric) == .orderedAscending
    }
    
    static func greaterThanEqualToiOS(version: String) -> Bool {
        return Self.getCurrentDeviceVersion.compare(version, options: .numeric) != .orderedAscending
    }
    
    static func isPEPayload(userInfo: [AnyHashable: Any]) -> Bool {
        if let customInfo = userInfo[userInfo: PayloadConstants.custom],
           customInfo[string: PayloadConstants.tag] != nil {
            return true
        } else {
            return false
        }
    }
    
    @available(iOS 10.0, *)
    static func addButtonTo(withNotification: PENotification,
                            content: UNMutableNotificationContent) {
        
        guard let actionButtons = withNotification.actionButtons else {
            return
        }
        
        if actionButtons.count == 0 {
            return
        }
        
        var buttons = [UNNotificationAction]()
        
        for button in actionButtons {
            let action = UNNotificationAction(identifier: button.id,
                                              title: button.title,
                                              options: .foreground)
            buttons.append(action)
        }
        let buttonIds = buttons.map { $0.identifier }
        let categoryIdentifier = UUID().uuidString
        let category = UNNotificationCategory(identifier: categoryIdentifier,
                                              actions: buttons,
                                              intentIdentifiers: buttonIds,
                                              options: .customDismissAction)
        UNUserNotificationCenter.current().setNotificationCategories([category])
        content.categoryIdentifier = categoryIdentifier
    }
    
    static func isNotifiyIsDisplayable(userInfo: [AnyHashable: Any]) -> Bool {
        if isRemoteNotificationNotification(userInfo: userInfo) {
            return false
        }
        return userInfo[userInfo:
               PayloadConstants.aps]?[userInfo:
               PayloadConstants.alert] != nil
    }
    
    static func isRemoteNotificationNotification(userInfo: [AnyHashable: Any]) -> Bool {
        if userInfo[userInfo: PayloadConstants.aps]?[string: PayloadConstants.sound] != nil
            || userInfo[userInfo: PayloadConstants.custom]?[string: PayloadConstants.customSound] != nil
            || userInfo[userInfo: PayloadConstants.aps]?[string: PayloadConstants.alert] != nil
            || userInfo[userInfo: PayloadConstants.aps]?[string: PayloadConstants.badge] != nil
            || userInfo[userInfo: PayloadConstants.custom]?[string: PayloadConstants.title] != nil
            || userInfo[userInfo: PayloadConstants.custom]?[string: PayloadConstants.custombadge] != nil
            || userInfo[userInfo: PayloadConstants.custom]?[list: PayloadConstants.actionButton] != nil
            || userInfo[userInfo: PayloadConstants.custom]?[string: PayloadConstants.attachmentKey] != nil {
            return false
        }
        return true
    }
    
    @available(iOS, deprecated: 9.0)
    static func createUILocalNotification(for notification: PENotification) -> UILocalNotification {
        let uiNotification =  UILocalNotification()
        let category = UIMutableUserNotificationCategory()
        category.identifier = UUID().uuidString
        var actionArray = [UIMutableUserNotificationAction]()
        for action in notification.actionButtons ?? [] {
            let mutableAction = UIMutableUserNotificationAction()
            mutableAction.title = action.title
            mutableAction.identifier = action.id
            mutableAction.activationMode = .foreground
            mutableAction.isDestructive = false
            mutableAction.isAuthenticationRequired = false
            actionArray.append(mutableAction)
            //   iOS 8 shows notification buttons in reverse in all cases but alerts.
            //   This flips it so the frist button is on the left.
            if actionArray.count == 2 {
                category.setActions([actionArray[1], actionArray[0]], for: .minimal)
            }
        }
        category.setActions(actionArray, for: .default)
        var currentCategories = UIApplication.shared.currentUserNotificationSettings?.categories
        if currentCategories != nil {
            currentCategories?.insert(category)
        } else {
            currentCategories = Set<UIUserNotificationCategory>()
            currentCategories?.insert(category)
        }
        
        let notificationSetting = UIUserNotificationSettings(types: .init(rawValue: 7),
                                                             categories: currentCategories)
        UIApplication.shared.registerUserNotificationSettings(notificationSetting)
        uiNotification.category = category.identifier
        uiNotification.alertTitle = notification.title
        uiNotification.alertBody = notification.body
        uiNotification.userInfo = notification.rawPayload
        uiNotification.soundName = notification.sound
        if uiNotification.soundName == nil {
            uiNotification.soundName = UILocalNotificationDefaultSoundName
        }
        uiNotification.applicationIconBadgeNumber = notification.badge ?? 0
        return uiNotification
    }
    
    // for iOS 10+
    
    @available(iOS 10.0, *)
    static func createUNNotificationRequest(notification: PENotification,
                                            networkService: NetworkRouter?) -> UNNotificationRequest? {
        let content =  UNMutableNotificationContent()
        addButtonTo(withNotification: notification, content: content)
        content.title = notification.title ?? ""
        content.subtitle = notification.subtitle ?? ""
        content.body = notification.body ?? ""
        content.userInfo = notification.rawPayload
        if let sound = notification.sound {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(sound))
        } else {
            content.sound = UNNotificationSound.default
        }
        if let badge = notification.badge {
            content.badge = NSNumber(value: badge)
        }
        
        guard let unWrappednetworkService = networkService else {
            return nil
        }
        
        if let att = notification.attachmentURL, att.isEmpty == false {
            let downloadOperationQueue: DownloadOperationInput? = (att,
                                                                   content,
                                                                   unWrappednetworkService)
            let downloadOperation = DownloadAttachmentOperation(inputValue: downloadOperationQueue)
            downloadOperation.onResult = { result in
                switch result {
                case .failure(let error):
                    PELogger.error(className: String(describing: Utility.self),
                                   message: error.errorDescription ?? "")

                case .success(let message):
                    PELogger.info(className: String(describing: Utility.self),
                                  message: message)
                }
            }
            let operationQueue = OperationQueue()
            operationQueue.addOperations([downloadOperation], waitUntilFinished: true)
        }
        Utility.addButtonTo(withNotification: notification, content: content)
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.25, repeats: false)
        let identifier = "PE\(UUID().uuidString)"
        return UNNotificationRequest(identifier: identifier,
                                     content: content,
                                     trigger: trigger)
    }
    
    static func checkForDuplicateProcess(infoDict: [AnyHashable: Any], lastRecivedNotifyId: String ) -> String {
        if let currentNotifyId = infoDict[userInfo: PayloadConstants.custom]?[string: PayloadConstants.tag],
           currentNotifyId != lastRecivedNotifyId {
           return currentNotifyId
        } else {
            return PayloadConstants.duplicate
        }
    }
    
    static func urlUnWrapper(for path: String) throws -> URL {
        guard let url = URL(string: path) else {
            throw PEError.missingURL
        }
        return url
    }
    
    static func isBackgroundFetchEnable() -> Bool {
        let backgroundModeStatus = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? NSArray
        let isEnableRemoteNotification = backgroundModeStatus?.contains("remote-notification")
        return isEnableRemoteNotification ?? false
    }
    
    static var getDevice: String? {
        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            return "tablet"
        case .phone:
            return "mobile"
        case .mac:
            return "desktop"
        default:
            return nil
        }
    }
    
    static func retryCheck(error: PEError) -> RetryApi {
        
        switch error {
        case .networkError, .networkNotReachable:
            return .allow
        case .invalidStatusCode(_, let code):
            let range: ClosedRange<Int> = 500...599
            return code != nil ? range.contains(code!) == true ? .allow
                  : .denied : .denied
        default:
            return .denied
        }
    }
    
    static func loadWKWebView(with url: URL?) {
        if let link = url {
            DispatchQueue.main.async {
                let wkWebView = WKWebViewController(url: link, title: Utility.getApplicationName)
                let nav = UINavigationController(rootViewController: wkWebView)
                UIApplication.shared.windows.first?.rootViewController?.present(nav, animated: true, completion: nil)
            }
        }
    }
    
    @available(iOS 10.0, *)
    static func loadWithSafari(url: URL?) {
        guard let link = url else {
            return
        }
        DispatchQueue.main.async {
            if UIApplication.shared.canOpenURL(link) {
                UIApplication.shared.open(link) { (reponse) in
                    PELogger.info(className: String(describing: Utility.self),
                                  message: reponse.description)
                }
            }
        }
    }
    
    @available(iOS 10.0, *)
    static func isDismissEvent(response: UNNotificationResponse) -> Bool {
        return "com.apple.UNNotificationDismissActionIdentifier" == response.actionIdentifier
    }
 }
