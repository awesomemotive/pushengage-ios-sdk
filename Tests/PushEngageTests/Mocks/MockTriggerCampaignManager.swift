import Foundation
@testable import PushEngage

final class MockTriggerCampaignManager: TriggerCampaignManagerType {

    private(set) var sendTriggerEventCallCount = 0
    private(set) var lastTriggerCampaign: TriggerCampaign?
    var sendTriggerEventResult: (Bool, PEError?) = (true, nil)

    func sendTriggerEvent(trigger: TriggerCampaign,
                          completion: ((Bool, PEError?) -> Void)?) {
        sendTriggerEventCallCount += 1
        lastTriggerCampaign = trigger
        completion?(sendTriggerEventResult.0, sendTriggerEventResult.1)
    }

    private(set) var addAlertCallCount = 0
    private(set) var lastAlert: TriggerAlert?
    var addAlertResult: (Bool, PEError?) = (true, nil)

    func addAlert(triggerAlert: TriggerAlert,
                  completionHandler: ((Bool, PEError?) -> Void)?) {
        addAlertCallCount += 1
        lastAlert = triggerAlert
        completionHandler?(addAlertResult.0, addAlertResult.1)
    }
}
