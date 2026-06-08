//
//  TextInputViewController.swift
//  PushNotificationDemo
//
//  iOS-native bottom-sheet input prompt. Mirrors Android's
//  `bottom_sheet_request.xml` / `getRequestFromUser(...)` from MainActivity —
//  drag handle, title, hint subtitle, outlined multi-line input, and
//  Cancel/OK buttons aligned bottom-right.
//

import UIKit

class TextInputViewController: UIViewController {

    // MARK: - Public API

    /// Title shown at the top of the sheet (e.g. "Add Subscriber Attributes").
    var promptTitle: String = "Enter Input"
    /// Optional helper text below the title (e.g. "Enter attributes as key value pairs").
    var hint: String?
    /// Pre-fill the input field. Use this in place of `textField.text` —
    /// kept for backward compatibility, see the `textField` shim below.
    var prefilledText: String = ""

    /// Fires with the trimmed input when the user taps OK.
    var didProvideInput: ((String) -> Void)?

    /// Back-compat shim — existing callers do `textInputVC.textField.text = "…"`.
    /// Now backed by the internal multi-line text view so the call sites don't break.
    var textField: TextFieldShim { TextFieldShim(owner: self) }

    // MARK: - Subviews

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 18, weight: .bold)
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    private let hintLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13)
        if #available(iOS 13.0, *) {
            l.textColor = .secondaryLabel
        } else {
            l.textColor = UIColor(white: 0.45, alpha: 1)
        }
        l.numberOfLines = 0
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()
    private let inputBorder: UIView = {
        let v = UIView()
        v.layer.cornerRadius = 8
        v.layer.borderWidth = 1
        if #available(iOS 13.0, *) {
            v.layer.borderColor = UIColor.separator.cgColor
        } else {
            v.layer.borderColor = UIColor(white: 0.78, alpha: 1).cgColor
        }
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()
    private let inputTextView: UITextView = {
        let tv = UITextView()
        tv.font = UIFont(name: "Menlo", size: 13) ?? .systemFont(ofSize: 13)
        tv.autocorrectionType = .no
        tv.autocapitalizationType = .none
        tv.backgroundColor = .clear
        tv.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        tv.translatesAutoresizingMaskIntoConstraints = false
        return tv
    }()
    private let cancelButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("Cancel", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()
    private let okButton: UIButton = {
        let b = UIButton(type: .system)
        b.setTitle("OK", for: .normal)
        b.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        b.translatesAutoresizingMaskIntoConstraints = false
        return b
    }()

    // MARK: - Lifecycle

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        configurePresentation()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configurePresentation()
    }

    private func configurePresentation() {
        if #available(iOS 15.0, *) {
            modalPresentationStyle = .pageSheet
        } else {
            modalPresentationStyle = .formSheet
        }
    }

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

        // Sheet detents + grabber configured here (not in init) so the
        // sheetPresentationController is reliably present.
        if #available(iOS 15.0, *), let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }

        titleLabel.text = promptTitle
        hintLabel.text = hint
        hintLabel.isHidden = (hint?.isEmpty ?? true)
        inputTextView.text = prefilledText

        inputBorder.addSubview(inputTextView)
        [titleLabel, hintLabel, inputBorder, cancelButton, okButton].forEach {
            view.addSubview($0)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            hintLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            inputBorder.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 16),
            inputBorder.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            inputBorder.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            inputBorder.heightAnchor.constraint(greaterThanOrEqualToConstant: 100),

            inputTextView.topAnchor.constraint(equalTo: inputBorder.topAnchor),
            inputTextView.leadingAnchor.constraint(equalTo: inputBorder.leadingAnchor),
            inputTextView.trailingAnchor.constraint(equalTo: inputBorder.trailingAnchor),
            inputTextView.bottomAnchor.constraint(equalTo: inputBorder.bottomAnchor),

            okButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            okButton.topAnchor.constraint(equalTo: inputBorder.bottomAnchor, constant: 16),
            okButton.heightAnchor.constraint(equalToConstant: 44),
            okButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),

            cancelButton.trailingAnchor.constraint(equalTo: okButton.leadingAnchor, constant: -16),
            cancelButton.centerYAnchor.constraint(equalTo: okButton.centerYAnchor),
            cancelButton.heightAnchor.constraint(equalToConstant: 44),
            cancelButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 60)
        ])

        okButton.addTarget(self, action: #selector(okTapped), for: .touchUpInside)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        inputTextView.becomeFirstResponder()
    }

    // MARK: - Actions

    @objc private func okTapped() {
        let text = inputTextView.text ?? ""
        // Fire the callback only after dismiss completes — otherwise a fast SDK
        // response races the dismiss animation and `showResponseSheet` tries to
        // present while this sheet is still mid-dismiss, which iOS silently drops.
        let callback = didProvideInput
        dismiss(animated: true) {
            callback?(text)
        }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    // MARK: - Back-compat shim

    /// Tiny shim so existing call sites of the form
    /// `textInputVC.textField.text = "…"` keep working. Reads/writes the
    /// internal multi-line text view's contents.
    struct TextFieldShim {
        weak var owner: TextInputViewController?
        var text: String? {
            get { owner?.prefilledText }
            nonmutating set {
                owner?.prefilledText = newValue ?? ""
                // If the view is already loaded, propagate to the live text view too.
                if owner?.isViewLoaded == true {
                    owner?.inputTextView.text = newValue ?? ""
                }
            }
        }
    }
}
