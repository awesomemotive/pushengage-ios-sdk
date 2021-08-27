//
//  Configuration.swift
//  PushEngage
//
//  Created by Abhishek on 16/06/21.
//

import Foundation

struct Configuration {
    static var enviroment: Environment = .prod
}

@objc public enum Environment: Int {
    case dev
    case prod
}

struct PENetworkURLs {
    static let syncapiObject = DependencyInitialize.getUserDefaults()
                                            .getObject(for: SyncAPIData.self,
                                                       key: UserDefaultConstant.pushEngageSyncApi)
    
    // MARK: - Default Staging BaseURL
    
    static let stagingTriggerURL
    = "https://x9dlvh1zcg.execute-api.us-east-1.amazonaws.com/beta/streams/staging-trigger/records"
    static let stagingBackendURL = "https://staging-dexter.pushengage.com/p/v1/"
    static let stagingBackendCdnURL = "https://staging-dexter1.pushengage.com/p/v1/"
    static let stagingNotifAnalyticURL = "https://staging-dexter1.pushengage.com/p/v1/"
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
    
    
    static var backendCdnBaseURL: String {
        switch Configuration.enviroment {
        case .dev:
            return syncapiObject?.api?.backendCloud ?? stagingBackendCdnURL
        case .prod:
            return  syncapiObject?.api?.backendCloud ?? productionBackendCdnURL
        }
    }
    
    static var backendBaseURL: String {
        switch Configuration.enviroment {
        case .dev:
            return syncapiObject?.api?.backend ?? stagingBackendURL
        case .prod:
            return  syncapiObject?.api?.backend ?? productionBackendURL
        }
    }
    
    static var notifyAnalyticsBaseURL: String {
        switch Configuration.enviroment {
        case .dev:
            return syncapiObject?.api?.analytics ?? stagingNotifAnalyticURL
        case .prod:
            return syncapiObject?.api?.analytics ?? productionNotifyAnalyticURL
        }
    }
    
    static var triggerBaseURL: String {
        switch Configuration.enviroment {
        case .dev:
            return syncapiObject?.api?.trigger ?? stagingTriggerURL
        case .prod:
            return syncapiObject?.api?.trigger ?? productionTriggerURL
        }
    }
    
    static var loggingBaseURL: String {
        switch Configuration.enviroment {
        case .dev:
            return syncapiObject?.api?.log  ?? stagingLoggerURL
        case .prod:
            return syncapiObject?.api?.log ?? productionLoggingURL
        }
    }
}
