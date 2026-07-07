//
//  Postback.swift
//  PushEngage
//
//  Created by Abhishek on 25/03/21.
//

import Foundation

// MARK: - SponsoredPush

package struct SponsoredPush: Codable {
    package var tag: String?
    var postback: AnyCodable?
}

// struct Postback: Codable {
//    var isSponsored: Int?
//    var network, publisher, siteSubdomain: String?
//    var siteURL: String?
//    var deviceType, device, tid: String?
//    var siteID: Int?
//    var country, city, ipAddress, userAgent: String?
//
//    enum CodingKeys: String, CodingKey {
//        case isSponsored = "is_sponsored"
//        case network, publisher
//        case siteSubdomain = "site_subdomain"
//        case siteURL = "site_url"
//        case deviceType = "device_type"
//        case device, tid
//        case siteID = "site_id"
//        case country, city
//        case ipAddress = "ip_address"
//        case userAgent = "user_agent"
//    }
// }

// MARK: - SponsoredResponse
struct SponsoredResponse: Codable {
    package var errorCode: Int?
    package var data: SponsoredData?
    package var errorMessage: String?
    package var error: NetworkError?

    enum CodingKeys: String, CodingKey {
        case errorCode = "error_code"
        case data = "data"
        case errorMessage = "error_message"
        case error
    }
}

// MARK: - SponsoredData
package struct SponsoredData: Codable {
    package var title: String?
    var body: String?
    var icon: String?
    package var tag: String?
    var launchURL: String?
    var sponseredActionButton: [SButton]?

    enum CodingKeys: String, CodingKey {
        case title = "t"
        case body = "b"
        case icon =  "att"
        case tag = "tag"
        case launchURL = "u"
        case sponseredActionButton = "ab"
    }
}

extension SponsoredData {
    struct SButton: Codable {
        var slabel: String?

        enum CodingKeys: String, CodingKey {
            case slabel = "b"
        }
    }
}

// MARK: - Options
struct Options: Codable {
    var body: String
    var icon: String
    package var tag: String
    package var data: String
    var requireInteraction: Bool
}
