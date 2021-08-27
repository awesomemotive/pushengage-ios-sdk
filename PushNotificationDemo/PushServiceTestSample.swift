//
//  ViewController.swift
//  sample
//
//  Created by Abhishek on 22/01/21.
//

import UIKit
import PushEngage
import CoreLocation

// swiftlint:disable all

enum ApiAction : Int {
    case addSegment = 0
    case removeSegment = 1
    case addDynamicSegement = 2
    case addAttribute = 3
    case deleteAttribute = 4
    case trigger = 5
    case addProfileId = 6
    case getSubscriberDetails = 7
    case getAttribute = 8
}

class PushServiceTestSample: UIViewController {
    
    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var tableView : UITableView!
    let titles = ["Add segment" , "Remove segment", "Add dynamic ", "AddAttribute","Delete attribute",
    "Trigger","add profileId", "getSubscriberDetails","getAttribute"]
    
    var locationManager : CLLocationManager?
    
    override func viewDidLoad() {
        navigationItem.title = "PushEngage Sample App"
        textView.text = nil
        textView.layer.borderWidth = 0.2
        textView.layer.borderColor = UIColor.black.cgColor
        tableView.delegate = self
        tableView.dataSource = self
        tableView.layer.borderWidth = 0.2
        tableView.layer.borderColor = UIColor.black.cgColor
        locationManager = CLLocationManager()
        locationManager?.requestAlwaysAuthorization()
        let gesture = UITapGestureRecognizer(target: self, action: #selector(tap))
        gesture.cancelsTouchesInView = false
        view.addGestureRecognizer(gesture)
        super.viewDidLoad()
    }
    
    @objc func tap() {
        textView.resignFirstResponder()
    }
}

extension PushServiceTestSample : UITableViewDelegate , UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return titles.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.text = titles[indexPath.row]
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let action = ApiAction(rawValue: indexPath.row)
        switch action {
        case .addAttribute:
            PushEngage.add(attributes: ["name" : "Abhishek",
                                           "gender" : "male",
                                           "place" : "banglore",
                                           "phoneNo" : 91231114]) { [weak self] (response, error) in
                DispatchQueue.main.async {
                    if response {
                        self?.textView.text = "updated subsctiber data"
                    } else {
                        self?.textView.text = error?.localizedDescription
                    }
                }
            }
        case .addDynamicSegement:
            PushEngage.add(dynamic:  [
                ["name" : "Android" , "duration" : 7],
            ]) {
                [weak self] (response, error) in
                    DispatchQueue.main.async {
                        if response {
                            self?.textView.text = "added dynamic segments successfully"
                        } else {
                            self?.textView.text = error?.localizedDescription
                        }
                    }
            }
        case .addSegment:
            PushEngage.add(segments: ["newTestSegment","segmentTest1"]) { [weak self] (result , error) in
                DispatchQueue.main.async {
                    if result {
                        self?.textView.text = "added segment successfully"
                    } else {
                        self?.textView.text = error?.localizedDescription
                    }
                }
            }
        case .deleteAttribute:
            PushEngage.deleteAttribute(values: ["place", "gender"]) { [weak self] (response, error) in
                DispatchQueue.main.async {
                    if response {
                        self?.textView.text = "deleteAttribute successfull"
                    } else {
                        self?.textView.text = error?.localizedDescription
                    }
                }
            }
        case .removeSegment:
            PushEngage.remove(segments: ["segmentTest1"]) { [weak self] (result , error) in
                DispatchQueue.main.async {
                    if result {
                        self?.textView.text = "remove segment successfully"
                    } else {
                        self?.textView.text = error?.localizedDescription
                    }
                }
            }
        case .trigger:
            PushEngage.updateTrigger(status: false) { result, error in
                DispatchQueue.main.async { [weak self] in
                    if result {
                        self?.textView.text = "trigger added success fully"
                    } else {
                        self?.textView.text = error?.localizedDescription
                    }
                }
            }
        case .addProfileId:
            PushEngage.addProfile(for: "abhishekkumarthakur@gmail123.com") { [weak self] (result , error) in
                DispatchQueue.main.async {
                    if result {
                        self?.textView.text = "profile added successfully"
                    } else {
                        self?.textView.text = error?.localizedDescription
                    }
                }
            }
        case .getSubscriberDetails:
            PushEngage.getSubscriberDetails(for: nil) { [weak self] (response, error) in
                DispatchQueue.main.async {
                    if let value = response {
                        self?.textView.text = "\(value.segments ?? []) \n \(value.device ?? "")"
                    } else {
                        self?.textView.text = error?.localizedDescription
                    }
                }
            }
        case .getAttribute:
            PushEngage.getAttribute { [weak self] (info, error) in
                DispatchQueue.main.async {
                    if let value = info {
                        self?.textView.text = "\(value)"
                    } else {
                        self?.textView.text = error?.localizedDescription
                    }
                }
            }
        case .none:
            break
        }
    }
}



