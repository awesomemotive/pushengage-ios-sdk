//
//  NotificationExtensionFactory.swift
//  PushEngageExtension
//

import Foundation

enum NotificationExtensionFactory {

    /// Builds the `NotificationExtensionType` graph (routers, user defaults, lifecycle, manager).
    /// Also applies the logging flag the app persisted into the shared app-group
    /// container, so `PushEngage.enableLogging` covers extension processes too.
    /// The download and lifecycle paths get distinct Routers: `Router` keeps its
    /// in-flight task in an unsynchronized slot, so sharing one instance lets
    /// overlapping notifications clobber each other's requests. Both still share
    /// the process-wide `URLSession`.
    static func make(userDefaults: UserDefaultsType = PECoreServices.getUserDefaults(),
                     downloadRouter: NetworkRouterType = PECoreServices.getRouter(),
                     lifecycleRouter: NetworkRouterType = PECoreServices.getRouter()) -> NotificationExtensionType {
        PELogger.isLoggingEnable = userDefaults.isSdkLoggingEnabled
        let lifecycle = NotificationLifeCycleManager(networkRouter: lifecycleRouter,
                                                     datasource: DataManager(userDefault: userDefaults),
                                                     userDefault: userDefaults,
                                                     backgroundTask: ExtensionBackgroundTaskProvider())
        return NotificationExtensionManager(networkService: downloadRouter,
                                            notifcationLifeCycleService: lifecycle,
                                            userDefaultDatasource: userDefaults)
    }
}
