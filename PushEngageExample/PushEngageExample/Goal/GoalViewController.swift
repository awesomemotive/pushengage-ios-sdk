//
//  GoalViewController.swift
//  PushNotificationDemo
//
//  Created by Himshikhar Gayan on 19/12/23.
//

import UIKit
import PushEngage

class GoalViewController: UIViewController, UITextFieldDelegate {

    @IBOutlet weak var goalName: UITextField!
    @IBOutlet weak var goalCount: UITextField!
    @IBOutlet weak var goalValue: UITextField!
    @IBOutlet weak var sendGoalAction: UIButton!
    private let snackbarView = SnackbarView(frame: CGRect(origin: .zero, size: CGSize(width: 200, height: 50)))
    
    private let activityIndicator: UIActivityIndicatorView = {
        if #available(iOSApplicationExtension 13.0, *) {
            let indicator = UIActivityIndicatorView()
            indicator.color = .red
            indicator.translatesAutoresizingMaskIntoConstraints = false
            return indicator
        } else {
            let indicator = UIActivityIndicatorView(style: .gray)
            indicator.translatesAutoresizingMaskIntoConstraints = false
            return indicator        }
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Send Goal"
        let backButton = UIBarButtonItem()
        backButton.title = "Back"
        self.navigationController?.navigationBar.topItem?.backBarButtonItem = backButton
        sendGoalAction.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(sendGoalTapped)))
        view.addSubview(snackbarView)
        snackbarView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            snackbarView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            snackbarView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            snackbarView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -100)
        ])
        view.addSubview(activityIndicator)
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard)))

        snackbarView.isHidden = true
        goalName.delegate = self
        goalCount.delegate = self
        goalValue.delegate = self
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    @objc private func sendGoalTapped() {
        var count: Int?
        var value: Double?
        if let countText = goalCount.text, let countDouble = Int(countText) {
            count = countDouble
        }
        if let valueText = goalValue.text, let valueDouble = Double(valueText) {
            value = valueDouble
        }
        let goal = Goal(name: goalName.text ?? "", count: count, value: value)
        self.showLoader()
        PushEngage.sendGoal(goal: goal) { [weak self] response, error in
            self?.hideLoader()
            DispatchQueue.main.async {
                if let err = error {
                    self?.showSnackbar(message: "Failure: \(err.localizedDescription)", isSuccess: false)
                } else {
                    self?.showSnackbar(message: "Goal Added Successfully", isSuccess: true)
                }
            }
        }
    }
    
    func showSnackbar(message: String, isSuccess: Bool) {
        snackbarView.setMessage(message, isSuccess: isSuccess)
        snackbarView.alpha = 0
        snackbarView.isHidden = false
        
        UIView.animate(withDuration: 0.5, animations: {
            self.snackbarView.alpha = 1
        }) { (_) in
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.hideSnackbar()
            }
        }
    }
    
    private func hideSnackbar() {
        DispatchQueue.main.async {
            UIView.animate(withDuration: 0.5, animations: {
                self.snackbarView.alpha = 0
            }) { (_) in
                self.snackbarView.isHidden = true
            }
        }
    }
    
    func showLoader() {
        DispatchQueue.main.async {
            self.activityIndicator.startAnimating()
            self.view.isUserInteractionEnabled = false
        }
    }
    
    func hideLoader() {
        DispatchQueue.main.async {
            self.activityIndicator.stopAnimating()
            self.view.isUserInteractionEnabled = true
        }
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
