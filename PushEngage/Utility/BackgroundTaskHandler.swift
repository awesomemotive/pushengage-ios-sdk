//
//  BackgroundTaskHandler.swift
//  PushEngage
//
//  Created by Abhishek on 03/05/21.
//

import Foundation
import UIKit


// This class is handling the Background task with expiration
// of task when any task take place in the backgound mode

class BackgroundTaskExpirationHandler {
    
    private let application: UIApplication
    private var identifier = UIBackgroundTaskIdentifier.invalid

    init(application: UIApplication) {
        self.application = application
    }

    class func run(application: UIApplication,
                   handler: (BackgroundTaskExpirationHandler) -> Void) {

        let backgroundTask = BackgroundTaskExpirationHandler(application: application)
        backgroundTask.begin()
        handler(backgroundTask)
    }

    func begin() {
        PELogger.debug(className: String(describing: BackgroundTaskExpirationHandler.self),
                       message: "task started....")
        self.identifier = application.beginBackgroundTask {
            self.end()
        }
    }

    func end() {
        if identifier != UIBackgroundTaskIdentifier.invalid {
            application.endBackgroundTask(identifier)
        }

        identifier = UIBackgroundTaskIdentifier.invalid
        PELogger.debug(className: String(describing: BackgroundTaskExpirationHandler.self),
                       message: "Background task ended")
    }
}
