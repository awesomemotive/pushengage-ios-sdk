//
//  Configuration.swift
//  PushEngage
//
//  Created by Abhishek on 16/06/21.
//

import Foundation

struct Configuration {
    static var enviroment: Environment = .dev
}

enum Environment: String {
    case dev
    case prod
}

struct PENetworkURLs {
    static let syncapiObject = DependencyInitialize.getUserDefaults()
                                            .getObject(for: SyncAPIData.self,
                                                       key: UserDefaultConstant.pushEngageSyncApi)
    
    static let stagingBaseURL = "https://staging-dexter.pushengage.com/p/v1/"
    static let defaultsubscriberBaseURL = "https://clients-api.pushengage.com/p/v1/"
    static let defaultNotifyAnalyticBaseURL = "https://noti-analytics.pushengage.com/p/v1/"
    static let defaultTriggerBaseURL = "https://x9dlvh1zcg.execute-api.us-east-1.amazonaws.com"
    static let defaultLoggingBaseURL = "https://notify.pushengage.com/v1/"
    static let stagingLoggerBaseURL = "https://cwlvm0dw8e.execute-api.us-east-1.amazonaws.com/staging/v1/"
    static let stagingcdnBaseURL = "https://staging-dexter1.pushengage.com/p/v1/"
    
    static var cdStaging: String {
        switch Configuration.enviroment {
        case .dev:
            return stagingcdnBaseURL
        case .prod:
            return  syncapiObject?.api?.backendCloud ?? defaultsubscriberBaseURL
        }
    }
    
    static var subscriberbaseURL: String {
        switch Configuration.enviroment {
        case .dev:
            return stagingBaseURL
        case .prod:
            return  syncapiObject?.api?.backend ?? defaultsubscriberBaseURL
        }
    }
    
    static var notifyAnalyticsBaseURL: String {
        switch Configuration.enviroment {
        case .dev:
            return stagingBaseURL
        case .prod:
            return syncapiObject?.api?.analytics ?? defaultNotifyAnalyticBaseURL
        }
    }
    
    static var triggerBaseURL: String {
        switch Configuration.enviroment {
        case .dev:
            return defaultTriggerBaseURL
        case .prod:
            return syncapiObject?.api?.trigger ?? defaultTriggerBaseURL
        }
    }
    
    static var loggingBaseURL: String {
        switch Configuration.enviroment {
        case .dev:
            return stagingLoggerBaseURL
        case .prod:
            return syncapiObject?.api?.log ?? defaultLoggingBaseURL
        }
    }
}
