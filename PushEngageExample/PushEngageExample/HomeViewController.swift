//
//  HomeViewController.swift
//  PushEngageExample
//
//  Created by Himshikhar Gayan on 12/02/24.
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
    case getSubscriberId = 7
    case getAttribute = 8
    case setAttribute = 9
    case sendGoal = 10
    case triggerCampaigns = 11
    case getSubscriptionStatus = 12
    case getSubscriptionNotificationStatus = 13
    case checkPermissionStatus = 14
    case unsubscribe = 15
    case subscribe = 16
    
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
        case .getSubscriberDetails, .getSubscriberId, .getAttribute, .getSubscriptionStatus, .getSubscriptionNotificationStatus, .checkPermissionStatus, .unsubscribe, .subscribe:
            return nil
        case .addProfileId:
            return "test@gmail.com"
        case .sendGoal, .triggerCampaigns:
            return ""
        }
    }
}

class HomeViewController: UIViewController {
    
    @IBOutlet weak var notificationRequestButton: UIButton!
    // Removed unused IBOutlets for permission status and unsubscribe buttons
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var resultTextView: UITextView!
    
    private let activityIndicator: UIActivityIndicatorView = {
        if #available(iOSApplicationExtension 13.0, *) {
            let indicator = UIActivityIndicatorView(style: .gray)
            indicator.color = .red
            indicator.translatesAutoresizingMaskIntoConstraints = false
            return indicator
        } else {
            let indicator = UIActivityIndicatorView(style: .gray)
            indicator.translatesAutoresizingMaskIntoConstraints = false
            return indicator       
        }
    }()
    
    let actions = ["Add Segment",
                   "Remove Segments",
                   "Add Dynamic Segments",
                   "Add Subscriber Attributes",
                   "Delete Attributes",
                   "Add Profile Id",
                   "Get Subscriber Details",
                   "Get Subscriber ID",
                   "Get Subscriber Attributes",
                   "Set Subscriber Attributes",
                   "Send Goal",
                   "Trigger Campaigns",
                   "Get Subscription Status",
                   "Get Notification Status",
                   "Check Permission Status",
                   "Unsubscribe",
                   "Subscribe"]
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.setupUI()
    }
    
    private func setupUI() {
        navigationItem.title = "PushEngage Demo"
        resultTextView.text = nil
        resultTextView.layer.cornerRadius = 12
        tableView.delegate = self
        tableView.dataSource = self
        self.tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        let gesture = UITapGestureRecognizer(target: self, action: #selector(tap))
        gesture.cancelsTouchesInView = false
        view.addGestureRecognizer(gesture)
        
        view.addSubview(activityIndicator)
        
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        
        super.viewDidLoad()
        
        notificationRequestButton.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(requestNotificationPermission)))
        // Removed gesture recognizers for permission status and unsubscribe buttons since they're now in the table view
    }

    
    @objc private func requestNotificationPermission() {
        PushEngage.requestNotificationPermission { [weak self] response, error in
            DispatchQueue.main.async {
                if let error = error {
                    let errorMessage = "Error requesting notification permission: \(error.localizedDescription)"
                    self?.resultTextView.text = errorMessage
                } else if response {
                    let successMessage = "Notification permission granted successfully!"
                    self?.resultTextView.text = successMessage
                } else {
                    let deniedMessage = "Notification permission denied by user"
                    self?.resultTextView.text = deniedMessage
                }
            }
        }
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
        resultTextView.resignFirstResponder()
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
                        self?.resultTextView.text = "Subscriber added to segment successfully"
                    } else {
                        self?.resultTextView.text = error?.localizedDescription
                    }
                }
            }
        case .removeSegment:
            let segments = self.convertStringToArray(input: input)
            PushEngage.removeSegments(segments) { [weak self] (result , error) in
                DispatchQueue.main.async {
                    self?.hideLoader()
                    if result {
                        self?.resultTextView.text = "Subscriber removed from the segment(s)"
                    } else {
                        self?.resultTextView.text = error?.localizedDescription
                    }
                }
            }
        case .addDynamicSegment:
            let segments = input.convertStringToDictionary()
            PushEngage.addDynamicSegments([segments]) { [weak self] (response, error) in
                DispatchQueue.main.async {
                    self?.hideLoader()
                    if response {
                        self?.resultTextView.text = "Subscriber added to the dynamic segment successfully"
                    } else {
                        self?.resultTextView.text = error?.localizedDescription
                    }
                }
            }
        case .addAttribute:
            let attributes = input.convertStringToDictionary()
            
            PushEngage.add(attributes: attributes) { [weak self] (response, error) in
                DispatchQueue.main.async {
                    self?.hideLoader()
                    if response {
                        self?.resultTextView.text = "Attribute(s) updated for subscriber successfully"
                    } else {
                        self?.resultTextView.text = error?.localizedDescription
                    }
                }
            }
        case .deleteAttribute:
            let attributes = self.convertStringToArray(input: input)
            PushEngage.deleteSubscriberAttributes(for: attributes) { [weak self] (response, error) in
                DispatchQueue.main.async {
                    self?.hideLoader()
                    if response {
                        self?.resultTextView.text = "Attribute(s) deleted for subscriber successfully"
                    } else {
                        self?.resultTextView.text = error?.localizedDescription
                    }
                }
            }
        case .setAttribute:
            let attributes = input.convertStringToDictionary()
            
            PushEngage.set(attributes: attributes) { [weak self] (response, error) in
                DispatchQueue.main.async {
                    self?.hideLoader()
                    if response {
                        self?.resultTextView.text = "Attribute(s) set for subscriber successfully"
                    } else {
                        self?.resultTextView.text = error?.localizedDescription
                    }
                }
            }
        case .addProfileId:
            PushEngage.addProfile(for: input) { [weak self] (result , error) in
                DispatchQueue.main.async {
                    self?.hideLoader()
                    if result {
                        self?.resultTextView.text = "Profile ID added successfully"
                    } else {
                        self?.resultTextView.text = error?.localizedDescription
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

extension HomeViewController: UITableViewDelegate , UITableViewDataSource {
    
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
                        let responseString = """
                        device: \(value.device ?? ""),
                        user_agent: \(value.userAgent ?? ""),
                        country: \(value.country ?? ""),
                        ts_created: \(value.tsCreated ?? ""),
                        state: \(value.state ?? ""),
                        city: \(value.city ?? ""),
                        host: \(value.host ?? ""),
                        device_type: \(value.deviceType ?? ""),
                        timezone: \(value.timezone ?? ""),
                        segments: \(value.segments ?? []),
                        profile_id: \(value.profileId ?? "")
                        """

                        self?.resultTextView.text = responseString
                    } else {
                        self?.resultTextView.text = error?.localizedDescription
                    }
                }
            }
        case .getSubscriberId:
            PushEngage.getSubscriberId { response in
                DispatchQueue.main.async { [weak self] in
                    if let subscriberId = response {
                        self?.resultTextView.text = "Subscriber ID: \(subscriberId)"
                    } else {
                        self?.resultTextView.text = "User is not subscribed (no subscriber ID available)"
                    }
                }
            }
        case .getAttribute:
            self.showLoader()
            PushEngage.getSubscriberAttributes { [weak self] (info, error) in
                DispatchQueue.main.async {
                    self?.hideLoader()
                    if let value = info {
                        self?.resultTextView.text = "\(value)"
                    } else {
                        self?.resultTextView.text = error?.localizedDescription
                    }
                }
            }
        case .setAttribute:
            showTextInputAlert(for: .setAttribute)
        case .sendGoal:
            self.navigationController?.pushViewController(GoalViewController(), animated: true)
        case .triggerCampaigns:
            self.navigationController?.pushViewController(TriggerViewController(), animated: true)
        case .getSubscriptionStatus:
            self.showLoader()
            PushEngage.getSubscriptionStatus { [weak self] (isSubscribed, error) in
                DispatchQueue.main.async {
                    self?.hideLoader()
                    if let error = error {
                        self?.resultTextView.text = "Error getting subscription status: \(error.localizedDescription)"
                    } else {
                        let message = """
                        The user is currently \(isSubscribed ? "subscribed to" : "unsubscribed from") push notifications.
                        """
                        self?.resultTextView.text = message
                    }
                }
            }
        case .getSubscriptionNotificationStatus:
            self.showLoader()
            PushEngage.getSubscriptionNotificationStatus { [weak self] (canReceiveNotifications, error) in
                DispatchQueue.main.async {
                    self?.hideLoader()
                    if let error = error {
                        self?.resultTextView.text = "Error getting notification status: \(error.localizedDescription)"
                    } else {
                        let statusText = canReceiveNotifications ? "CAN RECEIVE" : "CANNOT RECEIVE"
                        let message = """
                        The user \(canReceiveNotifications ? "can receive" : "cannot receive") push notifications.
                        """
                        self?.resultTextView.text = message
                    }
                }
            }
        case .checkPermissionStatus:
            let permissionStatus = PushEngage.getNotificationPermissionStatus()
            
            DispatchQueue.main.async { [weak self] in
                let statusMessage: String
                switch permissionStatus {
                case "granted":
                    statusMessage = "Notification permission status: GRANTED\nNotifications are allowed"
                case "denied":
                    statusMessage = "Notification permission status: DENIED\nNotifications are not allowed"
                case "notYetRequested":
                    statusMessage = "Notification permission status: NOT YET REQUESTED\nPermission has not been requested from the user"
                default:
                    statusMessage = "Unknown permission status: \(permissionStatus)"
                }
                self?.resultTextView.text = statusMessage
            }
        case .unsubscribe:
            self.showLoader()
            PushEngage.unsubscribe { [weak self] (response, error) in
                DispatchQueue.main.async {
                    self?.hideLoader()
                    if let error = error {
                        self?.resultTextView.text = "Error unsubscribing: \(error.localizedDescription)"
                    } else if response {
                        self?.resultTextView.text = "Successfully unsubscribed from push notifications\nYou will no longer receive notifications"
                    } else {
                        self?.resultTextView.text = "Failed to unsubscribe from push notifications"
                    }
                }
            }
        case .subscribe:
            self.showLoader()
            PushEngage.subscribe { [weak self] (response, error) in
                DispatchQueue.main.async {
                    self?.hideLoader()
                    if let error = error {
                        self?.resultTextView.text = "Error subscribing: \(error.localizedDescription)"
                    } else if response {
                        self?.resultTextView.text = "Successfully subscribed to push notifications\nYou will now receive notifications"
                    } else {
                        self?.resultTextView.text = "Failed to subscribe to push notifications"
                    }
                }
            }
        case .none:
            break
        }
    }
}
