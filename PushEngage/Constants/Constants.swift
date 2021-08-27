//
//  Constants.swift
//  PushEngage
//
//  Created by Abhishek on 17/02/21.
//

internal struct NetworkConstants {
    // MARK: - Request Timeout
    static let requestTimeout = 60.0
    static let responseTimeOut = 40.0

    static let accessTokenExpired: Int = 401

    // MARK: - API Parameters
    // MARK: - Keys
    static let requestParameterModeKey = "mode"
    static let requestParameterFormatKey = "format"
    
    // MARK: - Values
    static let requestParameterFormatValue = "json"

    // MARK: - API Headers
    // MARK: - Keys
    static let requestHeaderContentTypeKey = "Content-Type"
    static let requestHeaderAuthorizationKey = "Authorization"
    static let requestHeaderRefererKey = "referer"

    // MARK: - Values
    static let requestHeaderAuthorizationValue = "Bearer "
    static let requestHeaderContentTypeValue = "application/json"
    static let requestHeaderContentTypeValueForcharSet = "application/x-www-form-urlencoded; charset=utf-8"
    static let requestHeaderRefererValue = "https://pushengage.com/service-worker.js"

    // MARK: - BASE URL
    
    static let baseURL = PENetworkURLs.backendBaseURL
    
    static var notifAnalyticURL = PENetworkURLs.notifyAnalyticsBaseURL
    
    static let triggerCampaignBaseURL = PENetworkURLs.triggerBaseURL
    
    static let errorLoggingBaseURL = PENetworkURLs.loggingBaseURL
    
    static let cdnurl = PENetworkURLs.backendCdnBaseURL
    
    // MARK: - SDK version
    
    static let sdkVersion = "0.0.1"

    // MARK: - URL relative - path
    static let addSubscriberPath = "subscriber/add"
    static let getHashPath = "subscriber/%@/"
    static let checkSubscriberHash = "subscriber/check/%@"
    static let subscriberAttribute = "subscriber/%@/attributes"
    static let getSubscriberAttribute = "subscriber/%@/attributes"
    static let updateSubscriberStatus = "subscriber/updatesubscriberstatus"
    static let addProfileId = "subscriber/profile-id/add"
    static let upgarde = "subscriber/upgrade"
    static let timeZone = "subscriber/timezone/add"
    static let addSegment = "subscriber/segments/add"
    static let removeSegment = "subscriber/segments/remove"
    static let dynamicAddSegment = "subscriber/dynamicSegments/add"
    static let segmentHashArray = "subscriber/segments/segmentHashArray"
    static let dynamicRemoveSegment = "subscriber/dynamicSegments/remove"
    static let updateTrigger = "subscriber/updatetriggerstatus"
    static let updateSubscriber = "subscriber/%@"
    static let syncSubscriber = "sites/%@/sync/ios"
    
    // MARK: - Notification relative path
    static let notificationView = "notification/view"
    static let notificationClicked = "notification/click"
    static let sponsoreFetch = "notification/fetch"
    
    // MARK: - Error logging relative path
    static let logs = "logs"
    
    // MARK: - HTTPS
    static let https = "https://"
    static let http = "http://"
}

struct PayloadConstants {
    
    static let attachmentKey = "att"
    static let launchUrlKey = "u"
    static let custom = "pe"
    static let deeplinking = "dl"
    static let actionSelected = "actionSelected"
    static let additionalData = "ad"
    static let tag = "tag"
    static let duplicate = "duplicate"
    static let title = "t"
    static let aps = "aps"
    static let alert = "alert"
    static let sound = "sound"
    static let badge = "badge"
    static let custombadge = "ba"
    static let customSound = "s"
    static let actionButton = "ab"
    static let customsubtitle = "sb"
    static let customBody = "b"
}

struct  InfoPlistConstants {
    static let PushEngageInAppEnabled = "PushEngageInAppEnabled"
    static let locationWhenInUse = "NSLocationAlwaysAndWhenInUseUsageDescription"
    static let loactionAllow = "NSLocationWhenInUseUsageDescription"
    static let pushEngageAppGroupKey = "PushEngage_App_Group_Key"
}

struct UserDefaultConstant {
    
    static let deviceToken = "deviceToken"
    static let subscriberHash = "subscriberHash"
    static let permissionState = "notitficationPermission"
    static let appId = "AppId"
    static let country = "country"
    static let state = "state"
    static let city = "city"
    static let notificationId = "notificationId"
    static let badgeCount = "badgeCount"
    static let lastSmartSubscribeDate = "lastSmartSubscribeDate"
    static let appIsStarting = "appIsStarting"
    static let pushEngageSyncApi = "pushengageSyncApi"
    static let ispermissionAlertedKey = "ispermissionAlerted"
    static let profileId = "pe_host_profile_id"
    static let siteStatus = "pe_host_site_status"
    static let siteKey = "pe_site_key"
    static let locationCoordinates = "location_coordinates"
    static let isSubscriberDeleted = "is_subscriber_deleted"
    static let istriedFirstTime = "istriedFirstTime"
    static let sponsered = "pesponser"
    static let isSwizziled = "is_swizziled"
    
}

// MARK: - Query parms key

extension String {
    static let swvKey = "swv"
    static let isEuKey = "is_eu"
    static let geoFetch = "geo_fetch"
}

// MARK: - Parsing Constants

struct ParsingConstants {
    static let data = "data"
}

// MARK: - PEErrorMessages

  extension String {
   
    static let contentNotFound = "Content not found"
    static let network = "Network faliure"
    static let downloadAttachmentfailed = "Failed to download attachment"
    static let parametersNil = "Parameters were nil."
    static let encodingFailed = "Parameter encoding failed"
    static let missingURL = "URL is not available."
    static let parsingError = "Error in parsing file"
    static let invalidStatusCode = "Invalid status code:- %@"
    static let dataEncodeingFailed = "Failed data encoding"
    static let networkNotReachable = "Network reachablity Error"
    static let canceled = "Canceled the operation in operationQueue"
    static let missingInputURL = "Input URL is missing"
    static let missingRedirectURL = "Redirecting url is missing"
    static let sponseredfailWithContent = "Failed with previous mutable content"
    static let incorrectParameter = "Parameter for type method(:) call is invalid please verify the input parameter"
    static let tiggerfailure = "Trigger failure"
    static let mediaLengthExceeded = "media length is greater than 5 mb"
    static let urlRequestException = "URL request Exeception."
    static let dataNotFound = "Data not found after api call."
    static let networkResponseFaliure = "status code:- %@ \n reason:-  %@."
    static let dataTypeCastingError = "Data type casting error."
    static let requestTimeOut = "Network request time is out please check the internet connection."
    static let failedToLogError = "failed to log error to server."
    static let siteStatusNotActive = "site status is not Active"
    static let subscriberNotAvailable = "Subscriber is not active."
    static let profileAlreadyExist = "User profile already exist. In server"
    static let siteKeyNotAvailable = "site key is not available."
    static let permissionNotDetermine = "Notification Permission is not Determined."
    static let notificationUserActionFailed = "Notification user action failed which is not retry able message: - %@."
    static let defaultActionIdentifer = "com.apple.UNNotificationDefaultActionIdentifier"
    static let viewCountTrackingFailed = "viewCountTrackingFailed"
    static let clickCountTrackingFailed = "clickCountTrackingFailed"
    static let notificationRefetchFailed = "notificationRefetchFailed"
}

// MARK: - Registration Messages.

struct RegisterationMessages {
    static let appIDNotFound = "Please provide proper App ID."
    static let notificationDisable = "To access the notification api please allow the notifications from."
    static let registerationFailed = "Please check App ID or re-visit setup instructions."
}

