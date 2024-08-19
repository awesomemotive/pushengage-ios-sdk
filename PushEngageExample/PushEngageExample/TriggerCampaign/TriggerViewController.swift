//
//  TriggerViewController.swift
//  PushNotificationDemo
//
//  Created by Himshikhar Gayan on 22/12/23.
//

import UIKit
import PushEngage

class TriggerViewController: UIViewController {
    
    @IBOutlet weak var addAlertAction: UIButton!
    @IBOutlet weak var sendTriggerEventAction: UIButton!
    @IBOutlet weak var enableAutomatedNotificationAction: UIButton!
    @IBOutlet weak var disableAutomatedNotificationAction: UIButton!
    
    private let snackbarView = SnackbarView(
        frame: CGRect(
            origin: .zero,
            size: CGSize(
                width: 200,
                height: 50
            )
        )
    )
    
    private let activityIndicator: UIActivityIndicatorView = {
        if #available(
            iOSApplicationExtension 13.0,
            *
        ) {
            let indicator = UIActivityIndicatorView()
            indicator.color = .red
            indicator.translatesAutoresizingMaskIntoConstraints = false
            return indicator
        } else {
            let indicator = UIActivityIndicatorView(
                style: .gray
            )
            indicator.translatesAutoresizingMaskIntoConstraints = false
            return indicator        }
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Trigger Campaigns"
        
        view.addSubview(
            snackbarView
        )
        snackbarView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate(
            [
                snackbarView.leadingAnchor.constraint(
                    equalTo: view.leadingAnchor,
                    constant: 20
                ),
                snackbarView.trailingAnchor.constraint(
                    equalTo: view.trailingAnchor,
                    constant: -20
                ),
                snackbarView.bottomAnchor.constraint(
                    equalTo: view.bottomAnchor,
                    constant: -100
                )
            ]
        )
        
        view.addSubview(
            activityIndicator
        )
        NSLayoutConstraint.activate(
            [
                activityIndicator.centerXAnchor.constraint(
                    equalTo: view.centerXAnchor
                ),
                activityIndicator.centerYAnchor.constraint(
                    equalTo: view.centerYAnchor
                )
            ]
        )
        
        snackbarView.isHidden = true
        addAlertAction.addTarget(
            self,
            action: #selector(
                addAlert
            ),
            for: .touchUpInside
        )
        sendTriggerEventAction.addTarget(
            self,
            action: #selector(
                sendTriggerAlert
            ),
            for: .touchUpInside
        )
        enableAutomatedNotificationAction.addTarget(
            self,
            action: #selector(
                enableAutomatedNotification
            ),
            for: .touchUpInside
        )
        disableAutomatedNotificationAction.addTarget(
            self,
            action: #selector(
                disableAutomatedNotification
            ),
            for: .touchUpInside
        )
        
    }
    
    @objc private func enableAutomatedNotification() {
        self.showLoader()
        PushEngage.automatedNotification(
            status: .enabled
        ) {
            result,
            error in
            self.hideLoader()
            DispatchQueue.main.async { [weak self] in
                if result {
                    self?.showSnackbar(
                        message: "Trigger enabled successfully",
                        isSuccess: true
                    )
                } else {
                    self?.showSnackbar(
                        message: "Failure: \(error?.localizedDescription ?? "")",
                        isSuccess: false
                    )
                }
            }
        }
    }
    
    @objc private func disableAutomatedNotification() {
        self.showLoader()
        PushEngage.automatedNotification(
            status: .disabled
        ) {
            result,
            error in
            self.hideLoader()
            DispatchQueue.main.async { [weak self] in
                if result {
                    self?.showSnackbar(
                        message: "Trigger disabled successfully",
                        isSuccess: true
                    )
                } else {
                    self?.showSnackbar(
                        message: "Failure: \(error?.localizedDescription ?? "")",
                        isSuccess: false
                    )
                }
            }
        }
    }
    
    @objc private func sendTriggerAlert() {
        let triggerController = TriggerEntryViewController()
        triggerController.isAlert = false
        self.navigationController?.pushViewController(triggerController, animated: true)
    }
    
    @objc private func addAlert() {
        let triggerController = TriggerEntryViewController()
        triggerController.isAlert = true
        self.navigationController?.pushViewController(triggerController, animated: true)
    }
    
    func showSnackbar(
        message: String,
        isSuccess: Bool
    ) {
        DispatchQueue.main.async {
            self.snackbarView.setMessage(
                message,
                isSuccess: isSuccess
            )
            self.snackbarView.alpha = 0
            self.snackbarView.isHidden = false
            
            UIView.animate(withDuration: 0.5,
                           animations: {
                self.snackbarView.alpha = 1
            }) { (
                _
            ) in
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + 2.0
                ) {
                    self.hideSnackbar()
                }
            }
        }
    }
    
    private func hideSnackbar() {
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.5,
                           animations: {
                self.snackbarView.alpha = 0
            }) { (
                _
            ) in
                self.snackbarView.isHidden = true
            }
        }
    }
    
    private func showLoader() {
        DispatchQueue.main.async {
            self.activityIndicator.startAnimating()
            self.view.isUserInteractionEnabled = false
        }
    }
    
    private func hideLoader() {
        DispatchQueue.main.async {
            self.activityIndicator.stopAnimating()
            self.view.isUserInteractionEnabled = true
        }
    }
    
}
