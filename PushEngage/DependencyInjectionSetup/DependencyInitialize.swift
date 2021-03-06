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
            
            // MARK: - LocationProtocol
            // this locationInfoProtocol is beign registered with its manager
            // which is location manager. As you can see there is no dependency to initialize the
            // location manager. So no need to resolve the dependencies
            .register(LocationInfoProtocol.self) { _  in
                LocationManager()
            }
            
            // MARK: - UserDefaultProtocol
            
            .register(UserDefaultProtocol.self) {_ in
                UserDefaultManager()
            }
            
            // MARK: - NetworkRouter
            
            .register(NetworkRouter.self) { _ in
                Router()
            }
            
            // MARK: - DataSourceProtocol
            .register(DataSourceProtocol.self) { resolver in
                let  userDefault = resolver.resolve(UserDefaultProtocol.self)
                return DataManager(userDefault: userDefault)
            }
            
            // MARK: - NotificationProtocol
            .register(NotificationProtocol.self) { resolved in
                let userDefaultServices = resolved.resolve(UserDefaultProtocol.self)
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
            
            .register(SubscriberService.self) { resolver in
                let datasource = resolver.resolve(DataSourceProtocol.self)
                let networkRouter = resolver.resolve(NetworkRouter.self)
                let userDefault = resolver.resolve(UserDefaultProtocol.self)
                return SubscriberServiceManager(datasourceProtocol: datasource,
                                                networkRouter: networkRouter,
                                                userDefault: userDefault)
            }
            
            // MARK: - NotificationLifeCycleService
            .register(NotificationLifeCycleService.self) { resolver in
                let networkRouter = resolver.resolve(NetworkRouter.self)
                let datasource = resolver.resolve(DataSourceProtocol.self)
                let userdefault = resolver.resolve(UserDefaultProtocol.self)
                return NotificationLifeCycleManager(networkRouter: networkRouter,
                                                    datasource: datasource,
                                                    userDefault: userdefault)
            }
            
            // MARK: - ApplicationProtocol
            
            .register(ApplicationProtocol.self) { resolve in
                let userDefault = resolve.resolve(UserDefaultProtocol.self)
                let subscriberService = resolve.resolve(SubscriberService.self)
                let notificationLifeCycleService = resolve.resolve(NotificationLifeCycleService.self)
                let networkService = resolve.resolve(NetworkRouter.self)
                return ApplicationService(userDefault: userDefault,
                                          subscriberService: subscriberService,
                                          notificationLifeCycleService: notificationLifeCycleService,
                                          networkService: networkService)
            }
            
            // MARK: - NotificationExtensionProtocol
            
            .register(NotificationExtensionProtocol.self) { resolver in
                let networkRouter = resolver.resolve(NetworkRouter.self)
                let userDefaultService = resolver.resolve(UserDefaultProtocol.self)
                let notificationCycleService = resolver.resolve(NotificationLifeCycleService.self)
                return NotificationExtensionManager(networkService: networkRouter,
                                                    notifcationLifeCycleService: notificationCycleService,
                                                    userDefaultDatasource: userDefaultService)
            }
            
            // MARK: - TriggerCampaignProtocol
            
            .register(TriggerCampaignProtocol.self) { resolver  in
                let networkRouter = resolver.resolve(NetworkRouter.self)
                let userDefaultService = resolver.resolve(UserDefaultProtocol.self)
                return TriggerCampaignManager(userDefaultService: userDefaultService,
                                              networkService: networkRouter)
            }
            
            // MARK: - PEViewModel
        
            .register(PEViewModel.self) { resolver in
                let applicationService = resolver.resolve(ApplicationProtocol.self)
                let notificationService = resolver.resolve(NotificationProtocol.self)
                let notificationExtensionService = resolver.resolve(NotificationExtensionProtocol.self)
                let subsciberService = resolver.resolve(SubscriberService.self)
                let userDefaultService = resolver.resolve(UserDefaultProtocol.self)
                let notificationLifeCycleService = resolver.resolve(NotificationLifeCycleService.self)
                let locationService = resolver.resolve(LocationInfoProtocol.self)
                let triggerCampaiginService = resolver.resolve(TriggerCampaignProtocol.self)
                return PEViewModel(applicationService: applicationService,
                                   notificationService: notificationService,
                                   notificationExtensionService: notificationExtensionService,
                                   subscriberService: subsciberService,
                                   userDefaultService: userDefaultService,
                                   notificationLifeCycleService: notificationLifeCycleService,
                                   locationService: locationService,
                                   triggerCamapaiginService: triggerCampaiginService)
            }
    }
    
    class func getPEViewModelDependency() -> PEViewModel {
        return sharedInstance.container.resolve(PEViewModel.self)
    }
    
    class func getUserDefaults() -> UserDefaultProtocol {
        return sharedInstance.container.resolve(UserDefaultProtocol.self)
    }
    
    class func getRouter() -> NetworkRouter {
        return sharedInstance.container.resolve(NetworkRouter.self)
    }
}
