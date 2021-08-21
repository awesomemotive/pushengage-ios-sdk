//
//  SyncAPI.swift
//  PushEngage
//
//  Created by Abhishek on 16/06/21.
//

import Foundation

// MARK: - SyncAPIResponse
struct SyncAPIResponse: Codable {
    var errorCode: Int?
    var data: SyncAPIData?
    var errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case data = "data"
        case errorMessage = "error_message"
    }
}

// MARK: - SyncAPIData
struct SyncAPIData: Codable {
    var siteID: Int?
    var siteKey, siteStatus, siteName, siteSubdomain: String?
    var isEu: Int?
    var geoLocationEnabled: Bool?
    var api: SyncAPI?
    var isDeleteSubscriberOnDisable: Bool?

    enum CodingKeys: String, CodingKey {
        case siteID = "site_id"
        case siteKey = "site_key"
        case siteStatus = "site_status"
        case siteName = "site_name"
        case siteSubdomain = "site_subdomain"
        case isEu = "is_eu"
        case geoLocationEnabled = "geo_fetch"
        case api = "api"
        case isDeleteSubscriberOnDisable = "delete_on_notification_disable"
    }
}

// MARK: - SyncAPI
struct SyncAPI: Codable {
    var analytics, log, backend, trigger, optin: String?
    var backendCloud: String?
    
    enum CodingKeys: String, CodingKey {
        case backendCloud = "backend_cdn"
    }
}
