//
//  Constants.swift
//  PushEngage
//
//  Created by Abhishek on 17/02/21.
//

package struct NetworkConstants {
    // MARK: - Request Timeout
    package static let requestTimeout = 60.0
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
    static let requestHeaderClientKey = "X-Pe-Client"
    static let requestHeaderClientVersionKey = "X-Pe-Client-Version"
    static let requestHeaderSdkVersionKey = "X-Pe-Sdk-Version"
    static let requestHeaderAppIdKey = "X-Pe-App-Id"
    static let requestHeaderUserAgentKey = "User-Agent"

    // MARK: - Values
    static let requestHeaderAuthorizationValue = "Bearer "
    static let requestHeaderContentTypeValue = "application/json"
    static let requestHeaderContentTypeValueForcharSet = "application/x-www-form-urlencoded; charset=utf-8"
    static let requestHeaderRefererValue = "https://pushengage.com/service-worker.js"
    static let requestHeaderClientValue = "iOS"
    // MARK: - BASE URL
    
    static var baseURL: String { PENetworkURLs.backendBaseURL() }
    
    static var notifAnalyticURL: String { PENetworkURLs.notifyAnalyticsBaseURL() }
    
    static var triggerCampaignBaseURL: String { PENetworkURLs.triggerBaseURL() }
    
    static var errorLoggingBaseURL: String { PENetworkURLs.loggingBaseURL() }
    
    static var cdnurl: String { PENetworkURLs.backendCdnBaseURL() }
    
    // MARK: - SDK version
    //
    // Keep in sync with `spec.version` in PushEngage.podspec and the README badge
    // on every release. This string is sent to the PushEngage backend in the
    // `X-Pe-Sdk-Version` HTTP header, in the User-Agent string, and in the
    // `swv` field of subscribe/sync/trackEvent payloads; a mismatch with the
    // actual shipped version corrupts server-side analytics.
    package static let sdkVersion = "1.0.0"

    // MARK: - URL relative - path
    static let addSubscriberPath = "subscriber/add"
    static let getHashPath = "subscriber/%@"
    static let checkSubscriberHash = "subscriber/check/%@"
    static let subscriberAttribute = "subscriber/%@/attributes"
    static let getSubscriberAttribute = "subscriber/%@/attributes"
    static let updateSubscriberStatus = "subscriber/updatesubscriberstatus"
    static let addProfileId = "subscriber/profile-id/add"
    static let subscriberUpgrade = "subscriber/upgrade"
    package static let timeZone = "subscriber/timezone/add"
    static let addSegment = "subscriber/segments/add"
    static let removeSegment = "subscriber/segments/remove"
    static let dynamicAddSegment = "subscriber/dynamicSegments/add"
    static let segmentHashArray = "subscriber/segments/segmentHashArray"
    static let dynamicRemoveSegment = "subscriber/dynamicSegments/remove"
    static let updateTrigger = "subscriber/updatetriggerstatus"
    static let updateSubscriber = "subscriber/%@"
    static let syncSubscriber = "sites/%@/sync/ios"
    static let addAlert = "alerts"
    
    // MARK: - Notification relative path
    static let notificationView = "notification/view"
    static let notificationClicked = "notification/click"
    static let sponsoreFetch = "notification/fetch"
    
    // MARK: Goal tracking
    static let sendGoal = "goals"

    // MARK: Track event
    static let trackEvent = "events/track"

    // MARK: identify / logout (subscriber fields)
    static let identifySubscriber       = "subscriber/%@"
    static let logoutSubscriberFields   = "subscriber/%@/fields"
    
    // MARK: - Error logging relative path
    static let logs = "logs"
    
    // MARK: - HTTPS
    package static let https = "https://"
    package static let http = "http://"
}

package struct PayloadConstants {
    static let attachmentKey = "att"
    package static let launchUrlKey = "u"
    package static let custom = "pe"
    package static let deeplinking = "dl"
    package static let actionSelected = "actionSelected"
    package static let additionalData = "ad"
    package static let tag = "tag"
    package static let duplicate = "duplicate"
    package static let title = "t"
    package static let aps = "aps"
    package static let alert = "alert"
    static let sound = "sound"
    static let badge = "badge"
    static let custombadge = "ba"
    static let customSound = "s"
    static let actionButton = "ab"
    package static let customsubtitle = "sb"
    package static let customBody = "b"
}

struct InfoPlistConstants {
    static let PushEngageInAppEnabled = "PushEngageInAppEnabled"
    static let locationWhenInUse = "NSLocationAlwaysAndWhenInUseUsageDescription"
    static let loactionAllow = "NSLocationWhenInUseUsageDescription"
    static let pushEngageAppGroupKey = "PushEngage_App_Group_Key"
    static let pushEngageAutoHandleDeeplinkUrl = "PushEngageAutoHandleDeeplinkURL"
}

package struct UserDefaultConstant {
    static let environment = "environment"
    package static let deviceToken = "device_token"
    package static let subscriberHash = "subscriber_hash"
    static let permissionState = "notification_permission"
    static let appId = "app_id"
    static let country = "country"
    static let state = "state"
    static let city = "city"
    static let notificationId = "notification_id"
    static let badgeCount = "badge_count"
    static let isSdkLoggingEnabled = "is_sdk_logging_enabled"
    static let lastSmartSubscribeDate = "last_smart_subscribe_date"
    static let appIsStarting = "app_is_starting"
    package static let pushEngageSyncApi = "pushengage_sync_api"
    static let ispermissionAlertedKey = "is_permission_alerted"
    package static let profileId = "pe_host_profile_id"
    static let siteStatus = "pe_host_site_status"
    static let siteKey = "pe_site_key"
    static let locationCoordinates = "location_coordinates"
    static let isSubscriberDeleted = "is_subscriber_deleted"
    static let isManuallyUnsubscribed = "is_manually_unsubscribed"
    static let isTriedFirstTime = "is_tried_first_time"
    static let sponsered = "pe_sponser"
    static let isSwizzled = "is_swizzled"
    static let platform = "pe_platform"
    static let wrapperVersion = "pe_wrapper_version"
    static let subscriberFieldsCache = "pe_subscriber_fields_cache"
    static let subscriberFieldsCacheTimestamp = "pe_subscriber_fields_cache_ts"
}

// MARK: - Query parms key

extension String {
    package static let swvKey = "swv"
    package static let isEuKey = "is_eu"
    package static let geoFetch = "geo_fetch"
}

// MARK: - Parsing Constants

package struct ParsingConstants {
    package static let data = "data"
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
    static let canceled = "Cancelled the operation in operationQueue"
    static let missingInputURL = "Input URL is missing"
    static let missingRedirectURL = "Redirecting URL is missing"
    static let sponseredfailWithContent = "Failed with previous mutable content"
    static let incorrectParameter = "Parameter for type method(:) call is invalid please verify the input parameter"
    static let tiggerfailure = "Trigger failure"
    static let mediaLengthExceeded = "Media length is greater than 5 mb"
    static let urlRequestException = "URL request Exeception."
    static let dataNotFound = "Data not found after API call."
    static let networkResponseFaliure = "Status code:- %@ \n reason:-  %@."
    static let dataTypeCastingError = "Data type casting error."
    static let requestTimeOut = "Network request time is out please check the internet connection."
    static let failedToLogError = "Failed to log error to server."
    static let siteStatusNotActive = "Site status is not Active"
    static let subscriberNotAvailable = "Subscriber is not active."
    static let profileAlreadyExist = "User profile already exist. In server"
    static let siteKeyNotAvailable = "Site key is not available."
    static let permissionNotDetermine = "Notification Permission is not Determined."
    static let notificationUserActionFailed = "Notification user action failed which is not retry able message: - %@."
    package static let defaultActionIdentifier = "com.apple.UNNotificationDefaultActionIdentifier"
    static let viewCountTrackingFailed = "viewCountTrackingFailed"
    static let clickCountTrackingFailed = "clickCountTrackingFailed"
    static let notificationRefetchFailed = "notificationRefetchFailed"
    static let invalidInput = "One or more inputs provided are not valid."
    static let permissionNotGranted = "Notification Permission is not Granted."
}

// MARK: - Registration Messages.

struct RegistrationMessages {
    static let appIDNotFound = "Please provide proper App ID."
    package static let notificationDisabled = "To access the notification api please allow the notifications from."
    static let registrationFailed = "Please check App ID or re-visit setup instructions."
}

