//
//  String+Extensions.swift
//  PushNotificationDemo
//
//  Created by Himshikhar Gayan on 22/12/23.
//

import Foundation

extension String {
    func convertStringToDictionary() -> [String: Any] {
        var dictionary = [String: Any]()
        
        // Split the input string into key-value pairs
        let keyValuePairs = self.components(separatedBy: ",")
        
        // Iterate through key-value pairs and add them to the dictionary
        for pair in keyValuePairs {
            // Split each pair into key and value
            let components = pair.components(separatedBy: ":")
            if components.count == 2 {
                // Trim whitespace from key and value
                let key = components[0].trimmingCharacters(in: .whitespaces)
                let valueString = components[1].trimmingCharacters(in: .whitespaces)
                
                // Try to convert the value to appropriate types (String, Bool, Int, etc.)
                if let boolValue = Bool(valueString) {
                    dictionary[key] = boolValue
                } else if let intValue = Int(valueString) {
                    dictionary[key] = intValue
                } else {
                    dictionary[key] = valueString
                }
            } else {
                // Invalid key-value pair format
                return [:]
            }
        }
        
        return dictionary
    }
}
