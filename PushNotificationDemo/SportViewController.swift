//
//  SportViewController.swift
//  Test
//
//  Created by Abhishek on 14/03/21.
//

import UIKit

// swiftlint:disable all

class SportViewController: UIViewController {

    
    override func viewDidLoad() {
        super.viewDidLoad()
        let image = UIImage(named: "sport")
        let imageView = UIImageView(image: image)
        view.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([imageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                                     imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                                     imageView.widthAnchor.constraint(equalToConstant: 300),
                                     imageView.heightAnchor.constraint(equalToConstant: 300)])
        let rightButtonItem = UIBarButtonItem(title: "pay" ,
                                              style: .plain,
                                              target: self,
                                              action: #selector(clickAction(_:)))
        navigationItem.rightBarButtonItem = rightButtonItem
        
    }
    
    @objc func clickAction(_ sender: Any) {
        let storyBoad = UIStoryboard(name: "Main", bundle: nil)
        if #available(iOSApplicationExtension 13.0, *) {
            let vc = storyBoad.instantiateViewController(identifier: "PEPay")
            self.navigationController?.pushViewController(vc, animated: true)
        } else {
            let vc = storyBoad.instantiateViewController(withIdentifier: "PEPay")
            self.navigationController?.pushViewController(vc, animated: true)
        }
       
    }
    
}
