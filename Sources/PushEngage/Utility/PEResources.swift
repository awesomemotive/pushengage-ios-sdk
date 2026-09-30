//
//  PEResources.swift
//  PushEngage
//

import Foundation

/// Resolves the bundle containing the PushEngage module's resources
/// (e.g. the compiled InAppMessaging CoreData model) across both
/// distribution channels: SPM (`Bundle.module`) and CocoaPods
/// (`resource_bundles` → `PushEngageResources.bundle`).
enum PEResources {

    static let bundle: Bundle = {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        let candidates = [Bundle(for: BundleToken.self), Bundle.main]
        for candidate in candidates {
            if let url = candidate.url(forResource: "PushEngageResources", withExtension: "bundle"),
               let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return Bundle(for: BundleToken.self)
        #endif
    }()
}

#if !SWIFT_PACKAGE
private final class BundleToken {}
#endif
