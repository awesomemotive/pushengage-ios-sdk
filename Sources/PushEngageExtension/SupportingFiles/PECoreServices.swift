//
//  PECoreServices.swift
//  PushEngageExtension
//

import Foundation

/// The single construction point for the core services. Both accessors build a
/// fresh instance per call — the instances are stateless wrappers (storage is
/// the app-group `UserDefaults`; all Routers share one static `URLSession`), so
/// nothing is cached or shared at this layer. Every construction of these
/// services in either module must go through here so the recipe can never
/// diverge between the app and extension processes.
package enum PECoreServices {

    package static func getUserDefaults() -> UserDefaultsType {
        return UserDefaultManager()
    }

    package static func getRouter() -> NetworkRouterType {
        return Router()
    }
}
