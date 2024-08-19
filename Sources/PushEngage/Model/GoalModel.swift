//
//  GoalModel.swift
//  PushEngage
//
//  Created by Himshikhar Gayan on 18/12/23.
//

import Foundation

@objcMembers
@objc public class Goal: NSObject {
    let name: String
    let count: Int?
    let value: Double?
    
    public init(name: String, count: Int?, value: Double?) {
        self.name = name
        self.count = count
        self.value = value
    }
    
    @objc public init(name: String, count: NSNumber?, value: NSNumber?) {
        self.name = name
        self.count = count?.intValue
        self.value = value?.doubleValue
    }
    
}
