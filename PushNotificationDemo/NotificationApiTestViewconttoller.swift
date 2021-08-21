//
//  NotificationApiTestViewconttoller.swift
//  Test
//
//  Created by Abhishek on 14/03/21.
//

import UIKit
import PushEngage
// swiftlint:disable all

class NotificationApiTestViewconttoller: UIViewController {

    @IBAction func addToCart(_ sender: Any) {
        PushEngage.createTriggerCampaign(for: TriggerCampaign(campaignName: "Shopping", eventName: "add to cart", notificationDetails: [TriggerNotification(notificationURL: Input(key: "url", value: "www.google.com"), title: Input(key: "shoes", value: "Puma shoes"), message: Input(key: "message", value: "check out the sale 50%"), notificationImage: Input(key: "image_url", value: "https://images.unsplash.com/photo-1494548162494-384bba4ab999?ixlib=rb-1.2.1&ixid=eyJhcHBfaWQiOjEyMDd9&w=1000&q=80"), bigImage: nil, actions: Input(key: "Okay", value: "www.pushengage.com")),TriggerNotification(notificationURL: Input(key: "checkout url", value: "www.amazon.com"), title: Input(key: "imported shoes", value: "Nike shoes"), message: Input(key: "messages", value: "check out the sale 90%"), notificationImage: nil, bigImage: nil, actions: Input(key: "Grab a shoes", value: "www.pushengage.com"))],data: nil)) { [weak self] (response) in
            DispatchQueue.main.async {
                if response {
                    self?.textView.text = "addToCart"
                } else {
                    self?.textView.text = "failed to add trigger"
                }
            }
        }
    }
    
    @IBAction func checkout(_ sender: Any) {
        PushEngage.createTriggerCampaign(for: TriggerCampaign(campaignName: "Shopping", eventName: "checkout", notificationDetails: nil, data: ["revenue" : "40"])) {[weak self] (response) in
            DispatchQueue.main.async {
                if response {
                    self?.textView.text = "Item checkout successfull tigger created"
                } else {
                    self?.textView.text = "faild to add trigger for check out"
                }
            }
        }
    }
    
    
    @IBOutlet weak var textView: UITextView! {
        didSet {
            textView.layer.borderWidth = 0.2
            textView.layer.borderColor = UIColor.black.cgColor
        }
    }
    
    override func viewDidLoad() {
        textView.text = nil
        super.viewDidLoad()
        
        // Do any additional setup after loading the view.
    }

}
