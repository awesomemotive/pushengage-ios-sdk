//
//  SettingsViewController.swift
//  PushEngageExample
//
//  iOS-native equivalent of Android's SettingsActivity (PR #37).
//
//  Lets the user override the App ID + environment at runtime so the
//  demo can target different sites without recompiling. Persists to
//  `DemoPrefs`; the new values apply on the next app launch — iOS doesn't
//  expose a public restart API, so we ask the user to force-quit instead.
//

import UIKit
import PushEngage

final class SettingsViewController: UIViewController {

    private enum Section: Int, CaseIterable {
        case appId
        case environment
        case action

        var title: String? {
            switch self {
            case .appId:       return "App configuration"
            case .environment: return "Environment"
            case .action:      return nil
            }
        }

        var footer: String? {
            switch self {
            case .appId:       return "Paste the site key from your PushEngage dashboard."
            case .environment: return "Staging targets internal test infrastructure. Production targets live PushEngage backend."
            case .action:      return nil
            }
        }
    }

    /// When `true`, the user must save valid settings to leave this screen.
    /// Set by AppDelegate on the cold-start path when no app ID is configured.
    var isInitialSetup: Bool = false

    private let tableView: UITableView = {
        if #available(iOS 13.0, *) {
            return UITableView(frame: .zero, style: .insetGrouped)
        } else {
            return UITableView(frame: .zero, style: .grouped)
        }
    }()
    private let appIdField: UITextField = {
        let f = UITextField()
        f.placeholder = "e.g. 3ca8257d-1f40-41e0-88bc-ea28dc6495ef"
        f.font = UIFont(name: "Menlo", size: 14) ?? .systemFont(ofSize: 14)
        f.autocorrectionType = .no
        f.autocapitalizationType = .none
        f.clearButtonMode = .whileEditing
        f.translatesAutoresizingMaskIntoConstraints = false
        return f
    }()

    private var selectedEnvironment: PEEnvironment = DemoPrefs.shared.environment

    // MARK: - Lifecycle

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
        title = "Settings"

        // Hide back nav on first-launch flow; user must save to leave.
        if isInitialSetup {
            navigationItem.hidesBackButton = true
            // No Cancel either — only path forward is "Save".
        } else {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .cancel,
                target: self,
                action: #selector(cancelTapped)
            )
        }

        appIdField.text = DemoPrefs.shared.appId
        selectedEnvironment = DemoPrefs.shared.environment

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    private func saveTapped() {
        view.endEditing(true)
        let candidate = (appIdField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else {
            showAlert(title: "App ID required",
                      message: "Enter an App ID before saving.",
                      completion: nil)
            return
        }
        DemoPrefs.shared.appId = candidate
        DemoPrefs.shared.environment = selectedEnvironment
        promptRelaunch()
    }

    private func promptRelaunch() {
        // iOS doesn't expose a public restart API. The PushEngage SDK
        // caches its config from the first `setAppID` / `setEnvironment`
        // call at process start, so a fresh launch is the cleanest way
        // to apply new settings. Ask the user to force-quit.
        let alert = UIAlertController(
            title: "Settings saved",
            message: "Please force-quit and reopen the app to apply the new App ID and environment.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in
            guard let self = self else { return }
            if self.isInitialSetup {
                // Stay here — user needs to force-quit before the SDK initialises with the new settings.
                return
            }
            self.dismiss(animated: true)
        })
        present(alert, animated: true)
    }

    private func showAlert(title: String, message: String, completion: (() -> Void)?) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completion?() })
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource / Delegate

extension SettingsViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int { Section.allCases.count }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .appId:       return 1
        case .environment: return 2
        case .action:      return 1
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        Section(rawValue: section)?.title
    }

    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        Section(rawValue: section)?.footer
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .appId:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.selectionStyle = .none
            cell.contentView.addSubview(appIdField)
            NSLayoutConstraint.activate([
                appIdField.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                appIdField.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                appIdField.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 6),
                appIdField.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -6),
                appIdField.heightAnchor.constraint(greaterThanOrEqualToConstant: 32)
            ])
            return cell

        case .environment:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            let env: PEEnvironment = (indexPath.row == 0) ? .staging : .production
            cell.textLabel?.text = (env == .staging) ? "Staging" : "Production"
            cell.accessoryType = (env == selectedEnvironment) ? .checkmark : .none
            return cell

        case .action:
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.textLabel?.text = "Save"
            cell.textLabel?.textColor = .systemBlue
            cell.textLabel?.textAlignment = .center
            cell.textLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
            return cell
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch Section(rawValue: indexPath.section)! {
        case .appId:
            // Tap the cell → focus the text field.
            appIdField.becomeFirstResponder()
        case .environment:
            let env: PEEnvironment = (indexPath.row == 0) ? .staging : .production
            selectedEnvironment = env
            tableView.reloadSections(IndexSet(integer: Section.environment.rawValue), with: .none)
        case .action:
            saveTapped()
        }
    }
}
