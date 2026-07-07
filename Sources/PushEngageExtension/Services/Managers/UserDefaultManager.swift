//
//  UserDefaultManager.swift
//  PushEngage
//
//  Created by Abhishek on 19/02/21.
//

import Foundation

package class UserDefaultManager: UserDefaultsType {

    private let userDefaultSharedContainer: UserDefaults?

    package init(userDefaults: UserDefaults? = .shared) {
        self.userDefaultSharedContainer = userDefaults
    }

    package var environment: PEEnvironment {
        get {
            PEEnvironment(rawValue: userDefaultSharedContainer?[.sdkEnvironment] ?? 1) ?? .production
        }
        set(value) {
            userDefaultSharedContainer?[.sdkEnvironment] = (value == .production) ? 1 : 0
        }
    }

    package var isSdkLoggingEnabled: Bool {
        get {
            userDefaultSharedContainer?[.isSdkLoggingEnabled] ?? false
        }
        set(value) {
            userDefaultSharedContainer?[.isSdkLoggingEnabled] = value
        }
    }

    package var badgeCount: Int? {
        get {
            userDefaultSharedContainer?[.badgeCount]
        }

        set (value) {
            userDefaultSharedContainer?[.badgeCount] = value
        }
    }

    package var deviceToken: String {
        get {
            userDefaultSharedContainer?[.deviceToken] ?? ""
        }

        set (value) {
            userDefaultSharedContainer?[.deviceToken] = value
        }
    }

    package var subscriberHash: String {
        get {
            userDefaultSharedContainer?[.subscriberHash] ?? ""
        }
        set(value) {
            let previous: String = userDefaultSharedContainer?[.subscriberHash] ?? ""

            if value.isEmpty && !previous.isEmpty {
                return
            }

            userDefaultSharedContainer?[.subscriberHash] = value
            if previous != value {
                clearSubscriberFields()
            }
        }
    }

    package var notificationPermissionState: PermissionStatus {
        get {
            let rawValue = userDefaultSharedContainer?[.permissionState] ?? "notYetRequested"
            return PermissionStatus(rawValue: rawValue) ?? PermissionStatus.notYetRequested
        }
        set (value) {
            userDefaultSharedContainer?[.permissionState] = value.rawValue
        }
    }

    package var appId: Int? {
        self.getObject(for: SyncAPIData.self, key: UserDefaultConstant.pushEngageSyncApi)?.siteID
    }

    package var lastSmartSubscribeDate: Date? {
        get {
            userDefaultSharedContainer?[.lastSmartSubscribeDate]
        } set (value) {
            userDefaultSharedContainer?[.lastSmartSubscribeDate] = value
        }
    }

    package var ispermissionAlerted: Bool {
        get {
            userDefaultSharedContainer?[.ispermissionAlerted] ?? false
        } set (value) {
            userDefaultSharedContainer?[.ispermissionAlerted] = value
        }
    }

    package var profileID: String? {
        get {
            userDefaultSharedContainer?[.profileID]
        } set (value) {
            userDefaultSharedContainer?[.profileID] = value
        }
    }

    package var siteStatus: String {
        self.getObject(for: SyncAPIData.self,
                             key: UserDefaultConstant.pushEngageSyncApi)?.siteStatus ?? "none"
    }

    package var siteKey: String? {
        get {
            userDefaultSharedContainer?[.siteKey]
        } set {
            userDefaultSharedContainer?[.siteKey] = newValue
        }
    }

    package var isLocationEnabled: Bool {
        self.getObject(for: SyncAPIData.self,
                              key: UserDefaultConstant.pushEngageSyncApi)?.geoLocationEnabled ?? false
    }

    package var isGDPR: Int {
        self.getObject(for: SyncAPIData.self,
                              key: UserDefaultConstant.pushEngageSyncApi)?.isEu ?? 0
    }

    package var isSubscriberDeleted: Bool {
        get {
             userDefaultSharedContainer?[.isSubscriberDeleted] ?? false
        }
        set {
            userDefaultSharedContainer?[.isSubscriberDeleted] = newValue
        }
    }

    package var isManuallyUnsubscribed: Bool {
        get {
             userDefaultSharedContainer?[.isManuallyUnsubscribed] ?? false
        }
        set {
            userDefaultSharedContainer?[.isManuallyUnsubscribed] = newValue
        }
    }

    package var isDeleteSubscriberOnDisable: Bool? {
         self.getObject(for: SyncAPIData.self,
                        key: UserDefaultConstant.pushEngageSyncApi)?
                        .isDeleteSubscriberOnDisable
    }

    package var istriedFirstTime: Bool {
        get {
            userDefaultSharedContainer?[.istriedFirstTime] ?? false
        }

        set {
            userDefaultSharedContainer?[.istriedFirstTime] = newValue
        }
    }

    package func setsponseredID(id: String) {
        userDefaultSharedContainer?[.isSponseredIdKey] = id
    }

    package var sponseredIdKey: String? {
        userDefaultSharedContainer?[.isSponseredIdKey]
    }

    package var isSwizzled: Bool {
        get {
            userDefaultSharedContainer?[.isSwizzled] ?? false
        }
        set {
            userDefaultSharedContainer?[.isSwizzled] = newValue
        }
    }

    package var platform: String? {
        get {
            userDefaultSharedContainer?[.platform]
        }
        set {
            userDefaultSharedContainer?[.platform] = newValue
        }
    }

    package var wrapperVersion: String? {
        get {
            userDefaultSharedContainer?[.wrapperVersion]
        }
        set {
            userDefaultSharedContainer?[.wrapperVersion] = newValue
        }
    }

    package var subscriberFields: [String: String] {
        guard let data = userDefaultSharedContainer?[.subscriberFieldsCache] else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    package var subscriberFieldsCacheTimestamp: Date? {
        return userDefaultSharedContainer?[.subscriberFieldsCacheTimestamp]
    }

    package func mergeSubscriberFields(_ fields: [String: String]) {
        var current = subscriberFields
        for (k, v) in fields { current[k] = v }
        writeSubscriberFields(current, timestamp: Date())
    }

    package func removeSubscriberFields(_ names: [String]) {
        var current = subscriberFields
        for n in names { current.removeValue(forKey: n) }
        writeSubscriberFields(current, timestamp: Date())
    }

    package func clearSubscriberFields() {
        userDefaultSharedContainer?[.subscriberFieldsCache] = nil
        userDefaultSharedContainer?[.subscriberFieldsCacheTimestamp] = nil
    }

    private func writeSubscriberFields(_ fields: [String: String], timestamp: Date) {
        guard let data = try? JSONEncoder().encode(fields) else { return }
        userDefaultSharedContainer?[.subscriberFieldsCache] = data
        userDefaultSharedContainer?[.subscriberFieldsCacheTimestamp] = timestamp
    }

    package func save<T: Codable>(object: T, for key: String) {
        do {
            let data = try JSONEncoder().encode(object)
            userDefaultSharedContainer?.setValue(data, forKey: key)
        } catch {
            PELogger.error(className: String(describing: UserDefaultManager.self),
                           message: PEError.parsingError.errorDescription ?? "")
        }
    }

    package func getObject<T: Codable>(for typeof: T.Type, key: String) -> T? {
        guard let data = userDefaultSharedContainer?.data(forKey: key) else {
            return nil
        }
        return Utility.decodeData(tyeof: T.self, data: data)
    }
}
