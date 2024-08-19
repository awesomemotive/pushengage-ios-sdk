//
//  DataCell.swift
//  PushNotificationDemo
//
//  Created by Himshikhar Gayan on 27/12/23.
//

import UIKit

enum DataCellState {
    case add
    case cancel
}

class DataCell: UITableViewCell {

    @IBOutlet weak var actionButton: UIButton!
    @IBOutlet weak var valueTextField: UITextField!
    @IBOutlet weak var keyTextField: UITextField!
    
    var didTap: ((DataCellState)->())?
    
    var state: DataCellState = .add {
        didSet {
            if state == .add {
                valueTextField.isEnabled = true
                keyTextField.isEnabled = true
                actionButton.setTitle("Add", for: .normal)
            } else {
                valueTextField.isEnabled = false
                keyTextField.isEnabled = false
                actionButton.setTitle("Cancel", for: .normal)
            }
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        self.configure()
    }

    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
    }
    
    func setData(key: String, value: String, state: DataCellState) {
        self.keyTextField.text = key
        self.valueTextField.text = value
        self.state = state
    }
    
    private func configure() {
        actionButton.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
    }
    
    @objc private func actionButtonTapped() {
        didTap?(self.state)
    }
    
}
