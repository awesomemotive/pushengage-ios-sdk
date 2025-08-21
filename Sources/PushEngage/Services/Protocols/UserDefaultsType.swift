//
//  UserDefaultProtocol.swift
//  PushEngage
//
//  Created by Abhishek on 19/02/21.
//

import Foundation

protocol UserDefaultsType {
    func save<T: Codable>(object: T, for key: String)
    func getObject<T: Codable>(for typeof: T.Type, key: String) -> T?
    func setsponseredID(id: String)
    var deviceToken: String { get set }
    var subscriberHash: String { get set }
    var notificationPermissionState: PermissionStatus { get set }
    var appId: Int? { get }
    var badgeCount: Int? { get set }
    var lastSmartSubscribeDate: Date? { get set }
    var ispermissionAlerted: Bool { get set }
    var profileID: String? { get set }
    var siteStatus: String { get }
    var siteKey: String? { get set }
    var isLocationEnabled: Bool { get }
    var isGDPR: Int { get }
    var isSubscriberDeleted: Bool { get set }
    var isDeleteSubscriberOnDisable: Bool? { get }
    var isManuallyUnsubscribed: Bool { get set }
    var istriedFirstTime: Bool { get set }
    var sponseredIdKey: String? { get }
    var isSwizzled: Bool { get set }
    var environment: PEEnvironment { get set }
}
