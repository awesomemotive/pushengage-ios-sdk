//
//  DemoPrefs.swift
//  PushEngageExample
//
//  Stores the demo's runtime configuration (App ID + environment) so the
//  user can switch sites without recompiling. Mirrors Android's
//  `DemoPrefs` (PR #37). The values are read by AppDelegate at launch
//  and pushed into the SDK via `PushEngage.setAppID` / `setEnvironment`.
//

import Foundation
import PushEngage

final class DemoPrefs {

    static let shared = DemoPrefs()

    private let defaults: UserDefaults
    private enum Key {
        static let appId       = "com.pushengage.demo.appId"
        static let environment = "com.pushengage.demo.environment"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var appId: String {
        get { defaults.string(forKey: Key.appId) ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.appId) }
    }

    var environment: PEEnvironment {
        get {
            // Default to production when unset, matching Android.
            let raw = defaults.object(forKey: Key.environment) as? Int ?? PEEnvironment.production.rawValue
            return PEEnvironment(rawValue: raw) ?? .production
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.environment)
        }
    }

    var isConfigured: Bool {
        !appId.isEmpty
    }
}
