//
//  DependencyManager.swift
//  PushEngage
//
//  Created by Abhishek on 12/02/21.
//

import Foundation

// Custom Container handle registering and resolving of the dependencies.

struct Container: Resolver {
    
    let factories: [AnyServiceFactory]
    
    init() {
        self.factories = []
    }
    
    private init(factories: [AnyServiceFactory]) {
        self.factories = factories
    }
    
    // MARK: - Register
    
    @discardableResult
    func register<T>(_ interface: T.Type, instance: T) -> Container {
        return register(interface) { _ in instance }
    }
    
    @discardableResult
    func register<ServiceType>(_ type: ServiceType.Type, _ factory: @escaping (Resolver) -> ServiceType) -> Container {
        assert(!factories.contains(where: { $0.supports(type) }))
        
        let newFactory = BasicServiceFactory<ServiceType>(type, factory: { resolver in
            factory(resolver)
        })
        return .init(factories: factories + [AnyServiceFactory(newFactory)])
    }
    
    // MARK: - Resolver
    func resolve<ServiceType>(_ type: ServiceType.Type) -> ServiceType {
        guard let factory = factories.first(where: { $0.supports(type) }) else {
            fatalError("No suitable factory found")
        }
        return factory.resolve(self)
    }
    
    func factory<ServiceType>(for type: ServiceType.Type) -> () -> ServiceType {
        guard let factory = factories.first(where: { $0.supports(type) }) else {
            fatalError("No suitable factory found")
        }
        
        return { factory.resolve(self) }
    }
}


struct BasicServiceFactory<ServiceType>: ServiceFactory {
    private let factory: (Resolver) -> ServiceType
    
    init(_ type: ServiceType.Type, factory: @escaping (Resolver) -> ServiceType) {
        self.factory = factory
    }
    
    func resolve(_ resolver: Resolver) -> ServiceType {
        return factory(resolver)
    }
}

final class AnyServiceFactory {
    private let _resolve: (Resolver) -> Any
    private let _supports: (Any.Type) -> Bool
    
    init<T: ServiceFactory>(_ serviceFactory: T) {
        self._resolve = { resolver -> Any in
            serviceFactory.resolve(resolver)
        }
        self._supports = { $0 == T.ServiceType.self }
    }
    
    func resolve<ServiceType>(_ resolver: Resolver) -> ServiceType {
        let resolver = _resolve(resolver) as? ServiceType
        return resolver!
    }
    
    func supports<ServiceType>(_ type: ServiceType.Type) -> Bool {
        return _supports(type)
    }
}
