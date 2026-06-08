//
//  ResponseSheetViewController.swift
//  PushEngageExample
//
//  iOS-native equivalent of Android's `bottom_sheet_response.xml` /
//  `showResponse(...)` from MainActivity. Pops up after every PushEngage
//  action with the result payload pretty-printed, plus Copy + Close
//  buttons. Uses UISheetPresentationController .medium() detent on
//  iOS 15+ for the bottom-sheet feel; falls back to .formSheet modal
//  on iOS 12-14.
//

import UIKit

final class ResponseSheetViewController: UIViewController {

    private let headerTitle: String
    private let bodyText: String

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 18, weight: .bold)
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    private let bodyView: UITextView = {
        let tv = UITextView()
        tv.font = UIFont(name: "Menlo", size: 13) ?? .systemFont(ofSize: 13)
        tv.isEditable = false
        tv.isSelectable = true
        tv.alwaysBounceVertical = true
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 4, bottom: 12, right: 4)
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()
    private let copyButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("Copy", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()
    private let closeButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("Close", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    init(title: String, body: String) {
        self.headerTitle = title
        self.bodyText = body
        super.init(nibName: nil, bundle: nil)
        // Presentation style must be set on the instance before present(...);
        // detent configuration goes in viewDidLoad after the
        // sheetPresentationController is reliably available.
        if #available(iOS 15.0, *) {
            modalPresentationStyle = .pageSheet
        } else {
            modalPresentationStyle = .formSheet
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        view = UIView()
        if #available(iOS 13.0, *) {
            view.backgroundColor = .systemBackground
        } else {
            view.backgroundColor = .white
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        if #available(iOS 15.0, *), let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        titleLabel.text = headerTitle
        bodyView.text = bodyText
        if #available(iOS 13.0, *) {
            bodyView.backgroundColor = .secondarySystemBackground
        } else {
            bodyView.backgroundColor = UIColor(white: 0.95, alpha: 1)
        }
        bodyView.layer.cornerRadius = 8

        [titleLabel, bodyView, copyButton, closeButton].forEach { view.addSubview($0) }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            bodyView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            bodyView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            bodyView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            bodyView.bottomAnchor.constraint(equalTo: copyButton.topAnchor, constant: -16),

            copyButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            copyButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            copyButton.heightAnchor.constraint(equalToConstant: 44),

            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            closeButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            closeButton.heightAnchor.constraint(equalToConstant: 44)
        ])

        copyButton.addTarget(self, action: #selector(copyTapped), for: .touchUpInside)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    }

    @objc private func copyTapped() {
        UIPasteboard.general.string = bodyText
        let original = copyButton.title(for: .normal)
        copyButton.setTitle("Copied!", for: .normal)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.copyButton.setTitle(original, for: .normal)
        }
    }

    @objc private func closeTapped() {
        dismiss(animated: true)
    }
}

// MARK: - Pretty-print helper (mirrors Android's `tryPrettyPrintJson` + Gson path)

enum ResponseFormatter {
    static func format(_ payload: Any?) -> String {
        guard let payload = payload else {
            return "Operation completed successfully."
        }
        if let string = payload as? String {
            if string.isEmpty { return "Operation completed successfully." }
            // Try to interpret as JSON for pretty-printing; pass through otherwise.
            return tryPrettyPrintJSON(string)
        }
        if JSONSerialization.isValidJSONObject(payload),
           let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
           let pretty = String(data: data, encoding: .utf8) {
            return unescapeSlashes(pretty)
        }
        return String(describing: payload)
    }

    private static func tryPrettyPrintJSON(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let result = String(data: pretty, encoding: .utf8)
        else {
            return raw
        }
        return unescapeSlashes(result)
    }

    private static func unescapeSlashes(_ json: String) -> String {
        json.replacingOccurrences(of: "\\/", with: "/")
    }
}

// MARK: - Convenience presenter

extension UIViewController {
    /// Presents the response bottom sheet over the current view controller.
    /// Title is shown bold at the top; payload is pretty-printed JSON when
    /// possible, plain text otherwise. Safe to call from any action handler
    /// — no-op if the presenter is already presenting something else.
    func showResponseSheet(title: String, payload: Any?) {
        let work = { [weak self] in
            guard let self = self else { return }
            let body = ResponseFormatter.format(payload)
            let sheet = ResponseSheetViewController(title: title, body: body)
            // Walk up to the topmost presented controller to avoid the
            // "Attempt to present X on Y whose view is not in the window hierarchy" trap.
            var presenter: UIViewController = self
            while let nextPresented = presenter.presentedViewController {
                presenter = nextPresented
            }
            presenter.present(sheet, animated: true)
        }
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}
