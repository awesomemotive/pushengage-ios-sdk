//
//  Configuration.swift
//  PushEngage
//
//  Created by Abhishek on 16/06/21.
//

import Foundation

@objc public enum PEEnvironment: Int {
    case staging = 0
    case production = 1
}

struct PENetworkURLs {

    // MARK: - Default Staging BaseURL

    static let stagingTriggerURL
    = "https://x9dlvh1zcg.execute-api.us-east-1.amazonaws.com/beta/streams/staging-trigger/records"
    static let stagingBackendURL = "https://staging-dexter.pushengage.com/p/v1/"
    static let stagingBackendCdnURL = "https://staging-dexter.pushengage.com/p/v1/"
    static let stagingNotifAnalyticURL = "https://staging-dexter.pushengage.com/p/v1/"
    static let stagingLoggerURL = "https://cwlvm0dw8e.execute-api.us-east-1.amazonaws.com/staging/v1/"

    // not using currently for future.
    static let stagingOptinBaseURL
    = "https://xgmlyjovsg.execute-api.us-east-1.amazonaws.com/beta/streams/staging-optin/records"


    // MARK: - Default prod BaseURL

    static let productionBackendURL = "https://clients-api.pushengage.com/p/v1/"
    static let productionNotifyAnalyticURL = "https://noti-analytics.pushengage.com/p/v1/"
    static let productionTriggerURL
    = "https://m4xrk918t5.execute-api.us-east-1.amazonaws.com/beta/streams/production_triggers/records"
    static let productionBackendCdnURL = "https://dexter-cdn.pushengage.com/p/v1/"
    static let productionLoggingURL = "https://notify.pushengage.com/v1/"

    // not using currently for future.
    static let productionOptinBaseURL = "https://oeqepmcz7a.execute-api.us-east-1.amazonaws.com/beta/streams/optin/records"


    private static func syncAPIData(_ userDefaults: UserDefaultsType) -> SyncAPIData? {
        userDefaults.getObject(for: SyncAPIData.self, key: UserDefaultConstant.pushEngageSyncApi)
    }

    static func backendCdnBaseURL(_ userDefaults: UserDefaultsType = PECoreServices.getUserDefaults()) -> String {
        let syncapiObject = syncAPIData(userDefaults)
        switch userDefaults.environment {
        case .staging:
            return syncapiObject?.api?.backendCloud ?? stagingBackendCdnURL
        case .production:
            return syncapiObject?.api?.backendCloud ?? productionBackendCdnURL
        }
    }

    static func backendBaseURL(_ userDefaults: UserDefaultsType = PECoreServices.getUserDefaults()) -> String {
        let syncapiObject = syncAPIData(userDefaults)
        switch userDefaults.environment {
        case .staging:
            return syncapiObject?.api?.backend ?? stagingBackendURL
        case .production:
            return syncapiObject?.api?.backend ?? productionBackendURL
        }
    }

    static func notifyAnalyticsBaseURL(_ userDefaults: UserDefaultsType = PECoreServices.getUserDefaults()) -> String {
        let syncapiObject = syncAPIData(userDefaults)
        switch userDefaults.environment {
        case .staging:
            return syncapiObject?.api?.analytics ?? stagingNotifAnalyticURL
        case .production:
            return syncapiObject?.api?.analytics ?? productionNotifyAnalyticURL
        }
    }

    static func triggerBaseURL(_ userDefaults: UserDefaultsType = PECoreServices.getUserDefaults()) -> String {
        let syncapiObject = syncAPIData(userDefaults)
        switch userDefaults.environment {
        case .staging:
            return syncapiObject?.api?.trigger ?? stagingTriggerURL
        case .production:
            return syncapiObject?.api?.trigger ?? productionTriggerURL
        }
    }

    static func loggingBaseURL(_ userDefaults: UserDefaultsType = PECoreServices.getUserDefaults()) -> String {
        let syncapiObject = syncAPIData(userDefaults)
        switch userDefaults.environment {
        case .staging:
            return syncapiObject?.api?.log ?? stagingLoggerURL
        case .production:
            return syncapiObject?.api?.log ?? productionLoggingURL
        }
    }
}
