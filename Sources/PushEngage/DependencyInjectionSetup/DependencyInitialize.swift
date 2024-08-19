//
//  DependencyInitialize.swift
//  PushEngage
//
//  Created by Abhishek on 26/02/21.
//

import Foundation

// Custom Dependency Initializer to inject dependencies to the Class.

/*
 1. First register you manager with its protocol name.
 2. if your manager has some dependencies resolve it and provide the dependency
    and make sure before resolving the dependency. That protocol which you are trying to resolve
    is registered to the container.
 3. This container is place where you have to manages dependencies for your code.
 */

// MARK: - private class for Dependency Initialization
internal final class DependencyInitialize {
    
    static let sharedInstance = DependencyInitialize()
    
    private var container: Container
    
    private init() {
        
        container = Container()
            
            // MARK: - UserDefaultProtocol
            
            .register(UserDefaultsType.self) {_ in
                UserDefaultManager()
            }
            
            // MARK: - NetworkRouter
            
            .register(NetworkRouterType.self) { _ in
                Router()
            }
            
            // MARK: - DataSourceProtocol
            .register(DataSourceType.self) { resolver in
                let  userDefault = resolver.resolve(UserDefaultsType.self)
                return DataManager(userDefault: userDefault)
            }
            
            // MARK: - NotificationProtocol
            .register(NotificationServiceType.self) { resolved in
                let userDefaultServices = resolved.resolve(UserDefaultsType.self)
                if #available(iOS 10.0, *) {
                    return NotificationSettingsManageriOS10(userDefaultService: userDefaultServices)
                } else {
                    return NotificationSettingsManageriOS9(userDefaultService: userDefaultServices)
                }
            }
            
            // MARK: - SubscriberService
            // Here we are registering SubscriberService to the SubscriberServiceManager
            // We find out that SubscriberServiceManager is having dependency of
            // 1. DataSourceProtocol
            // 2. NetworkRouter
            // 3. UserDefaultProtocol
            // so before initializing SubscriberServiceManager we need to reslove these dependencies.
            // So we are resolving it and you and notice this that DataSourceProtocol and other dependencies
            // are already registered with the container.
            
            .register(SubscriberServiceType.self) { resolver in
                let datasource = resolver.resolve(DataSourceType.self)
                let networkRouter = resolver.resolve(NetworkRouterType.self)
                let userDefault = resolver.resolve(UserDefaultsType.self)
                return SubscriberServiceManager(datasourceProtocol: datasource,
                                                networkRouter: networkRouter,
                                                userDefault: userDefault)
            }
            
            // MARK: - NotificationLifeCycleService
            .register(NotificationLifeCycleServiceType.self) { resolver in
                let networkRouter = resolver.resolve(NetworkRouterType.self)
                let datasource = resolver.resolve(DataSourceType.self)
                let userdefault = resolver.resolve(UserDefaultsType.self)
                return NotificationLifeCycleManager(networkRouter: networkRouter,
                                                    datasource: datasource,
                                                    userDefault: userdefault)
            }
            
            // MARK: - ApplicationProtocol
            
            .register(ApplicationServiceType.self) { resolve in
                let userDefault = resolve.resolve(UserDefaultsType.self)
                let subscriberService = resolve.resolve(SubscriberServiceType.self)
                let notificationLifeCycleService = resolve.resolve(NotificationLifeCycleServiceType.self)
                let networkService = resolve.resolve(NetworkRouterType.self)
                return ApplicationService(userDefault: userDefault,
                                          subscriberService: subscriberService,
                                          notificationLifeCycleService: notificationLifeCycleService,
                                          networkService: networkService)
            }
            
            // MARK: - NotificationExtensionProtocol
            
            .register(NotificationExtensionType.self) { resolver in
                let networkRouter = resolver.resolve(NetworkRouterType.self)
                let userDefaultService = resolver.resolve(UserDefaultsType.self)
                let notificationCycleService = resolver.resolve(NotificationLifeCycleServiceType.self)
                return NotificationExtensionManager(networkService: networkRouter,
                                                    notifcationLifeCycleService: notificationCycleService,
                                                    userDefaultDatasource: userDefaultService)
            }
            
            // MARK: - TriggerCampaignProtocol
            
            .register(TriggerCampaignManagerType.self) { resolver  in
                let networkRouter = resolver.resolve(NetworkRouterType.self)
                let userDefaultService = resolver.resolve(UserDefaultsType.self)
                let dataSource = resolver.resolve(DataSourceType.self)
                return TriggerCampaignManager(userDefaultService: userDefaultService,
                                              networkService: networkRouter,
                                              dataSource: dataSource)
            }
            
            // MARK: - PEViewModel
        
            .register(PEManagerType.self) { resolver in
                let applicationService = resolver.resolve(ApplicationServiceType.self)
                let notificationService = resolver.resolve(NotificationServiceType.self)
                let notificationExtensionService = resolver.resolve(NotificationExtensionType.self)
                let subscriberService = resolver.resolve(SubscriberServiceType.self)
                let userDefaultService = resolver.resolve(UserDefaultsType.self)
                let notificationLifeCycleService = resolver.resolve(NotificationLifeCycleServiceType.self)
                let triggerCampaiginService = resolver.resolve(TriggerCampaignManagerType.self)
                
                return PEManager(applicationService: applicationService,
                                   notificationService: notificationService,
                                   notificationExtensionService: notificationExtensionService,
                                   subscriberService: subscriberService,
                                   userDefaultService: userDefaultService,
                                   notificationLifeCycleService: notificationLifeCycleService,
                                   triggerCamapaiginService: triggerCampaiginService)
            }
    }
    
    class func getPEManagerDependency() -> PEManagerType {
        return sharedInstance.container.resolve(PEManagerType.self)
    }
    
    class func getUserDefaults() -> UserDefaultsType {
        return sharedInstance.container.resolve(UserDefaultsType.self)
    }
    
    class func getRouter() -> NetworkRouterType {
        return sharedInstance.container.resolve(NetworkRouterType.self)
    }
}
