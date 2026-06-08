import Foundation
@testable import PushEngage

final class MockSubscriberService: SubscriberServiceType {

    // MARK: - addSubscriber
    private(set) var addSubscriberCallCount = 0
    var addSubscriberResult: (AddSubscriberData?, PEError?) = (nil, nil)
    func addSubscriber(completionHandler: ServiceCallBackObjects<AddSubscriberData>?) {
        addSubscriberCallCount += 1
        completionHandler?(addSubscriberResult.0, addSubscriberResult.1)
    }

    // MARK: - getSubscriber
    private(set) var getSubscriberCallCount = 0
    private(set) var lastGetSubscriberFields: [String]?
    var getSubscriberResult: (SubscriberDetailsData?, PEError?) = (nil, nil)
    func getSubscriber(for fields: [String]?, completionHandler: ServiceCallBackObjects<SubscriberDetailsData>?) {
        getSubscriberCallCount += 1
        lastGetSubscriberFields = fields
        completionHandler?(getSubscriberResult.0, getSubscriberResult.1)
    }

    // MARK: - addSubscriberAttributes
    private(set) var addSubscriberAttributesCallCount = 0
    private(set) var lastAddAttributes: Parameters?
    var addSubscriberAttributesResult: (Bool, PEError?) = (true, nil)
    func addSubscriberAttributes(attributes: Parameters, completionHandler: SubscriberBoolCallBack?) {
        addSubscriberAttributesCallCount += 1
        lastAddAttributes = attributes
        completionHandler?(addSubscriberAttributesResult.0, addSubscriberAttributesResult.1)
    }

    // MARK: - setSubscriberAttributes
    private(set) var setSubscriberAttributesCallCount = 0
    private(set) var lastSetAttributes: Parameters?
    var setSubscriberAttributesResult: (Bool, PEError?) = (true, nil)
    func setSubscriberAttributes(attributes: Parameters, completionHandler: SubscriberBoolCallBack?) {
        setSubscriberAttributesCallCount += 1
        lastSetAttributes = attributes
        completionHandler?(setSubscriberAttributesResult.0, setSubscriberAttributesResult.1)
    }

    // MARK: - getAttribute
    private(set) var getAttributeCallCount = 0
    var getAttributeResult: (Parameters?, PEError?) = (nil, nil)
    func getAttribute(completionHandler: @escaping ServiceCallBack) {
        getAttributeCallCount += 1
        completionHandler(getAttributeResult.0, getAttributeResult.1)
    }

    // MARK: - updateSubscriberStatus
    private(set) var updateSubscriberStatusCallCount = 0
    private(set) var lastUpdateStatus: Int?
    var updateSubscriberStatusResult: (Bool, PEError?) = (true, nil)
    func updateSubscriberStatus(status: Int, completionHandler: SubscriberBoolCallBack?) {
        updateSubscriberStatusCallCount += 1
        lastUpdateStatus = status
        completionHandler?(updateSubscriberStatusResult.0, updateSubscriberStatusResult.1)
    }

    // MARK: - addProfile
    private(set) var addProfileCallCount = 0
    private(set) var lastAddProfileId: String?
    var addProfileResult: (Bool, PEError?) = (true, nil)
    func addProfile(id: String, completionHandler: SubscriberBoolCallBack?) {
        addProfileCallCount += 1
        lastAddProfileId = id
        completionHandler?(addProfileResult.0, addProfileResult.1)
    }

    // MARK: - deleteAttribute
    private(set) var deleteAttributeCallCount = 0
    private(set) var lastDeleteAttributeValues: [String]?
    var deleteAttributeResult: (Bool, PEError?) = (true, nil)
    func deleteAttribute(with values: [String], completionHandler: SubscriberBoolCallBack?) {
        deleteAttributeCallCount += 1
        lastDeleteAttributeValues = values
        completionHandler?(deleteAttributeResult.0, deleteAttributeResult.1)
    }

    // MARK: - upgradeSubscription
    private(set) var upgradeSubscriptionCallCount = 0
    var upgradeSubscriptionResult: (Bool, PEError?) = (true, nil)
    func upgradeSubscription(completion: SubscriberBoolCallBack?) {
        upgradeSubscriptionCallCount += 1
        completion?(upgradeSubscriptionResult.0, upgradeSubscriptionResult.1)
    }

    // MARK: - update(segments:action:)
    private(set) var updateSegmentsCallCount = 0
    private(set) var lastUpdateSegments: [String]?
    private(set) var lastUpdateSegmentAction: SegmentActions?
    var updateSegmentsResult: (Bool, PEError?) = (true, nil)
    func update(segments: [String], action: SegmentActions, completionHandler: SubscriberBoolCallBack?) {
        updateSegmentsCallCount += 1
        lastUpdateSegments = segments
        lastUpdateSegmentAction = action
        completionHandler?(updateSegmentsResult.0, updateSegmentsResult.1)
    }

    // MARK: - update(dynamic:)
    private(set) var updateDynamicCallCount = 0
    private(set) var lastDynamicSegments: [Parameters]?
    var updateDynamicResult: (Bool, PEError?) = (true, nil)
    func update(dynamic segmentInfo: [Parameters], completionHandler: SubscriberBoolCallBack?) {
        updateDynamicCallCount += 1
        lastDynamicSegments = segmentInfo
        completionHandler?(updateDynamicResult.0, updateDynamicResult.1)
    }

    // MARK: - segmentHashArray
    private(set) var segmentHashArrayCallCount = 0
    private(set) var lastSegmentId: Int?
    var segmentHashArrayResult: (Bool, PEError?) = (true, nil)
    func segmentHashArray(for segmentId: Int, completionHandler: SubscriberBoolCallBack?) {
        segmentHashArrayCallCount += 1
        lastSegmentId = segmentId
        completionHandler?(segmentHashArrayResult.0, segmentHashArrayResult.1)
    }

    // MARK: - automatedNotification
    private(set) var automatedNotificationCallCount = 0
    private(set) var lastAutomatedStatus: TriggerStatusType?
    var automatedNotificationResult: (Bool, PEError?) = (true, nil)
    func automatedNotification(status: TriggerStatusType, completionHandler: SubscriberBoolCallBack?) {
        automatedNotificationCallCount += 1
        lastAutomatedStatus = status
        completionHandler?(automatedNotificationResult.0, automatedNotificationResult.1)
    }

    // MARK: - checkSubscriber
    private(set) var checkSubscriberCallCount = 0
    var checkSubscriberResult: (CheckSubscriberData?, PEError?) = (nil, nil)
    func checkSubscriber(completionHandler: ServiceCallBackObjects<CheckSubscriberData>?) {
        checkSubscriberCallCount += 1
        completionHandler?(checkSubscriberResult.0, checkSubscriberResult.1)
    }

    // MARK: - updateSubscriber
    private(set) var updateSubscriberCallCount = 0
    var updateSubscriberResult: (NetworkResponse?, PEError?) = (nil, nil)
    func updateSubscriber(completionHandler: ServiceCallBackObjects<NetworkResponse>?) {
        updateSubscriberCallCount += 1
        completionHandler?(updateSubscriberResult.0, updateSubscriberResult.1)
    }

    // MARK: - syncSiteInfo
    private(set) var syncSiteInfoCallCount = 0
    private(set) var lastSyncSiteKey: String?
    var syncSiteInfoResult: (SyncAPIData?, PEError?) = (nil, nil)
    func syncSiteInfo(for siteKey: String, completionHandler: ServiceCallBackObjects<SyncAPIData>?) {
        syncSiteInfoCallCount += 1
        lastSyncSiteKey = siteKey
        completionHandler?(syncSiteInfoResult.0, syncSiteInfoResult.1)
    }

    // MARK: - retryAddSubscriberProcess
    private(set) var retryAddSubscriberCallCount = 0
    var retryAddSubscriberError: PEError? = nil
    func retryAddSubscriberProcess(completion: ((PEError?) -> Void)?) {
        retryAddSubscriberCallCount += 1
        completion?(retryAddSubscriberError)
    }

    // MARK: - updateSettingPermission
    private(set) var updateSettingPermissionCallCount = 0
    private(set) var lastSettingPermissionStatus: PermissionStatus?
    func updateSettingPermission(status: PermissionStatus) {
        updateSettingPermissionCallCount += 1
        lastSettingPermissionStatus = status
    }

    // MARK: - trackEvent
    private(set) var trackEventCallCount = 0
    private(set) var lastTrackEventRequest: TrackEventRequest?
    var trackEventResult: (Bool, PEError?) = (true, nil)
    func trackEvent(request: TrackEventRequest,
                    completionHandler: ((Bool, PEError?) -> Void)?) {
        trackEventCallCount += 1
        lastTrackEventRequest = request
        completionHandler?(trackEventResult.0, trackEventResult.1)
    }

    // MARK: - sendGoal
    private(set) var sendGoalCallCount = 0
    private(set) var lastGoal: Goal?
    var sendGoalResult: (Bool, PEError?) = (true, nil)
    func sendGoal(goal: Goal, completionHandler: ((Bool, PEError?) -> Void)?) {
        sendGoalCallCount += 1
        lastGoal = goal
        completionHandler?(sendGoalResult.0, sendGoalResult.1)
    }
}
