//
//  HomeViewController.swift
//  PushEngageExample
//
//  Created by Himshikhar Gayan on 12/02/24.
//
//  Layout mirrors the Android demo (PR #37) but in iOS-native idioms:
//    - Inset-grouped UITableView with sectioned actions
//    - tableHeaderView showing the current environment chip + App ID
//    - Collapsible event log panel pinned to the bottom safe area
//

import UIKit
import PushEngage

// MARK: - Action model

enum APIAction {
    case addSegment
    case removeSegment
    case addDynamicSegment
    case addAttribute
    case deleteAttribute
    case addProfileId
    case getSubscriberDetails
    case getSubscriberId
    case getAttribute
    case setAttribute
    case sendGoal
    case triggerCampaigns
    case getSubscriptionStatus
    case getSubscriptionNotificationStatus
    case checkPermissionStatus
    case unsubscribe
    case subscribe
    case trackEvent
    case identify
    case logout
    case requestNotificationPermission

    var title: String {
        switch self {
        case .addSegment: return "Add Segment"
        case .removeSegment: return "Remove Segments"
        case .addDynamicSegment: return "Add Dynamic Segments"
        case .addAttribute: return "Add Subscriber Attributes"
        case .deleteAttribute: return "Delete Attributes"
        case .addProfileId: return "Add Profile Id"
        case .getSubscriberDetails: return "Get Subscriber Details"
        case .getSubscriberId: return "Get Subscriber ID"
        case .getAttribute: return "Get Subscriber Attributes"
        case .setAttribute: return "Set Subscriber Attributes"
        case .sendGoal: return "Send Goal"
        case .triggerCampaigns: return "Trigger Campaigns"
        case .getSubscriptionStatus: return "Get Subscription Status"
        case .getSubscriptionNotificationStatus: return "Get Notification Status"
        case .checkPermissionStatus: return "Check Permission Status"
        case .unsubscribe: return "Unsubscribe"
        case .subscribe: return "Subscribe"
        case .trackEvent: return "Track Event"
        case .identify: return "Identify"
        case .logout: return "Logout"
        case .requestNotificationPermission: return "Request Notification Permission"
        }
    }

    /// Pre-filled text shown in the input dialog. `nil` means the action takes
    /// no input and runs immediately on tap.
    var input: String? {
        switch self {
        case .addSegment, .removeSegment:
            return "ios"
        case .addDynamicSegment:
            return "name: ios, duration: 7"
        case .addAttribute:
            return "name: PushEngage, movies: false"
        case .deleteAttribute:
            return "name"
        case .setAttribute:
            return "name: PushEngage Sample"
        case .addProfileId:
            return "test@gmail.com"
        case .identify:
            return "email: test@example.com, first_name: Alice, profile_id: user-42"
        case .logout:
            // Empty input → default PII set; otherwise comma-separated field names.
            return "email, profile_id"
        case .getSubscriberDetails:
            // Empty input → fetch all fields; otherwise comma-separated field names.
            return ""
        case .getSubscriberId, .getAttribute,
             .getSubscriptionStatus, .getSubscriptionNotificationStatus,
             .checkPermissionStatus, .unsubscribe, .subscribe,
             .sendGoal, .triggerCampaigns, .trackEvent,
             .requestNotificationPermission:
            return nil
        }
    }

    /// Hint subtitle shown under the input sheet's title (matches Android's
    /// `bottom_sheet_request.xml` "Enter attributes as key value pairs" line).
    var hint: String? {
        switch self {
        case .addSegment, .removeSegment:
            return "Comma-separated segment names."
        case .addDynamicSegment:
            return "Enter as key: value pairs, separated by commas."
        case .addAttribute, .setAttribute:
            return "Enter attributes as key: value pairs, separated by commas."
        case .deleteAttribute:
            return "Comma-separated attribute keys to remove."
        case .addProfileId:
            return "Subscriber profile identifier (e.g. email)."
        case .identify:
            return "Identify the subscriber with one of the 12 supported fields. " +
                   "Format: key: value, key: value"
        case .logout:
            return "Comma-separated field names to clear. Leave empty to clear the default PII set."
        case .getSubscriberDetails:
            return "Comma-separated field names to fetch. Leave empty for all fields."
        default:
            return nil
        }
    }
}

private struct ActionSection {
    let title: String
    let actions: [APIAction]
}

// MARK: - HomeViewController

class HomeViewController: UIViewController {

    // Section structure mirrors the Android demo's collapsible groups.
    private let sections: [ActionSection] = [
        ActionSection(title: "Permissions", actions: [
            .requestNotificationPermission,
            .checkPermissionStatus
        ]),
        ActionSection(title: "Subscription", actions: [
            .subscribe,
            .unsubscribe,
            .getSubscriptionStatus,
            .getSubscriptionNotificationStatus,
            .getSubscriberId
        ]),
        ActionSection(title: "Profile & Attributes", actions: [
            .addProfileId,
            .getSubscriberDetails,
            .getAttribute,
            .addAttribute,
            .setAttribute,
            .deleteAttribute,
            .identify,
            .logout
        ]),
        ActionSection(title: "Segments", actions: [
            .addSegment,
            .removeSegment,
            .addDynamicSegment
        ]),
        ActionSection(title: "Goals & Events", actions: [
            .sendGoal,
            .trackEvent
        ]),
        ActionSection(title: "Triggers", actions: [
            .triggerCampaigns
        ])
    ]

    // MARK: - Subviews

    private let tableView: UITableView = {
        if #available(iOS 13.0, *) {
            return UITableView(frame: .zero, style: .insetGrouped)
        } else {
            return UITableView(frame: .zero, style: .grouped)
        }
    }()
    private let eventLog = EventLogPanel()
    private let activityIndicator: UIActivityIndicatorView = {
        let style: UIActivityIndicatorView.Style
        if #available(iOS 13.0, *) { style = .medium } else { style = .gray }
        let indicator = UIActivityIndicatorView(style: style)
        indicator.color = .systemRed
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    private var eventLogHeightConstraint: NSLayoutConstraint!

    // Config card lives in the table header — refreshed on view appear.
    private let configCard = ConfigCardView()

    // MARK: - Lifecycle

    override func loadView() {
        // Programmatic root — supersedes the legacy HomeViewController.xib.
        view = UIView()
        if #available(iOS 13.0, *) {
            view.backgroundColor = .systemGroupedBackground
        } else {
            view.backgroundColor = UIColor(white: 0.95, alpha: 1)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "PushEngage Demo"
        setupTableView()
        setupEventLogPanel()
        setupActivityIndicator()
        setupSettingsBarButton()
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }

    private func setupSettingsBarButton() {
        let item: UIBarButtonItem
        if #available(iOS 13.0, *) {
            item = UIBarButtonItem(
                image: UIImage(systemName: "gearshape"),
                style: .plain,
                target: self,
                action: #selector(openSettings)
            )
        } else {
            item = UIBarButtonItem(
                title: "Settings",
                style: .plain,
                target: self,
                action: #selector(openSettings)
            )
        }
        navigationItem.rightBarButtonItem = item
    }

    @objc private func openSettings() {
        let settings = SettingsViewController()
        let nav = UINavigationController(rootViewController: settings)
        present(nav, animated: true)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshConfigCard()
    }

    // MARK: - Setup

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.tableHeaderView = configCard.makeWrapped(width: UIScreen.main.bounds.width)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func setupEventLogPanel() {
        eventLog.translatesAutoresizingMaskIntoConstraints = false
        eventLog.onToggle = { [weak self] expanded in
            self?.eventLogHeightConstraint.constant = expanded ? 220 : 44
            UIView.animate(withDuration: 0.2) { self?.view.layoutIfNeeded() }
        }
        view.addSubview(eventLog)

        eventLogHeightConstraint = eventLog.heightAnchor.constraint(equalToConstant: 44)
        NSLayoutConstraint.activate([
            eventLog.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            eventLog.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            eventLog.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            eventLogHeightConstraint,
            tableView.bottomAnchor.constraint(equalTo: eventLog.topAnchor)
        ])
    }

    private func setupActivityIndicator() {
        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func refreshConfigCard() {
        // Both the environment chip and the App ID slot are sourced from
        // `DemoPrefs` so they reflect what the user picked in
        // SettingsViewController — even after a force-quit/relaunch.
        let envText = (DemoPrefs.shared.environment == .staging) ? "STAGING" : "PRODUCTION"
        let appId = DemoPrefs.shared.appId.isEmpty ? "(not configured)" : DemoPrefs.shared.appId
        configCard.update(environment: envText, appId: appId)
    }

    // MARK: - Helpers

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    private func showLoader() {
        activityIndicator.startAnimating()
        view.isUserInteractionEnabled = false
    }

    private func hideLoader() {
        activityIndicator.stopAnimating()
        view.isUserInteractionEnabled = true
    }

    // MARK: - Action dispatch

    private func perform(action: APIAction) {
        if let prefill = action.input {
            // Action takes user input — show the text-input sheet.
            let textInputVC = TextInputViewController()
            textInputVC.promptTitle = action.title
            textInputVC.hint = action.hint
            textInputVC.prefilledText = prefill
            textInputVC.didProvideInput = { [weak self] input in
                self?.handleInput(input, action: action)
            }
            present(textInputVC, animated: true)
        } else {
            handleInput("", action: action)
        }
    }

    /// Dispatches the call and appends a result entry to the event log.
    /// All UI updates happen on the main queue.
    private func handleInput(_ input: String, action: APIAction) {
        showLoader()
        let actionTitle = action.title

        switch action {
        case .requestNotificationPermission:
            PushEngage.requestNotificationPermission { [weak self] response, error in
                self?.finish(actionTitle, success: response, error: error,
                             okMessage: "Notification permission granted",
                             failMessage: "Notification permission denied")
            }
        case .checkPermissionStatus:
            let permissionStatus = PushEngage.getNotificationPermissionStatus()
            hideLoader()
            log("\(actionTitle): \(permissionStatus.uppercased())")
            showResponseSheet(title: actionTitle, payload: permissionStatus.uppercased())
        case .subscribe:
            PushEngage.subscribe { [weak self] response, error in
                self?.finish(actionTitle, success: response, error: error,
                             okMessage: "Subscribed",
                             failMessage: "Subscribe failed")
            }
        case .unsubscribe:
            PushEngage.unsubscribe { [weak self] response, error in
                self?.finish(actionTitle, success: response, error: error,
                             okMessage: "Unsubscribed",
                             failMessage: "Unsubscribe failed")
            }
        case .getSubscriptionStatus:
            PushEngage.getSubscriptionStatus { [weak self] isSubscribed, error in
                self?.finishCustom(actionTitle, error: error) {
                    isSubscribed ? "Subscribed to push notifications"
                                 : "Unsubscribed from push notifications"
                }
            }
        case .getSubscriptionNotificationStatus:
            PushEngage.getSubscriptionNotificationStatus { [weak self] canReceive, error in
                self?.finishCustom(actionTitle, error: error) {
                    canReceive ? "Can receive push notifications"
                               : "Cannot receive push notifications"
                }
            }
        case .getSubscriberId:
            PushEngage.getSubscriberId { [weak self] response in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.hideLoader()
                    let display = response ?? "(no subscriber)"
                    self.log("\(actionTitle): \(display)")
                    self.showResponseSheet(title: actionTitle, payload: display)
                }
            }
        case .addProfileId:
            PushEngage.addProfile(for: input) { [weak self] result, error in
                self?.finish(actionTitle, success: result, error: error,
                             okMessage: "Profile ID '\(input)' added",
                             failMessage: "Add profile failed")
            }
        case .getSubscriberDetails:
            let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
            let keys: [String]? = trimmed.isEmpty
                ? nil
                : trimmed.split(separator: ",")
                         .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                         .filter { !$0.isEmpty }
            PushEngage.getSubscriberDetails(for: keys) { [weak self] response, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.hideLoader()
                    if let value = response {
                        let raw = value.rawFields
                        let summary = "country=\(raw["country"] as? String ?? "-"), city=\(raw["city"] as? String ?? "-"), tz=\(raw["timezone"] as? String ?? "-"), profile_id=\(raw["profile_id"] as? String ?? "-")"
                        self.log("\(actionTitle): \(summary)")
                        // Display whatever the server returned, snake_case keys
                        // as-is. `rawFields` includes fields not modeled on the
                        // SDK type (e.g. identify-API fields like email,
                        // first_name) — forward-compatible across future
                        // backend additions.
                        self.showResponseSheet(title: actionTitle, payload: value.rawFields)
                    } else {
                        let msg = error?.localizedDescription ?? "unknown error"
                        self.log("\(actionTitle) FAILED: \(msg)")
                        self.showResponseSheet(title: "\(actionTitle) — failed", payload: msg)
                    }
                }
            }
        case .getAttribute:
            PushEngage.getSubscriberAttributes { [weak self] info, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.hideLoader()
                    if let value = info {
                        self.log("\(actionTitle): \(value)")
                        self.showResponseSheet(title: actionTitle, payload: value)
                    } else {
                        let msg = error?.localizedDescription ?? "unknown error"
                        self.log("\(actionTitle) FAILED: \(msg)")
                        self.showResponseSheet(title: "\(actionTitle) — failed", payload: msg)
                    }
                }
            }
        case .addAttribute:
            let attributes = input.convertStringToDictionary()
            PushEngage.addSubscriberAttributes(attributes) { [weak self] response, error in
                self?.finish(actionTitle, success: response, error: error,
                             okMessage: "Attributes added: \(attributes)",
                             failMessage: "Add attributes failed")
            }
        case .setAttribute:
            let attributes = input.convertStringToDictionary()
            PushEngage.setSubscriberAttributes(attributes) { [weak self] response, error in
                self?.finish(actionTitle, success: response, error: error,
                             okMessage: "Attributes set: \(attributes)",
                             failMessage: "Set attributes failed")
            }
        case .deleteAttribute:
            let attributes = convertStringToArray(input: input)
            PushEngage.deleteSubscriberAttributes(for: attributes) { [weak self] response, error in
                self?.finish(actionTitle, success: response, error: error,
                             okMessage: "Attributes deleted: \(attributes)",
                             failMessage: "Delete attributes failed")
            }
        case .addSegment:
            let segments = convertStringToArray(input: input)
            PushEngage.addSegments(segments) { [weak self] result, error in
                self?.finish(actionTitle, success: result, error: error,
                             okMessage: "Added to segment(s): \(segments)",
                             failMessage: "Add segment failed")
            }
        case .removeSegment:
            let segments = convertStringToArray(input: input)
            PushEngage.removeSegments(segments) { [weak self] result, error in
                self?.finish(actionTitle, success: result, error: error,
                             okMessage: "Removed from segment(s): \(segments)",
                             failMessage: "Remove segment failed")
            }
        case .addDynamicSegment:
            let segments = input.convertStringToDictionary()
            PushEngage.addDynamicSegments([segments]) { [weak self] response, error in
                self?.finish(actionTitle, success: response, error: error,
                             okMessage: "Dynamic segment added: \(segments)",
                             failMessage: "Add dynamic segment failed")
            }
        case .sendGoal:
            hideLoader()
            navigationController?.pushViewController(GoalViewController(), animated: true)
        case .triggerCampaigns:
            hideLoader()
            navigationController?.pushViewController(TriggerViewController(), animated: true)
        case .trackEvent:
            hideLoader()
            navigationController?.pushViewController(TrackEventViewController(), animated: true)
        case .identify:
            let fields = input.convertStringToDictionary()
            PushEngage.identify(fields: fields) { [weak self] response, error in
                self?.finish(actionTitle, success: response, error: error,
                             okMessage: "Identified with: \(fields)",
                             failMessage: "Identify failed")
            }
        case .logout:
            let trimmed = input.trimmingCharacters(in: .whitespaces)
            let fieldNames: [String]? = trimmed.isEmpty
                ? nil
                : convertStringToArray(input: trimmed).map { $0.trimmingCharacters(in: .whitespaces) }
            PushEngage.logout(fieldNames: fieldNames) { [weak self] response, error in
                let label = fieldNames.map { "\($0)" } ?? "default PII set"
                self?.finish(actionTitle, success: response, error: error,
                             okMessage: "Logged out fields: \(label)",
                             failMessage: "Logout failed")
            }
        }
    }

    // MARK: - Result helpers

    private func finish(_ actionTitle: String,
                        success: Bool,
                        error: Error?,
                        okMessage: String,
                        failMessage: String,
                        responsePayload: Any? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.hideLoader()
            if success {
                self.log("\(actionTitle) OK: \(okMessage)")
                self.showResponseSheet(title: "\(actionTitle) — success",
                                       payload: responsePayload ?? okMessage)
            } else {
                let detail = error?.localizedDescription ?? failMessage
                self.log("\(actionTitle) FAILED: \(detail)")
                self.showResponseSheet(title: "\(actionTitle) — failed",
                                       payload: detail)
            }
        }
    }

    private func finishCustom(_ actionTitle: String,
                              error: Error?,
                              messageProvider: () -> String) {
        let msg = messageProvider()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.hideLoader()
            if let err = error {
                self.log("\(actionTitle) FAILED: \(err.localizedDescription)")
                self.showResponseSheet(title: "\(actionTitle) — failed",
                                       payload: err.localizedDescription)
            } else {
                self.log("\(actionTitle) OK: \(msg)")
                self.showResponseSheet(title: "\(actionTitle) — success",
                                       payload: msg)
            }
        }
    }

    private func log(_ message: String) {
        SdkEventLog.shared.append(message)
        // The panel observes the shared log directly — no per-call append needed.
    }

    private func convertStringToArray(input: String) -> [String] {
        input.components(separatedBy: ",")
    }
}

// MARK: - UITableViewDelegate / UITableViewDataSource

extension HomeViewController: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].actions.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].title
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let action = sections[indexPath.section].actions[indexPath.row]
        cell.textLabel?.text = action.title
        cell.textLabel?.font = .systemFont(ofSize: 16, weight: .regular)
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let action = sections[indexPath.section].actions[indexPath.row]
        perform(action: action)
    }
}

// MARK: - Config card

private final class ConfigCardView: UIView {

    private let envLabel: UILabel = {
        let l = UILabel()
        l.text = "ENVIRONMENT"
        l.font = .systemFont(ofSize: 10, weight: .bold)
        l.textColor = DemoColor.secondaryLabel
        return l
    }()
    private let envChip: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 11, weight: .bold)
        l.textColor = .white
        l.backgroundColor = .systemBlue
        l.textAlignment = .center
        l.layer.cornerRadius = 4
        l.layer.masksToBounds = true
        return l
    }()
    private let appIdLabel: UILabel = {
        let l = UILabel()
        l.text = "APP ID"
        l.font = .systemFont(ofSize: 10, weight: .bold)
        l.textColor = DemoColor.secondaryLabel
        return l
    }()
    private let appIdValue: UILabel = {
        let l = UILabel()
        l.font = UIFont(name: "Menlo", size: 13) ?? .systemFont(ofSize: 13)
        l.textColor = DemoColor.primaryLabel
        l.numberOfLines = 1
        l.lineBreakMode = .byTruncatingMiddle
        return l
    }()
    private let cardContainer: UIView = {
        let v = UIView()
        v.backgroundColor = DemoColor.cardBackground
        v.layer.cornerRadius = 10
        v.layer.borderColor = DemoColor.separator.cgColor
        v.layer.borderWidth = 1
        return v
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(cardContainer)
        [envLabel, envChip, appIdLabel, appIdValue].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            cardContainer.addSubview($0)
        }
        cardContainer.translatesAutoresizingMaskIntoConstraints = false

        // The closing (bottom/trailing) edges yield at 999 so the throwaway
        // 0×1 tableHeaderView measuring pass in `makeWrapped` has a legal
        // solution; in the real layout nothing competes with them.
        NSLayoutConstraint.activate([
            cardContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            almostRequired(cardContainer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20)),
            cardContainer.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            almostRequired(cardContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)),

            envLabel.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: 14),
            envLabel.topAnchor.constraint(equalTo: cardContainer.topAnchor, constant: 14),

            envChip.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -14),
            envChip.centerYAnchor.constraint(equalTo: envLabel.centerYAnchor),
            envChip.widthAnchor.constraint(greaterThanOrEqualToConstant: 70),
            envChip.heightAnchor.constraint(equalToConstant: 22),

            appIdLabel.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: 14),
            appIdLabel.topAnchor.constraint(equalTo: envLabel.bottomAnchor, constant: 16),

            appIdValue.leadingAnchor.constraint(equalTo: cardContainer.leadingAnchor, constant: 14),
            almostRequired(appIdValue.trailingAnchor.constraint(equalTo: cardContainer.trailingAnchor, constant: -14)),
            appIdValue.topAnchor.constraint(equalTo: appIdLabel.bottomAnchor, constant: 4),
            almostRequired(appIdValue.bottomAnchor.constraint(equalTo: cardContainer.bottomAnchor, constant: -14))
        ])
    }

    private func almostRequired(_ constraint: NSLayoutConstraint) -> NSLayoutConstraint {
        constraint.priority = UILayoutPriority(999)
        return constraint
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func update(environment: String, appId: String) {
        envChip.text = "  \(environment)  "
        appIdValue.text = appId
    }

    /// Wraps the card in a fixed-width container suitable for use as a
    /// UITableView.tableHeaderView. Auto Layout doesn't size a tableHeaderView
    /// automatically, so the container must have a known height computed up-front.
    func makeWrapped(width: CGFloat) -> UIView {
        update(environment: "—", appId: "—") // placeholder until first refresh
        translatesAutoresizingMaskIntoConstraints = false
        let wrapper = UIView(frame: CGRect(x: 0, y: 0, width: width, height: 1))
        wrapper.addSubview(self)
        NSLayoutConstraint.activate([
            leadingAnchor.constraint(equalTo: wrapper.leadingAnchor),
            trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            topAnchor.constraint(equalTo: wrapper.topAnchor),
            bottomAnchor.constraint(equalTo: wrapper.bottomAnchor)
        ])
        // Force layout so wrapper picks up an intrinsic height.
        wrapper.setNeedsLayout()
        wrapper.layoutIfNeeded()
        let height = systemLayoutSizeFitting(
            CGSize(width: width, height: UIView.layoutFittingCompressedSize.height)
        ).height
        wrapper.frame.size.height = height
        return wrapper
    }
}

// MARK: - Event log panel

/// Collapsible bottom panel that observes `SdkEventLog.shared` and renders
/// every entry in monospace. Tap header to expand/collapse, "Clear" button
/// wipes the shared log (and therefore the panel) globally.
private final class EventLogPanel: UIView {

    var onToggle: ((Bool) -> Void)?
    private(set) var isExpanded = false

    private let header: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(red: 42/255, green: 42/255, blue: 42/255, alpha: 1)
        return v
    }()
    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "Event log (0)"
        l.font = .systemFont(ofSize: 13, weight: .bold)
        l.textColor = .white
        return l
    }()
    private let clearButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("Clear", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 12, weight: .regular)
        b.setTitleColor(.white, for: .normal)
        return b
    }()
    private let chevron: UILabel = {
        let l = UILabel()
        l.text = "▲"
        l.font = .systemFont(ofSize: 14)
        l.textColor = .white
        return l
    }()
    private let textView: UITextView = {
        let tv = UITextView()
        tv.backgroundColor = UIColor(red: 30/255, green: 30/255, blue: 30/255, alpha: 1)
        tv.textColor = .white
        tv.font = UIFont(name: "Menlo", size: 11) ?? .systemFont(ofSize: 11)
        tv.isEditable = false
        tv.isSelectable = true
        tv.alwaysBounceVertical = true
        return tv
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(red: 30/255, green: 30/255, blue: 30/255, alpha: 1)
        [header, textView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        [titleLabel, clearButton, chevron].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview($0)
        }
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.topAnchor.constraint(equalTo: topAnchor),
            header.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            chevron.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -12),
            chevron.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            clearButton.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -8),
            clearButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            textView.topAnchor.constraint(equalTo: header.bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(toggle))
        header.addGestureRecognizer(tap)
        clearButton.addTarget(self, action: #selector(clear), for: .touchUpInside)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshFromSharedLog),
            name: .sdkEventLogDidChange,
            object: nil
        )

        // Start collapsed.
        textView.isHidden = true
        chevron.text = "▲"
        refreshFromSharedLog()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func refreshFromSharedLog() {
        let entries = SdkEventLog.shared.entries
        textView.text = entries.joined(separator: "\n")
        titleLabel.text = "Event log (\(entries.count))"
        if isExpanded { scrollToBottom() }
    }

    @objc private func toggle() {
        isExpanded.toggle()
        textView.isHidden = !isExpanded
        chevron.text = isExpanded ? "▼" : "▲"
        onToggle?(isExpanded)
        if isExpanded { scrollToBottom() }
    }

    @objc private func clear() {
        SdkEventLog.shared.clear()
    }

    private func scrollToBottom() {
        let bottom = NSRange(location: (textView.text ?? "").count, length: 0)
        textView.scrollRangeToVisible(bottom)
    }
}

// MARK: - Color helpers with iOS 12 fallbacks
//
// Project deploys to iOS 12 but the dynamic-color/semantic-color APIs landed
// in iOS 13. Centralize the version checks here so the rest of the file
// reads naturally.

private enum DemoColor {
    static var primaryLabel: UIColor {
        if #available(iOS 13.0, *) { return .label }
        return .black
    }
    static var secondaryLabel: UIColor {
        if #available(iOS 13.0, *) { return .secondaryLabel }
        return UIColor(white: 0.45, alpha: 1)
    }
    static var separator: UIColor {
        if #available(iOS 13.0, *) { return .separator }
        return UIColor(white: 0.78, alpha: 1)
    }
    static var cardBackground: UIColor {
        if #available(iOS 13.0, *) { return .secondarySystemGroupedBackground }
        return .white
    }
}
