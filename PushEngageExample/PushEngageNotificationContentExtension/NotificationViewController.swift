//
//  NotificationViewController.swift
//  PushEngageNotificationContentExtension
//
//  Created by Himshikhar Gayan on 15/02/24.
//

import UIKit
import UserNotifications
import UserNotificationsUI
import SwiftUI
import PushEngage

@available(iOSApplicationExtension 13.0, *)
class NotificationViewController: UIViewController, UNNotificationContentExtension {
    
    fileprivate var hostingView: UIHostingController<ContentView>?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .white
    }
    
    func didReceive(_ notification: UNNotification) {
        print(notification.request.content.categoryIdentifier)
        if(notification.request.content.categoryIdentifier == "customNotification"){
            let payLoad = PushEngage.getCustomUIPayLoad(for: notification.request)
            let view = ContentView(payLoadInfo: payLoad)
            hostingView = UIHostingController(rootView: view)
            addChild(hostingView!)
            hostingView!.view.translatesAutoresizingMaskIntoConstraints = false
            self.view.addSubview(hostingView!.view)
            NSLayoutConstraint.activate([hostingView!.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                                         hostingView!.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
                                         hostingView!.view.topAnchor.constraint(equalTo: self.view.topAnchor),
                                         hostingView!.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
                                         hostingView!.view.centerYAnchor.constraint(equalTo: self.view.centerYAnchor),
                                         hostingView!.view.centerXAnchor.constraint(equalTo: self.view.centerXAnchor)])
        }
    }
    
}
