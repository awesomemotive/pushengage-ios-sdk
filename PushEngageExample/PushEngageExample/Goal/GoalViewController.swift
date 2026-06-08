//
//  GoalViewController.swift
//  PushNotificationDemo
//
//  Created by Himshikhar Gayan on 19/12/23.
//
//  Programmatic inset-grouped form. Matches the visual idiom of the new
//  HomeViewController and pipes results to `SdkEventLog.shared` so the
//  history is visible from HomeViewController's bottom panel.
//

import UIKit
import PushEngage

class GoalViewController: UIViewController {

    private enum Row: Int, CaseIterable {
        case name
        case count
        case value
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

    // Cell-owned text fields. Held by the controller so handleSend can read them.
    private let nameField = makeTextField(placeholder: "Goal name", keyboardType: .default)
    private let countField = makeTextField(placeholder: "Count (optional)", keyboardType: .numberPad)
    private let valueField = makeTextField(placeholder: "Value (optional)", keyboardType: .decimalPad)

    override func loadView() {
        // Programmatic root — supersedes the legacy GoalViewController.xib
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
        title = "Send Goal"

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

    @objc private func sendGoalTapped() {
        let name = (nameField.text ?? "").trimmingCharacters(in: .whitespaces)
        let count = Int(countField.text ?? "")
        let value = Double(valueField.text ?? "")
        let goal = Goal(name: name, count: count, value: value)

        showLoader()
        let summary = "name=\(name), count=\(count.map { "\($0)" } ?? "-"), value=\(value.map { "\($0)" } ?? "-")"

        PushEngage.sendGoal(goal: goal) { [weak self] response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.hideLoader()
                if let err = error {
                    self.showSnackbar(message: "Failure: \(err.localizedDescription)", isSuccess: false)
                    SdkEventLog.shared.append("Send Goal FAILED: \(err.localizedDescription)")
                    self.showResponseSheet(title: "Send Goal — failed",
                                           payload: err.localizedDescription)
                } else if response {
                    self.showSnackbar(message: "Goal Added Successfully", isSuccess: true)
                    SdkEventLog.shared.append("Send Goal OK: \(summary)")
                    let payload: [String: Any] = [
                        "name": name,
                        "count": count as Any,
                        "value": value as Any
                    ]
                    self.showResponseSheet(title: "Send Goal — success", payload: payload)
                } else {
                    self.showSnackbar(message: "Send goal failed", isSuccess: false)
                    SdkEventLog.shared.append("Send Goal FAILED: (no error)")
                    self.showResponseSheet(title: "Send Goal — failed",
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

    private static func makeTextField(placeholder: String, keyboardType: UIKeyboardType) -> UITextField {
        let f = UITextField()
        f.placeholder = placeholder
        f.keyboardType = keyboardType
        f.borderStyle = .none
        f.font = .systemFont(ofSize: 17)
        f.translatesAutoresizingMaskIntoConstraints = false
        return f
    }
}

// MARK: - UITableViewDelegate / UITableViewDataSource

extension GoalViewController: UITableViewDelegate, UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? Row.allCases.count : 1
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "Goal details" : nil
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.section == 0 {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.selectionStyle = .none
            let field: UITextField
            switch Row.allCases[indexPath.row] {
            case .name: field = nameField
            case .count: field = countField
            case .value: field = valueField
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
            // Action row: full-width "Send Goal" button.
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            cell.selectionStyle = .default
            cell.textLabel?.text = "Send Goal"
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
            sendGoalTapped()
        }
    }
}
