//
//  BackgroundTaskProviderType.swift
//  PushEngageExtension
//

import Foundation

/// A keep-alive token for in-flight work; `end()` releases it.
package protocol BackgroundTaskType {
    func end()
}

/// Keeps the current process alive while `handler`'s work (including its
/// escaping completions) finishes. The app module injects a
/// UIApplication-backed implementation; extension processes have no
/// background-task API and use `ExtensionBackgroundTaskProvider`.
package protocol BackgroundTaskProviderType {
    func run(handler: (BackgroundTaskType?) -> Void)
}

struct ExtensionBackgroundTaskProvider: BackgroundTaskProviderType {
    func run(handler: (BackgroundTaskType?) -> Void) {
        handler(nil)
    }
}
