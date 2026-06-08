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
    
    static var timeZone: String {
        let identifier = TimeZone.current.identifier
        return identifier
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
    
    static var autoHandleDeeplinkURL: Bool {
        let autoHandleEnabled = Bundle.main.object(forInfoDictionaryKey: InfoPlistConstants.pushEngageAutoHandleDeeplinkUrl) as? Bool
        return autoHandleEnabled ?? false
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
            return ""
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
    
    @available(iOS 10.0, *)
    static func createUNNotificationRequest(notification: PENotification,
                                            networkService: NetworkRouterType?) -> UNNotificationRequest? {
        let content =  UNMutableNotificationContent()
        addButtonTo(withNotification: notification, content: content)
        content.title = notification.title ?? ""
        content.subtitle = notification.subtitle ?? ""
        content.body = notification.body ?? ""
        content.userInfo = notification.rawPayload
        if let threadId = notification.threadId {
            content.threadIdentifier = threadId
        }
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
    
    /// Composes the SDK User-Agent in the slash-delimited shape:
    ///   iOS/<osVer>/<deviceModel>/<bundleId>/<appVer>/SDK/<sdkVer>/<flavor>[/<wrapperVer>]
    /// The trailing wrapper-version slot is omitted when no wrapper plugin has
    /// registered its version, so segment count signals native vs wrapped.
    /// Mirrors the Android counterpart in `RestClient.buildUserAgent`.
    static func buildUserAgent(userDefaults: UserDefaultsType) -> String {
        let osVer       = sanitizeUaSegment(getCurrentDeviceVersion)
        let deviceModel = sanitizeUaSegment(getHardwareIdentifier)
        let bundleId    = sanitizeUaSegment(Bundle.main.bundleIdentifier)
        let appVer      = sanitizeUaSegment(getAppShortVersion)
        let sdkVer      = sanitizeUaSegment(NetworkConstants.sdkVersion)
        let flavor      = sanitizeUaSegment(userDefaults.platform, default: PEPlatform.iOS)
        let wrapperVer  = sanitizeUaSegment(userDefaults.wrapperVersion)

        var ua = "iOS/\(osVer)/\(deviceModel)/\(bundleId)/\(appVer)/SDK/\(sdkVer)/\(flavor)"
        if !wrapperVer.isEmpty {
            ua += "/\(wrapperVer)"
        }
        return ua
    }

    /// Hardware identifier (e.g. "iPhone15,3", "iPad14,1") used in the
    /// SDK User-Agent's device-model slot. Reads `SIMULATOR_MODEL_IDENTIFIER`
    /// when running under the iOS Simulator so the value reflects the simulated
    /// device rather than the host CPU arch; falls back to `utsname.machine`
    /// on real devices.
    static var getHardwareIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"],
           !simulated.isEmpty {
            return simulated
        }
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce(into: "") { partial, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            partial.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier
    }

    /// `CFBundleShortVersionString` from the host app's Info.plist (no build
    /// suffix), used in the SDK User-Agent's app-version slot. Returns an
    /// empty string when the key is absent (test bundles, framework targets).
    static var getAppShortVersion: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// Sanitizes a single segment of the SDK User-Agent. Allowlists the RFC 7230
    /// `tchar` set (alphanumerics plus ``!#$%&'*+-.^_`|~``) and replaces every
    /// other character with `_`. Falls back to `fallback` when the input is nil
    /// or empty. The allowlist approach is intentional: `platform` and
    /// `wrapperVersion` are free-string user input from wrapper SDKs, so a
    /// denylist would inevitably miss something the wire format can't carry
    /// (`/` segment delimiter, CR/LF header injection, `;` parameter delimiter,
    /// `,` list delimiter, `"`/`(`/`)` quoted-string structure, etc.).
    static func sanitizeUaSegment(_ raw: String?, default fallback: String = "") -> String {
        guard let raw, !raw.isEmpty else { return fallback }
        var out = String.UnicodeScalarView()
        out.reserveCapacity(raw.unicodeScalars.count)
        for scalar in raw.unicodeScalars {
            if isTchar(scalar) {
                out.append(scalar)
            } else {
                out.append(UnicodeScalar(0x5F))
            }
        }
        return String(out)
    }

    /// RFC 7230 `tchar` predicate — the character set that may appear unquoted
    /// in HTTP header tokens.
    private static func isTchar(_ scalar: UnicodeScalar) -> Bool {
        let v = scalar.value
        // ALPHA / DIGIT
        if (0x30...0x39).contains(v) { return true } // 0-9
        if (0x41...0x5A).contains(v) { return true } // A-Z
        if (0x61...0x7A).contains(v) { return true } // a-z
        // tchar marks: !#$%&'*+-.^_`|~
        switch v {
        case 0x21, 0x23, 0x24, 0x25, 0x26, 0x27,
             0x2A, 0x2B, 0x2D, 0x2E,
             0x5E, 0x5F, 0x60, 0x7C, 0x7E:
            return true
        default:
            return false
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
    
    /// Returns the current key window using the modern scene-based lookup on iOS 13+,
    /// falling back to the deprecated `windows.first` on iOS 12. Returns `nil` inside
    /// app extensions since `UIApplication.shared` is unavailable there.
    static var keyWindow: UIWindow? {
        #if !APPLICATION_EXTENSION_API_ONLY
        if #available(iOS 13.0, *) {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        } else {
            return UIApplication.shared.windows.first
        }
        #else
        return nil
        #endif
    }

    static func loadWKWebView(with url: URL?) {
        if let link = url {
            DispatchQueue.main.async {
                let wkWebView = WKWebViewController(url: link, title: Utility.getApplicationName)
                let nav = UINavigationController(rootViewController: wkWebView)
                keyWindow?.rootViewController?.present(nav, animated: true, completion: nil)
            }
        }
    }
    
    @available(iOS 10.0, *)
    static func loadWithSafari(url: URL?) {
        guard let link = url else {
            return
        }
        DispatchQueue.main.async {
            #if !APPLICATION_EXTENSION_API_ONLY
            if UIApplication.shared.canOpenURL(link) {
                UIApplication.shared.open(link) { (reponse) in
                    PELogger.info(className: String(describing: Utility.self),
                                  message: reponse.description)
                }
            }
            #endif
        }
    }
    
    @available(iOS 10.0, *)
    static func isDismissEvent(response: UNNotificationResponse) -> Bool {
        return "com.apple.UNNotificationDismissActionIdentifier" == response.actionIdentifier
    }
 }
