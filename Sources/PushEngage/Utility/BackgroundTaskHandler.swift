//
//  BackgroundTaskHandler.swift
//  PushEngage
//
//  Created by Abhishek on 03/05/21.
//

import Foundation
import UIKit

// Wraps a unit of work in a UIApplication background task so it can complete if
// the host app is suspended. In app-extension builds (APPLICATION_EXTENSION_API_ONLY=YES)
// this becomes a no-op wrapper — extensions have their own fixed runtime budget and
// cannot request background time — and `run` invokes the handler with `nil`.

class BackgroundTaskExpirationHandler {

    private var identifier = UIBackgroundTaskIdentifier.invalid

    class func run(handler: (BackgroundTaskExpirationHandler?) -> Void) {
        #if !APPLICATION_EXTENSION_API_ONLY
        let task = BackgroundTaskExpirationHandler()
        task.begin()
        handler(task)
        #else
        handler(nil)
        #endif
    }

    func begin() {
        #if !APPLICATION_EXTENSION_API_ONLY
        PELogger.debug(className: String(describing: BackgroundTaskExpirationHandler.self),
                       message: "task started....")
        self.identifier = UIApplication.shared.beginBackgroundTask {
            self.end()
        }
        #endif
    }

    func end() {
        #if !APPLICATION_EXTENSION_API_ONLY
        if identifier != UIBackgroundTaskIdentifier.invalid {
            UIApplication.shared.endBackgroundTask(identifier)
        }
        identifier = UIBackgroundTaskIdentifier.invalid
        PELogger.debug(className: String(describing: BackgroundTaskExpirationHandler.self),
                       message: "Background task ended")
        #endif
    }
}
