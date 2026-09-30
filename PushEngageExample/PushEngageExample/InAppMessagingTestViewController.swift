import UIKit
import PushEngage

/// In-App Messaging test screen. Campaigns are server-driven, so QA types
/// whatever event name a campaign is configured with (in the PushEngage
/// dashboard) rather than picking a fixed message type — mirrors Android's
/// InAppMessagingActivity.
class InAppMessagingTestViewController: UIViewController {

    private let eventNameField: UITextField = {
        let field = UITextField()
        field.placeholder = "Event name (as configured in the dashboard)"
        field.borderStyle = .roundedRect
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    /// Optional trigger parameters as flat JSON, e.g. `{"cart_value": 150}`.
    /// A campaign's `trigger.conditions` are matched against these, so a campaign
    /// that declares conditions needs the matching values here. Mirrors Android's
    /// InAppMessagingActivity.
    private let parametersField: UITextField = {
        let field = UITextField()
        field.placeholder = #"Trigger parameters JSON, e.g. {"type": "banner"}"#
        field.borderStyle = .roundedRect
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }()

    private let triggerButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Trigger Event", for: .normal)
        button.titleLabel?.font = .boldSystemFont(ofSize: 16)
        button.backgroundColor = .systemBlue
        button.setTitleColor(.white, for: .normal)
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()


    override func viewDidLoad() {
        super.viewDidLoad()
        title = "In-App Messaging"
        if #available(iOS 13.0, *) {
            view.backgroundColor = .systemBackground
        } else {
            view.backgroundColor = .white
        }
        setupUI()
        setupCustomActionHandler()
    }

    private func setupUI() {
        [eventNameField, parametersField, triggerButton].forEach(view.addSubview)

        NSLayoutConstraint.activate([
            eventNameField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            eventNameField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            eventNameField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            eventNameField.heightAnchor.constraint(equalToConstant: 44),

            parametersField.topAnchor.constraint(equalTo: eventNameField.bottomAnchor, constant: 12),
            parametersField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            parametersField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            parametersField.heightAnchor.constraint(equalToConstant: 44),

            triggerButton.topAnchor.constraint(equalTo: parametersField.bottomAnchor, constant: 16),
            triggerButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            triggerButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            triggerButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        triggerButton.addTarget(self, action: #selector(triggerTapped), for: .touchUpInside)

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    private func setupCustomActionHandler() {
        PushEngage.setIAMCustomActionHandler { actionId, parameters in
            print("Custom action received: \(actionId) with parameters: \(parameters)")
            DispatchQueue.main.async {
                var message = "Custom action: \(actionId)"
                if let action = parameters["action"] {
                    message += " — \(action)"
                }
                SdkEventLog.shared.append(message)
            }
        }
    }

    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }

    /// Parses the parameters field as a flat JSON object, keeping values as their
    /// JSON types (String/Number/Bool) so a campaign condition declaring
    /// `type: number` compares numerically. nil when the field is empty.
    private func parsedParameters() -> [String: Any]? {
        let text = (parametersField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            showToast("Parameters must be a flat JSON object")
            return nil
        }
        return object
    }

    /// Triggers an in-app message for the typed event name. A message displays
    /// only if a synced campaign is configured for that event and is eligible.
    @objc private func triggerTapped() {
        view.endEditing(true)
        let eventName = (eventNameField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !eventName.isEmpty else {
            showToast("Enter an event name")
            return
        }

        let parameters = parsedParameters()
        print("Triggering in-app event: \(eventName), params: \(parameters ?? [:])")
        PushEngage.triggerIAMEvent(eventName: eventName,
                                   parameters: parameters) { [weak self] success, error in
            DispatchQueue.main.async {
                if success {
                    SdkEventLog.shared.append("Triggered IAM event '\(eventName)'")
                    self?.showToast("Triggered '\(eventName)'")
                } else {
                    let message = error?.localizedDescription ?? "unknown error"
                    SdkEventLog.shared.append("Failed to trigger '\(eventName)': \(message)")
                    self?.showToast("Failed to trigger '\(eventName)': \(message)")
                }
            }
        }
    }


    private func showToast(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            alert.dismiss(animated: true)
        }
    }
}
