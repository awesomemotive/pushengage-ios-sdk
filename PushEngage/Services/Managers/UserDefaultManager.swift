//
//  UserDefaultManager.swift
//  PushEngage
//
//  Created by Abhishek on 19/02/21.
//

import Foundation


class  UserDefaultManager: UserDefaultProtocol {
    
    private let userDefaultSharedContainer: UserDefaults = .shared
    
    var badgeCount: Int? {
        get {
            userDefaultSharedContainer[.badgeCount]
        }
        
        set (value) {
            userDefaultSharedContainer[.badgeCount] = value
        }
    }
    
    var deviceToken: String {
        get {
            userDefaultSharedContainer[.deviceToken] ?? ""
        }
        
        set (value) {
            userDefaultSharedContainer[.deviceToken] = value
        }
    }
    
    var subscriberHash: String {
        get {
            userDefaultSharedContainer[.subscriberHash] ?? ""
        }
        
        set(value) {
            userDefaultSharedContainer[.subscriberHash] = value
        }
    }
    
    var notificationPermissionState: PermissonStatus {
        get {
            let rawValue = userDefaultSharedContainer[.permissionState] ?? "notYetRequested"
            return PermissonStatus(rawValue: rawValue) ?? PermissonStatus.notYetRequested
        }
        
        set (value) {
            userDefaultSharedContainer[.permissionState] = value.rawValue
        }
    }
    
    var appId: Int? {
        self.getObject(for: SyncAPIData.self, key: UserDefaultConstant.pushEngageSyncApi)?.siteID
    }
    
    var lastSmartSubscribeDate: Date? {
        get {
            userDefaultSharedContainer[.lastSmartSubscribeDate]
        } set (value) {
            userDefaultSharedContainer[.lastSmartSubscribeDate] = value
        }
    }
    
    var ispermissionAlerted: Bool {
        get {
            userDefaultSharedContainer[.ispermissionAlerted] ?? false
        } set (value) {
            userDefaultSharedContainer[.ispermissionAlerted] = value
        }
    }
    
    var profileID: String? {
        get {
            userDefaultSharedContainer[.profileID]
        } set (value) {
            userDefaultSharedContainer[.profileID] = value
        }
    }
    
    var siteStatus: String {
        self.getObject(for: SyncAPIData.self,
                             key: UserDefaultConstant.pushEngageSyncApi)?.siteStatus ?? "none"
    }
    
    var siteKey: String? {
        get {
            userDefaultSharedContainer[.siteKey]
        } set {
            userDefaultSharedContainer[.siteKey] = newValue
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
             userDefaultSharedContainer[.isSubscriberDeleted] ?? false
        }
        
        set {
            userDefaultSharedContainer[.isSubscriberDeleted] = newValue
        }
    }
    
    var isDeleteSubscriberOnDisable: Bool? {
         self.getObject(for: SyncAPIData.self,
                        key: UserDefaultConstant.pushEngageSyncApi)?
                        .isDeleteSubscriberOnDisable
    }
    
    var istriedFirstTime: Bool {
        get {
            userDefaultSharedContainer[.istriedFirstTime] ?? false
        }
        
        set {
            userDefaultSharedContainer[.istriedFirstTime] = newValue
        }
    }
    
    
    func setsponseredID(id: String) {
        userDefaultSharedContainer[.isSponseredIdKey] = id
    }
    
    var sponseredIdKey: String? {
        userDefaultSharedContainer[.isSponseredIdKey]
    }
    
    var isSwizziled: Bool {
        
        get {
            userDefaultSharedContainer[.isSwizzled] ?? false
        }
        
        set {
            userDefaultSharedContainer[.isSwizzled] = newValue
        }
    }
    
    func save<T: Codable>(object: T, for key: String) {
        do {
            let data = try JSONEncoder().encode(object)
            userDefaultSharedContainer.setValue(data, forKey: key)
        } catch {
            PELogger.error(className: String(describing: UserDefaultManager.self),
                           message: PEError.parsingError.errorDescription ?? "")
        }
    }
    
    func getObject<T: Codable>(for typeof: T.Type, key: String) -> T? {
        guard let data = userDefaultSharedContainer.data(forKey: key) else {
            return nil
        }
        return Utility.decodeData(tyeof: T.self, data: data)
    }
}
