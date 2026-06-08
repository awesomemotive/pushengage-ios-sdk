//
//  UserDefaultManager.swift
//  PushEngage
//
//  Created by Abhishek on 19/02/21.
//

import Foundation

class UserDefaultManager: UserDefaultsType {

    private let userDefaultSharedContainer: UserDefaults?

    init(userDefaults: UserDefaults? = .shared) {
        self.userDefaultSharedContainer = userDefaults
    }
    
    var environment: PEEnvironment {
        get {
            PEEnvironment(rawValue: userDefaultSharedContainer?[.sdkEnvironment] ?? 1) ?? .production
        }
        set(value) {
            userDefaultSharedContainer?[.sdkEnvironment] = (value == .production) ? 1 : 0
        }
    }
    
    var badgeCount: Int? {
        get {
            userDefaultSharedContainer?[.badgeCount]
        }
        
        set (value) {
            userDefaultSharedContainer?[.badgeCount] = value
        }
    }
    
    var deviceToken: String {
        get {
            userDefaultSharedContainer?[.deviceToken] ?? ""
        }
        
        set (value) {
            userDefaultSharedContainer?[.deviceToken] = value
        }
    }
    
    var subscriberHash: String {
        get {
            userDefaultSharedContainer?[.subscriberHash] ?? ""
        }
        set(value) {
            // When the subscriber identity changes, the identify/logout
            // cache is no longer authoritative — wipe it. Same trigger as
            // Android's `mergeSubscriberFields` clearing on hash rewrite.
            let previous: String = userDefaultSharedContainer?[.subscriberHash] ?? ""

            // Don't allow a transient parse-error path that writes "" to
            // clobber a valid subscriberHash. Treat empty-overwrite as a
            // no-op when there's a real previous value. Use `clear...` if
            // you genuinely want to forget the subscriber.
            if value.isEmpty && !previous.isEmpty {
                return
            }

            userDefaultSharedContainer?[.subscriberHash] = value
            if previous != value {
                clearSubscriberFields()
            }
        }
    }
    
    var notificationPermissionState: PermissionStatus {
        get {
            let rawValue = userDefaultSharedContainer?[.permissionState] ?? "notYetRequested"
            return PermissionStatus(rawValue: rawValue) ?? PermissionStatus.notYetRequested
        }
        set (value) {
            userDefaultSharedContainer?[.permissionState] = value.rawValue
        }
    }
    
    var appId: Int? {
        self.getObject(for: SyncAPIData.self, key: UserDefaultConstant.pushEngageSyncApi)?.siteID
    }
    
    var lastSmartSubscribeDate: Date? {
        get {
            userDefaultSharedContainer?[.lastSmartSubscribeDate]
        } set (value) {
            userDefaultSharedContainer?[.lastSmartSubscribeDate] = value
        }
    }
    
    var ispermissionAlerted: Bool {
        get {
            userDefaultSharedContainer?[.ispermissionAlerted] ?? false
        } set (value) {
            userDefaultSharedContainer?[.ispermissionAlerted] = value
        }
    }
    
    var profileID: String? {
        get {
            userDefaultSharedContainer?[.profileID]
        } set (value) {
            userDefaultSharedContainer?[.profileID] = value
        }
    }
    
    var siteStatus: String {
        self.getObject(for: SyncAPIData.self,
                             key: UserDefaultConstant.pushEngageSyncApi)?.siteStatus ?? "none"
    }
    
    var siteKey: String? {
        get {
            userDefaultSharedContainer?[.siteKey]
        } set {
            userDefaultSharedContainer?[.siteKey] = newValue
        }
    }
    
    var isLocationEnabled: Bool {
        self.getObject(for: SyncAPIData.self,
                              key: UserDefaultConstant.pushEngageSyncApi)?.geoLocationEnabled ?? false
    }
    
    var isGDPR: Int {
        self.getObject(for: SyncAPIData.self,
                              key: UserDefaultConstant.pushEngageSyncApi)?.isEu ?? 0
    }
    
        var isSubscriberDeleted: Bool {
        get {
             userDefaultSharedContainer?[.isSubscriberDeleted] ?? false
        }
        set {
            userDefaultSharedContainer?[.isSubscriberDeleted] = newValue
        }
    }

    var isManuallyUnsubscribed: Bool {
        get {
             userDefaultSharedContainer?[.isManuallyUnsubscribed] ?? false
        }
        set {
            userDefaultSharedContainer?[.isManuallyUnsubscribed] = newValue
        }
    }

    var isDeleteSubscriberOnDisable: Bool? {
         self.getObject(for: SyncAPIData.self,
                        key: UserDefaultConstant.pushEngageSyncApi)?
                        .isDeleteSubscriberOnDisable
    }
    
    var istriedFirstTime: Bool {
        get {
            userDefaultSharedContainer?[.istriedFirstTime] ?? false
        }
        
        set {
            userDefaultSharedContainer?[.istriedFirstTime] = newValue
        }
    }
    
    func setsponseredID(id: String) {
        userDefaultSharedContainer?[.isSponseredIdKey] = id
    }
    
    var sponseredIdKey: String? {
        userDefaultSharedContainer?[.isSponseredIdKey]
    }
    
    var isSwizzled: Bool {
        get {
            userDefaultSharedContainer?[.isSwizzled] ?? false
        }
        set {
            userDefaultSharedContainer?[.isSwizzled] = newValue
        }
    }

    var platform: String? {
        get {
            userDefaultSharedContainer?[.platform]
        }
        set {
            userDefaultSharedContainer?[.platform] = newValue
        }
    }

    var wrapperVersion: String? {
        get {
            userDefaultSharedContainer?[.wrapperVersion]
        }
        set {
            userDefaultSharedContainer?[.wrapperVersion] = newValue
        }
    }

    var subscriberFields: [String: String] {
        guard let data = userDefaultSharedContainer?[.subscriberFieldsCache] else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    var subscriberFieldsCacheTimestamp: Date? {
        return userDefaultSharedContainer?[.subscriberFieldsCacheTimestamp]
    }

    func mergeSubscriberFields(_ fields: [String: String]) {
        var current = subscriberFields
        for (k, v) in fields { current[k] = v }
        writeSubscriberFields(current, timestamp: Date())
    }

    func removeSubscriberFields(_ names: [String]) {
        var current = subscriberFields
        for n in names { current.removeValue(forKey: n) }
        writeSubscriberFields(current, timestamp: Date())
    }

    func clearSubscriberFields() {
        userDefaultSharedContainer?[.subscriberFieldsCache] = nil
        userDefaultSharedContainer?[.subscriberFieldsCacheTimestamp] = nil
    }

    private func writeSubscriberFields(_ fields: [String: String], timestamp: Date) {
        guard let data = try? JSONEncoder().encode(fields) else { return }
        userDefaultSharedContainer?[.subscriberFieldsCache] = data
        userDefaultSharedContainer?[.subscriberFieldsCacheTimestamp] = timestamp
    }
    
    func save<T: Codable>(object: T, for key: String) {
        do {
            let data = try JSONEncoder().encode(object)
            userDefaultSharedContainer?.setValue(data, forKey: key)
        } catch {
            PELogger.error(className: String(describing: UserDefaultManager.self),
                           message: PEError.parsingError.errorDescription ?? "")
        }
    }
    
    func getObject<T: Codable>(for typeof: T.Type, key: String) -> T? {
        guard let data = userDefaultSharedContainer?.data(forKey: key) else {
            return nil
        }
        return Utility.decodeData(tyeof: T.self, data: data)
    }
}
