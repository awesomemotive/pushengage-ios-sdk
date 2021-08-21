//
//  PEPay.swift
//  PushNotificationDemo
//
//  Created by Abhishek on 16/07/21.
//

import UIKit

// swiftlint:disable all

class PEPay: UIViewController {

    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "PEPay"
        if #available(iOSApplicationExtension 11.0, *) {
            navigationItem.largeTitleDisplayMode = .automatic
        } else {
            // Fallback on earlier versions
        }
        
    }
}
