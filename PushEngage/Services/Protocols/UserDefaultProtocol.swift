//
//  UserDefaultProtocol.swift
//  PushEngage
//
//  Created by Abhishek on 19/02/21.
//

import Foundation

protocol UserDefaultProtocol {
    
    var deviceToken: String { get set }
    var subscriberHash: String { get set }
    var notificationPermissionState: PermissonStatus { get set }
    var appId: Int? { get }
    var badgeCount: Int? { get set }
    var lastSmartSubscribeDate: Date? { get set }
    func save<T: Codable>(object: T, for key: String)
    func getObject<T: Codable>(for typeof: T.Type, key: String) -> T?
    var ispermissionAlerted: Bool { get set }
    var profileID: String? { get set }
    var siteStatus: String { get }
    var siteKey: String? { get set }
    var isLocationEnabled: Bool { get }
    var isGDPR: Int { get }
    var isSubscriberDeleted: Bool { get set }
    var isDeleteSubscriberOnDisable: Bool? { get }
    var istriedFirstTime: Bool { get set }
    var sponseredIdKey: String? { get }
    var isSwizziled: Bool { get set }
    func setsponseredID(id: String)
}
