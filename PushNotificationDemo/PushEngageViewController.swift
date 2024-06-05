//
//  ViewController.swift
//  sample
//
//  Created by Abhishek on 22/01/21.
//

import UIKit
import PushEngage

enum APIAction: Int {
    case addSegment = 0
    case removeSegment = 1
    case addDynamicSegment = 2
    case addAttribute = 3
    case deleteAttribute = 4
    case addProfileId = 5
    case getSubscriberDetails = 6
    case getAttribute = 7
    case setAttribute = 8
    case sendGoal = 9
    case triggerCampaigns = 10
    
    var input: String? {
        switch self {
        case .addSegment:
            return "ios"
        case .removeSegment:
            return "ios"
        case .addDynamicSegment:
            return "name: ios, duration: 7"
        case .addAttribute:
            return "name: PushEngage, movies: false"
        case .deleteAttribute:
            return "name"
        case .setAttribute:
            return "name: PushEngage Sample"
        case .getSubscriberDetails, .getAttribute:
            return nil
        case .addProfileId:
            return "test@gmail.com"
        case .sendGoal, .triggerCampaigns:
            return ""
        }
    }
}

class PushEngageViewController: UIViewController {
    
    @IBOutlet weak var requestPermissionButton: UIButton!
    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var tableView: UITableView!
    let actions = ["Add To Segment",
                   "Delete From Segment",
                   "Add To Dynamic Segment",
                   "Add Attributes",
                   "Delete Attributes",
                   "Add Profile ID",
                   "Get Subscriber Details",
                   "Get Attributes",
                   "Set Attributes",
                   "Send Goal",
                   "Trigger Campaigns"]
    
    private let activityIndicator: UIActivityIndicatorView = {
        if #available(iOSApplicationExtension 13.0, *) {
            let indicator = UIActivityIndicatorView(style: .large)
            indicator.color = .red
            indicator.translatesAutoresizingMaskIntoConstraints = false
            return indicator
        } else {
            let indicator = UIActivityIndicatorView(style: .gray)
            indicator.translatesAutoresizingMaskIntoConstraints = false
            return indicator        }
    }()
    
    override func viewDidLoad() {
        navigationItem.title = "PushEngage"
        textView.text = nil
        textView.layer.cornerRadius = 12
        tableView.delegate = self
        tableView.dataSource = self
        let gesture = UITapGestureRecognizer(target: self, action: #selector(tap))
        gesture.cancelsTouchesInView = false
        view.addGestureRecognizer(gesture)
        
        view.addSubview(activityIndicator)
        
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        
        super.viewDidLoad()
        
        requestPermissionButton.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(requestNotificationPermission)))
    }
    
    @objc private func requestNotificationPermission() {
        PushEngage.requestNotificationPermission()
    }
    
    func showLoader() {
        activityIndicator.startAnimating()
        view.isUserInteractionEnabled = false // Disable user interaction while loading
    }
    
    // Function to hide the activity indicator
    func hideLoader() {
        activityIndicator.stopAnimating()
        view.isUserInteractionEnabled = true // Enable user interaction after loading
    }
    
    @objc func tap() {
        textView.resignFirstResponder()
    }
    
    func showTextInputAlert(for action: APIAction) {
        let textInputVC = TextInputViewController()
        textInputVC.textField.text = action.input
        textInputVC.didProvideInput = { [weak self] input in
            self?.handleInput(input, action: action)
        }
        present(textInputVC, animated: true, completion: nil)
    }
    
    private func handleInput(_ input: String, action: APIAction) {
        self.showLoader()
        switch action {
        case .addSegment:
            let segments = self.convertStringToArray(input: input)
            PushEngage.addSegments(segments) { [weak self] (result , error) in
                DispatchQueue.main.async {
                    self?.hideLoader()
                    if result {
                        self?.textView.text = "Subscriber added to segment successfully"
                    } else {
                        self?.textView.text = error?.localizedDescription
                    }
                }
            }
        case .removeSegment:
            let segments = self.convertStringToArray(input: input)
            PushEngage.removeSegments(segments) { [weak self] (result , error) in
                DispatchQueue.main.async {
                    self?.hideLoader()
                    if result {
                        self?.textView.text = "Subscriber removed from the segment(s)"
                    } else {
                        self?.textView.text = error?.localizedDescription
                    }
                }
            }
        case .addDynamicSegment:
            let segments = input.convertStringToDictionary()
            PushEngage.addDynamicSegments([segments]) { [weak self] (response, error) in
                DispatchQueue.main.async {
                    self?.hideLoader()
                    if response {
                        self?.textView.text = "Subscriber added to the dynamic segment successfully"
                    } else {
                        self?.textView.text = error?.localizedDescription
                    }
                }
            }
        case .addAttribute:
            let attributes = input.convertStringToDictionary()
            
            PushEngage.add(attributes: attributes) { [weak self] (response, error) in
                DispatchQueue.main.async {
                    self?.hideLoader()
                    if response {
                        self?.textView.text = "Attribute(s) updated for subscriber successfully"
                    } else {
                        self?.textView.text = error?.localizedDescription
                    }
                }
            }
        case .deleteAttribute:
            let attributes = self.convertStringToArray(input: input)
            PushEngage.deleteSubscriberAttributes(for: attributes) { [weak self] (response, error) in
                DispatchQueue.main.async {
                    self?.hideLoader()
                    if response {
                        self?.textView.text = "Attribute(s) deleted for subscriber successfully"
                    } else {
                        self?.textView.text = error?.localizedDescription
                    }
                }
            }
        case .setAttribute:
            let attributes = input.convertStringToDictionary()
            
            PushEngage.set(attributes: attributes) { [weak self] (response, error) in
                DispatchQueue.main.async {
                    self?.hideLoader()
                    if response {
                        self?.textView.text = "Attribute(s) set for subscriber successfully"
                    } else {
                        self?.textView.text = error?.localizedDescription
                    }
                }
            }
        case .addProfileId:
            PushEngage.addProfile(for: input) { [weak self] (result , error) in
                DispatchQueue.main.async {
                    self?.hideLoader()
                    if result {
                        self?.textView.text = "Profile ID added successfully"
                    } else {
                        self?.textView.text = error?.localizedDescription
                    }
                }
            }
        default:
            self.hideLoader()
            break
        }
    }
    
    func convertStringToArray(input: String) -> [String] {
        return input.components(separatedBy: ",")
    }
}

extension PushEngageViewController: UITableViewDelegate , UITableViewDataSource {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return actions.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.textLabel?.font = .boldSystemFont(ofSize: 18)
        cell.textLabel?.text = actions[indexPath.row]
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let action = APIAction(rawValue: indexPath.row)
        switch action {
        case .addAttribute:
            showTextInputAlert(for: .addAttribute)
        case .addDynamicSegment:
            showTextInputAlert(for: .addDynamicSegment)
        case .addSegment:
            showTextInputAlert(for: .addSegment)
        case .deleteAttribute:
            showTextInputAlert(for: .deleteAttribute)
        case .removeSegment:
            showTextInputAlert(for: .removeSegment)
        case .addProfileId:
            showTextInputAlert(for: .addProfileId)
        case .getSubscriberDetails:
            self.showLoader()
            PushEngage.getSubscriberDetails(for: nil) { [weak self] (response, error) in
                DispatchQueue.main.async {
                    self?.hideLoader()
                    if let value = response {
                        let responseString = "device: \(value.device ?? ""), user_agent: \(value.userAgent ?? ""), country: \(value.country ?? ""), ts_created: \(value.tsCreated ?? ""), state: \(value.state ?? ""), city: \(value.city ?? ""), host: \(value.host ?? ""), device_type: \(value.deviceType ?? ""), timezone: \(value.timezone ?? ""), segments: \(value.segments ?? []), profile_id: \(value.profileId ?? "")"
                        self?.textView.text = responseString
                    } else {
                        self?.textView.text = error?.localizedDescription
                    }
                }
            }
        case .getAttribute:
            self.showLoader()
            PushEngage.getSubscriberAttributes { [weak self] (info, error) in
                DispatchQueue.main.async {
                    self?.hideLoader()
                    if let value = info {
                        self?.textView.text = "\(value)"
                    } else {
                        self?.textView.text = error?.localizedDescription
                    }
                }
            }
        case .setAttribute:
            showTextInputAlert(for: .setAttribute)
        case .sendGoal:
            self.navigationController?.pushViewController(GoalViewController(), animated: true)
        case .triggerCampaigns:
            self.navigationController?.pushViewController(TriggerViewController(), animated: true)
        case .none:
            break
        }
    }
}



