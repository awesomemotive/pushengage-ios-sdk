//
//  TriggerCampaignManagerType.swift
//  PushEngage
//
//  Created by Abhishek on 07/04/21.
//

import Foundation
import PushEngageExtension

typealias TriggerWithBoolCallBack = (_ response: Bool) -> Void

protocol TriggerCampaignManagerType {
    func sendTriggerEvent(trigger: TriggerCampaign, completion: ((_ response: Bool,
                                                                  _ error: PEError?) -> Void)?)
    func addAlert(triggerAlert: TriggerAlert, completionHandler: ((_ response: Bool,
                                                                   _ error: PEError?) -> Void)?)
}
