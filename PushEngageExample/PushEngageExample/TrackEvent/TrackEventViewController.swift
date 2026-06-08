//
//  TrackEventViewController.swift
//  PushEngageExample
//
//  Mirrors the Android demo's `TrackEventActivity` — exposes all 5 fields of
//  the track-event API surface (eventName, provider, eventType, profileId,
//  data) so the same QA scenarios cover both platforms.
//

import UIKit
import PushEngage

class TrackEventViewController: UIViewController {

    private enum Row: Int, CaseIterable {
        case name
        case provider
        case eventType
        case profileId
        case data
    }

    private let tableView: UITableView = {
        if #available(iOS 13.0, *) {
            return UITableView(frame: .zero, style: .insetGrouped)
        } else {
            return UITableView(frame: .zero, style: .grouped)
        }
    }()
    private let snackbarView = SnackbarView(frame: CGRect(origin: .zero,
                                                          size: CGSize(width: 200, height: 50)))
    private let activityIndicator: UIActivityIndicatorView = {
        let style: UIActivityIndicatorView.Style
        if #available(iOS 13.0, *) { style = .medium } else { style = .gray }
        let indicator = UIActivityIndicatorView(style: style)
        indicator.color = .systemRed
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()

    private let nameField = makeTextField(placeholder: "Event name (required)", keyboardType: .default)
    private let providerField = makeTextField(placeholder: "Provider (optional, default \"PushEngage\")", keyboardType: .default)
    private let eventTypeField = makeTextField(placeholder: "Event type (optional, default \"PushEngage.CustomEvent\")", keyboardType: .default)
    private let profileIdField = makeTextField(placeholder: "Profile id (optional)", keyboardType: .default)
    private let dataField = makeTextField(placeholder: "Data — JSON object (optional)", keyboardType: .default)

    override func loadView() {
        view = UIView()
        if #available(iOS 13.0, *) {
            view.backgroundColor = .systemGroupedBackground
        } else {
            view.backgroundColor = UIColor(white: 0.95, alpha: 1)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Track Event"

        nameField.text = "MySite.AddToCart"
        dataField.text = "{\"amount\": 19.99, \"currency\": \"USD\", \"is_trial\": false, \"items\": 3}"

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .interactive
        view.addSubview(tableView)

        view.addSubview(snackbarView)
        snackbarView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            snackbarView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            snackbarView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            snackbarView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        snackbarView.isHidden = true

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    // MARK: - Actions

    @objc private func trackEventTapped() {
        let name = (nameField.text ?? "").trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            showSnackbar(message: "Event name is required", isSuccess: false)
            return
        }

        let provider = nonEmpty(providerField.text)
        let eventType = nonEmpty(eventTypeField.text)
        let profileId = nonEmpty(profileIdField.text)
        let properties = parseDataJSON(dataField.text)

        showLoader()
        let summary = "name=\(name), provider=\(provider ?? "-"), eventType=\(eventType ?? "-"), profileId=\(profileId ?? "-")"

        PushEngage.trackEvent(name: name,
                              properties: properties,
                              profileId: profileId,
                              provider: provider,
                              eventType: eventType) { [weak self] response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.hideLoader()
                if let err = error {
                    self.showSnackbar(message: "Failure: \(err.localizedDescription)", isSuccess: false)
                    SdkEventLog.shared.append("Track Event FAILED: \(err.localizedDescription)")
                    self.showResponseSheet(title: "Track Event — failed",
                                           payload: err.localizedDescription)
                } else if response {
                    self.showSnackbar(message: "Event tracked", isSuccess: true)
                    SdkEventLog.shared.append("Track Event OK: \(summary)")
                    let payload: [String: Any] = [
                        "name": name,
                        "provider": provider as Any,
                        "event_type": eventType as Any,
                        "profile_id": profileId as Any,
                        "properties": properties as Any
                    ]
                    self.showResponseSheet(title: "Track Event — success", payload: payload)
                } else {
                    self.showSnackbar(message: "Track event failed", isSuccess: false)
                    SdkEventLog.shared.append("Track Event FAILED: (no error)")
                    self.showResponseSheet(title: "Track Event — failed",
                                           payload: "(no error)")
                }
            }
        }
    }

    @objc private func dismissKeyboard() { view.endEditing(true) }

    private func showLoader() {
        activityIndicator.startAnimating()
        view.isUserInteractionEnabled = false
    }

    private func hideLoader() {
        activityIndicator.stopAnimating()
        view.isUserInteractionEnabled = true
    }

    private func showSnackbar(message: String, isSuccess: Bool) {
        snackbarView.setMessage(message, isSuccess: isSuccess)
        snackbarView.alpha = 0
        snackbarView.isHidden = false
        UIView.animate(withDuration: 0.5, animations: { self.snackbarView.alpha = 1 }) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                UIView.animate(withDuration: 0.5,
                               animations: { self.snackbarView.alpha = 0 }) { _ in
                    self.snackbarView.isHidden = true
                }
            }
        }
    }

    // MARK: - Helpers

    private func nonEmpty(_ text: String?) -> String? {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseDataJSON(_ text: String?) -> [String: Any]? {
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            showSnackbar(message: "Invalid JSON in Data — sending event without it", isSuccess: false)
            return nil
        }
        return obj
    }

    private static func makeTextField(placeholder: String, keyboardType: UIKeyboardType) -> UITextField {
        let f = UITextField()
        f.placeholder = placeholder
        f.keyboardType = keyboardType
        f.borderStyle = .none
        f.font = .systemFont(ofSize: 17)
        f.autocapitalizationType = .none
        f.autocorrectionType = .no
        f.translatesAutoresizingMaskIntoConstraints = false
        return f
    }
}

// MARK: - UITableViewDelegate / UITableViewDataSource

extension TrackEventViewController: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? Row.allCases.count : 1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Event details" : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.selectionStyle = .none
            let field: UITextField
            switch Row.allCases[indexPath.row] {
            case .name: field = nameField
            case .provider: field = providerField
            case .eventType: field = eventTypeField
            case .profileId: field = profileIdField
            case .data: field = dataField
            }
            cell.contentView.addSubview(field)
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                field.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                field.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 6),
                field.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -6),
                field.heightAnchor.constraint(greaterThanOrEqualToConstant: 32)
            ])
            return cell
        } else {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.selectionStyle = .default
            cell.textLabel?.text = "Track Event"
            cell.textLabel?.textColor = .systemBlue
            cell.textLabel?.textAlignment = .center
            cell.textLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 1 {
            view.endEditing(true)
            trackEventTapped()
        }
    }
}
