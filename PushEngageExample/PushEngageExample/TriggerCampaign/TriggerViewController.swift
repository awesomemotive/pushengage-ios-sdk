//
//  TriggerViewController.swift
//  PushNotificationDemo
//
//  Created by Himshikhar Gayan on 22/12/23.
//
//  Programmatic inset-grouped action menu. Matches the visual idiom of the
//  HomeViewController and pipes results to `SdkEventLog.shared` so the
//  history is visible from HomeViewController's bottom panel.
//

import UIKit
import PushEngage

class TriggerViewController: UIViewController {

    private enum Action {
        case addAlert
        case sendTriggerEvent
        case enableAutomatedNotification
        case disableAutomatedNotification

        var title: String {
            switch self {
            case .addAlert: return "Add Alert"
            case .sendTriggerEvent: return "Send Trigger Event"
            case .enableAutomatedNotification: return "Enable Automated Notification"
            case .disableAutomatedNotification: return "Disable Automated Notification"
            }
        }
    }

    private let actions: [Action] = [
        .addAlert,
        .sendTriggerEvent,
        .enableAutomatedNotification,
        .disableAutomatedNotification
    ]

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

    override func loadView() {
        // Programmatic root — supersedes the legacy TriggerViewController.xib
        // which still references @IBOutlets that no longer exist on this class.
        view = UIView()
        if #available(iOS 13.0, *) {
            view.backgroundColor = .systemGroupedBackground
        } else {
            view.backgroundColor = UIColor(white: 0.95, alpha: 1)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Trigger Campaigns"

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
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
    }

    // MARK: - Action dispatch

    private func perform(_ action: Action) {
        switch action {
        case .addAlert:
            let entry = TriggerEntryViewController()
            entry.isAlert = true
            navigationController?.pushViewController(entry, animated: true)
        case .sendTriggerEvent:
            let entry = TriggerEntryViewController()
            entry.isAlert = false
            navigationController?.pushViewController(entry, animated: true)
        case .enableAutomatedNotification:
            runAutomatedNotification(status: .enabled,
                                     okMessage: "Trigger enabled successfully",
                                     failPrefix: "Enable Automated Notification")
        case .disableAutomatedNotification:
            runAutomatedNotification(status: .disabled,
                                     okMessage: "Trigger disabled successfully",
                                     failPrefix: "Disable Automated Notification")
        }
    }

    private func runAutomatedNotification(status: TriggerStatusType,
                                          okMessage: String,
                                          failPrefix: String) {
        showLoader()
        PushEngage.automatedNotification(status: status) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.hideLoader()
                if result {
                    self.showSnackbar(message: okMessage, isSuccess: true)
                    SdkEventLog.shared.append("\(failPrefix) OK")
                    self.showResponseSheet(title: "\(failPrefix) — success",
                                           payload: okMessage)
                } else {
                    let msg = error?.localizedDescription ?? "(no error)"
                    self.showSnackbar(message: "Failure: \(msg)", isSuccess: false)
                    SdkEventLog.shared.append("\(failPrefix) FAILED: \(msg)")
                    self.showResponseSheet(title: "\(failPrefix) — failed",
                                           payload: msg)
                }
            }
        }
    }

    // MARK: - Helpers

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
}

// MARK: - UITableViewDelegate / UITableViewDataSource

extension TriggerViewController: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int { 1 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        actions.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "Trigger actions"
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let action = actions[indexPath.row]
        cell.textLabel?.text = action.title
        cell.textLabel?.font = .systemFont(ofSize: 16, weight: .regular)
        // Push-style actions get a disclosure indicator; in-line actions don't.
        cell.accessoryType = (action == .addAlert || action == .sendTriggerEvent) ? .disclosureIndicator : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        perform(actions[indexPath.row])
    }
}
