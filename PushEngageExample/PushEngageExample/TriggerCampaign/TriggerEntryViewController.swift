//
//  TriggerEntryViewController.swift
//  PushNotificationDemo
//
//  Created by Himshikhar Gayan on 27/12/23.
//

import UIKit
import PushEngage

class TriggerEntryViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, UIPickerViewDataSource, UIPickerViewDelegate {
    
    @IBOutlet weak var expiryLabel: UILabel!
    @IBOutlet weak var datetimePicker: UIDatePicker!
    @IBOutlet weak var mrp: UITextField!
    @IBOutlet weak var availabilityLabel: UILabel!
    @IBOutlet weak var typeLabel: UILabel!
    @IBOutlet weak var productId: UITextField!
    @IBOutlet weak var availability: UIPickerView!
    @IBOutlet weak var alertPrice: UITextField!
    @IBOutlet weak var variantId: UITextField!
    @IBOutlet weak var price: UITextField!
    @IBOutlet weak var link: UITextField!
    @IBOutlet weak var type: UIPickerView!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var campaignName: UITextField!
    @IBOutlet weak var eventName: UITextField!
    @IBOutlet weak var referenceId: UITextField!
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var doneButton: UIButton!
    
    @IBOutlet weak var profileId: UITextField!
    private var data = [(String, String, DataCellState)]()
    private let typeData: [TriggerAlertType] = [.priceDrop, .inventory]
    private let availabilityData: [TriggerAlertAvailabilityType] = [.inStock, .outOfStock]
    private var selectedDate: Date?
    
    private var selectedType: TriggerAlertType = .priceDrop {
        didSet {
            self.alertPrice.isHidden = (self.selectedType == .inventory)
        }
    }
    private var selectedAvailability: TriggerAlertAvailabilityType?
    
    private let celIdentifier: String = "DataCell"
    
    var isAlert: Bool = true
    
    private let snackbarView = SnackbarView(
        frame: CGRect(
            origin: .zero,
            size: CGSize(
                width: 200,
                height: 50
            )
        )
    )
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Trigger Campaign"
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(UINib.init(nibName: celIdentifier, bundle: nil), forCellReuseIdentifier: celIdentifier)
        doneButton.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        type.dataSource = self
        type.delegate = self
        availability.dataSource = self
        availability.delegate = self
        
        self.productId.delegate = self
        self.availability.delegate = self
        self.alertPrice.delegate = self
        self.variantId.delegate = self
        self.price.delegate = self
        self.link.delegate = self
        self.type.delegate = self
        self.campaignName.delegate = self
        self.eventName.delegate = self
        self.referenceId.delegate = self
        self.mrp.delegate = self
        datetimePicker.addTarget(self, action: #selector(datePickerValueChanged), for: .valueChanged)

        if isAlert {
            self.campaignName.isHidden = true
            self.eventName.isHidden = true
            self.referenceId.isHidden = true
        } else {
            self.datetimePicker.isHidden = true
            self.expiryLabel.isHidden = true
            self.mrp.isHidden = true
            self.productId.isHidden = true
            self.availability.isHidden = true
            self.alertPrice.isHidden = true
            self.variantId.isHidden = true
            self.price.isHidden = true
            self.link.isHidden = true
            self.type.isHidden = true
            self.typeLabel.isHidden = true
            self.availabilityLabel.isHidden = true
        }
        
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard)))
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
        snackbarView.isHidden = true
    }
    
    @objc func datePickerValueChanged(_ sender: UIDatePicker) {
        self.selectedDate = sender.date
    }
    
    @objc private func dismissKeyboard() {
        view.endEditing(true)
    }
    
    @objc func keyboardWillShow(_ notification: Notification) {
        if let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            let contentInsets = UIEdgeInsets(top: 0, left: 0, bottom: keyboardSize.height, right: 0)
            scrollView.contentInset = contentInsets
            scrollView.scrollIndicatorInsets = contentInsets
        }
    }
    
    @objc func keyboardWillHide(_ notification: Notification) {
        let contentInsets = UIEdgeInsets.zero
        scrollView.contentInset = contentInsets
        scrollView.scrollIndicatorInsets = contentInsets
    }
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        return 1
    }
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {

        if pickerView == type {
            switch self.typeData[row] {
            case .inventory: return "Inventory"
            case .priceDrop: return "Price Drop"
            }
        } else {
            if row == 0 {
                return "Nil"
            }
            switch (self.selectedType == .inventory) ? self.availabilityData[1] : self.availabilityData[row-1] {
            case .inStock: return "In Stock"
            case .outOfStock: return "Out of Stock"
            }
        }
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        return pickerView == type ? 2 : (selectedType == .inventory ? 2 : 3)
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        if pickerView == type {
            self.selectedType = self.typeData[row]
            self.availability.reloadAllComponents()
        } else {
            if row != 0 {
                self.selectedAvailability = (self.selectedType == .inventory) ? self.availabilityData[1] : self.availabilityData[row-1]
            } else {
                self.selectedAvailability = nil
            }
        }
    }
    
    @objc private func doneTapped() {
        var mappedData = [String: String]()
        self.data.forEach({ mappedData[$0.0] = $0.1 })
        var alertPrice: Double?
        if let price = self.alertPrice.text, let value = Double(price) {
            alertPrice = value
        }
        var price: Double?
        if let priceText = self.price.text, let value = Double(priceText) {
            price = value
        }
        if isAlert {
            let triggerAlert = TriggerAlert(
                type: selectedType,
                productId: productId.text ?? "",
                link: link.text ?? "",
                price: price ?? 0.0,
                variantId: (variantId.text?.isEmpty ?? true) ? nil : variantId.text,
                expiryTimestamp: selectedDate,
                alertPrice: alertPrice,
                availability: self.selectedAvailability ?? nil,
                profileId: (profileId.text?.isEmpty ?? true) ? nil : profileId.text,
                mrp: (mrp.text?.isEmpty ?? true) ? nil : Double(mrp.text ?? "0"),
                data: mappedData
            )
            PushEngage.addAlert(
                triggerAlert: triggerAlert
            ) {
                response,
                error in
                if error != nil {
                    self.showSnackbar(
                        message: error?.localizedDescription ?? "",
                        isSuccess: false
                    )
                } else {
                    self.showSnackbar(
                        message: "Add Alert Successfull",
                        isSuccess: true
                    )
                }
            }
        } else {

            let triggerCampaign = TriggerCampaign(
                campaignName: campaignName.text ?? "",
                eventName: eventName.text ?? "",
                referenceId: (referenceId.text?.isEmpty ?? true) ? nil : referenceId.text,
                profileId: (profileId.text?.isEmpty ?? true) ? nil : profileId.text,
                data: mappedData
            )
            PushEngage.sendTriggerEvent(
                triggerCampaign: triggerCampaign
            ) {
                response,
                error in
                if error != nil {
                    self.showSnackbar(
                        message: error?.localizedDescription ?? "",
                        isSuccess: false
                    )
                } else {
                    self.showSnackbar(
                        message: "Send Trigger Alert Successfull",
                        isSuccess: true
                    )
                }
            }
        }
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
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: celIdentifier, for: indexPath) as? DataCell
        if indexPath.row == 0 {
            cell?.setData(key: "", value: "", state: .add)
            cell?.keyTextField.delegate = self
            cell?.valueTextField.delegate = self
        } else {
            cell?.setData(key: data[indexPath.row - 1].0, value: data[indexPath.row - 1].1, state: data[indexPath.row - 1].2)
        }
        cell?.didTap = { state in
            if state == .add {
                self.data.insert((cell?.keyTextField.text ?? "", cell?.valueTextField.text ?? "", .cancel), at: 0)
            } else {
                self.data.remove(at: indexPath.row - 1)
            }
            tableView.reloadData()
        }
        return cell ?? UITableViewCell()
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return data.count + 1
    }

}
