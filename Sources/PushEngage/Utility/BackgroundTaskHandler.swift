//
//  BackgroundTaskHandler.swift
//  PushEngage
//
//  Created by Abhishek on 03/05/21.
//

import Foundation
import UIKit
import PushEngageExtension

// Wraps a unit of work in a UIApplication background task so it can complete if
// the host app is suspended.

class BackgroundTaskExpirationHandler: BackgroundTaskType {

    private var identifier = UIBackgroundTaskIdentifier.invalid

    class func run(handler: (BackgroundTaskExpirationHandler?) -> Void) {
        let task = BackgroundTaskExpirationHandler()
        task.begin()
        handler(task)
    }

    func begin() {
        PELogger.debug(className: String(describing: BackgroundTaskExpirationHandler.self),
                       message: "task started....")
        self.identifier = UIApplication.shared.beginBackgroundTask {
            self.end()
        }
    }

    func end() {
        if identifier != UIBackgroundTaskIdentifier.invalid {
            UIApplication.shared.endBackgroundTask(identifier)
        }
        identifier = UIBackgroundTaskIdentifier.invalid
        PELogger.debug(className: String(describing: BackgroundTaskExpirationHandler.self),
                       message: "Background task ended")
    }
}

struct AppBackgroundTaskProvider: BackgroundTaskProviderType {
    func run(handler: (BackgroundTaskType?) -> Void) {
        BackgroundTaskExpirationHandler.run { handler($0) }
    }
}
