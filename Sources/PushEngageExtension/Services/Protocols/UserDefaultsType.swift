//
//  UserDefaultProtocol.swift
//  PushEngage
//
//  Created by Abhishek on 19/02/21.
//

import Foundation

package protocol UserDefaultsType {
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
    var isSdkLoggingEnabled: Bool { get set }
    var environment: PEEnvironment { get set }
    var platform: String? { get set }
    var wrapperVersion: String? { get set }

    /// Subscriber-fields cache for `identify` / `logout` short-circuit semantics.
    /// Values are stringified (matches Android's `.toString()` comparison) so the
    /// cache can compare identify payloads regardless of original numeric type.
    var subscriberFields: [String: String] { get }
    var subscriberFieldsCacheTimestamp: Date? { get }
    func mergeSubscriberFields(_ fields: [String: String])
    func removeSubscriberFields(_ names: [String])
    func clearSubscriberFields()
}
