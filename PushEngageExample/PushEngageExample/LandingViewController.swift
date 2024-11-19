//
//  LandingViewController.swift
//  PushEngageExample
//
//  Created by Himshikhar Gayan on 21/10/24.
//

import UIKit

class LandingViewController: UIViewController {

    @IBOutlet weak var deeplinkUrl: UILabel!
    var linkText: String?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.deeplinkUrl.text = linkText
    }

}
