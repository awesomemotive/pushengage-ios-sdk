import Foundation
@testable import PushEngage
@testable import PushEngageExtension
final class MockUserDefaultsService: UserDefaultsType {

    // Storage backing the property protocol
    var deviceToken: String = ""
    var subscriberHash: String = ""
    var notificationPermissionState: PermissionStatus = .notYetRequested
    private(set) var appId: Int? = nil
    var badgeCount: Int? = nil
    var lastSmartSubscribeDate: Date? = nil
    var ispermissionAlerted: Bool = false
    var profileID: String? = nil
    private(set) var siteStatus: String = SiteStatus.active.rawValue
    var siteKey: String? = nil
    private(set) var isLocationEnabled: Bool = false
    private(set) var isGDPR: Int = 0
    var isSubscriberDeleted: Bool = false
    private(set) var isDeleteSubscriberOnDisable: Bool? = nil
    var isManuallyUnsubscribed: Bool = false
    var istriedFirstTime: Bool = false
    private(set) var sponseredIdKey: String? = nil
    var isSwizzled: Bool = false
    var isSdkLoggingEnabled: Bool = false
    var environment: PEEnvironment = .production
    var platform: String? = nil
    var wrapperVersion: String? = nil

    // Subscriber-fields cache
    private(set) var subscriberFields: [String: String] = [:]
    private(set) var subscriberFieldsCacheTimestamp: Date? = nil
    private(set) var mergeSubscriberFieldsCallCount = 0
    private(set) var removeSubscriberFieldsCallCount = 0
    private(set) var clearSubscriberFieldsCallCount = 0
    /// Test-only override so tests can pin "now" relative to the TTL window.
    var nowProvider: () -> Date = { Date() }

    func mergeSubscriberFields(_ fields: [String: String]) {
        mergeSubscriberFieldsCallCount += 1
        for (k, v) in fields { subscriberFields[k] = v }
        subscriberFieldsCacheTimestamp = nowProvider()
    }

    func removeSubscriberFields(_ names: [String]) {
        removeSubscriberFieldsCallCount += 1
        for n in names { subscriberFields.removeValue(forKey: n) }
        subscriberFieldsCacheTimestamp = nowProvider()
    }

    func clearSubscriberFields() {
        clearSubscriberFieldsCallCount += 1
        subscriberFields = [:]
        subscriberFieldsCacheTimestamp = nil
    }

    func _setSubscriberFieldsCacheTimestamp(_ value: Date?) { subscriberFieldsCacheTimestamp = value }

    // Test-only setters for read-only protocol properties
    func _setAppId(_ value: Int?) { appId = value }
    func _setSiteStatus(_ value: String) { siteStatus = value }
    func _setIsLocationEnabled(_ value: Bool) { isLocationEnabled = value }
    func _setIsGDPR(_ value: Int) { isGDPR = value }
    func _setIsDeleteSubscriberOnDisable(_ value: Bool?) { isDeleteSubscriberOnDisable = value }

    // Generic codable store
    private var codableStore: [String: Any] = [:]
    private(set) var saveCallCount = 0
    private(set) var lastSaveKey: String?
    private(set) var lastSavedObject: Any?

    func save<T: Codable>(object: T, for key: String) {
        saveCallCount += 1
        lastSaveKey = key
        lastSavedObject = object
        codableStore[key] = object
    }

    func getObject<T: Codable>(for typeof: T.Type, key: String) -> T? {
        return codableStore[key] as? T
    }

    private(set) var setsponseredIDCallCount = 0
    private(set) var lastsponseredID: String?
    func setsponseredID(id: String) {
        setsponseredIDCallCount += 1
        lastsponseredID = id
        sponseredIdKey = id
    }
}
