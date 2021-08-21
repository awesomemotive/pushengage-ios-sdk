//
//  TriggerCampaignProtocol.swift
//  PushEngage
//
//  Created by Abhishek on 07/04/21.
//

import Foundation

typealias TiggerWithBoolCallBack = (_ response: Bool) -> Void

protocol  TriggerCampaignProtocol {
    func createCampaign(for tigger: TriggerCampaign, completionHandler: TiggerWithBoolCallBack?)
}
