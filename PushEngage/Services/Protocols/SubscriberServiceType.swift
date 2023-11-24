//
//  NetworkDataService.swift
//  PushEngage
//
//  Created by Abhishek on 25/02/21.
//

import Foundation

typealias ServiceCallBack = (_ responseObject: Parameters?, _ error: PEError?) -> Void
typealias SubscriberBoolCallBack = (_ : Bool, _ error: PEError?) -> Void
typealias ServiceCallBackObjects<T> = (_ response: T?, _ error: PEError?) -> Void
protocol SubscriberServiceType {
    func addSubscriber(completionHandler: ServiceCallBackObjects<AddSubscriberData>?)
    func getSubscriber(for fields: [String]?, completionHandler: ServiceCallBackObjects<SubscriberDetailsData>?)
    func addSubscriberAttributes(attributes: Parameters, completionHandler: SubscriberBoolCallBack?)
    func setSubscriberAttributes(attributes: Parameters, completionHandler: SubscriberBoolCallBack?)
    func getAttribute(completionHandler: @escaping ServiceCallBack)
    func updateSubscriberStatus(status: Int, completionHandler: SubscriberBoolCallBack?)
    func addProfile(id: String, completionHandler: SubscriberBoolCallBack?)
    func deleteAttribute(with values: [String], completionHandler: SubscriberBoolCallBack?)
    func upgradeSubscription(completion: SubscriberBoolCallBack?)
    func update(segments: [String], action: SegmentActions, completionHandler: SubscriberBoolCallBack?)
    func update(dynamic segmentInfo: [Parameters], completionHandler: SubscriberBoolCallBack?)
    func segmentHashArray(for segmentId: Int, completionHandler: SubscriberBoolCallBack?)
    func updateTrigger(status: Bool, completionHandler: SubscriberBoolCallBack?)
    func checkSubscriber(completionHandler: ServiceCallBackObjects<CheckSubscriberData>?)
    func updateSubscriber(completionHandler: ServiceCallBackObjects<NetworkResponse>?)
    func syncSiteInfo(for siteKey: String, completionHandler: ServiceCallBackObjects<SyncAPIData>?)
    func retryAddSubscriberProcess(completion: ((PEError?) -> Void)?)
    func updateSettingPermission(status: PermissionStatus)
    
}

