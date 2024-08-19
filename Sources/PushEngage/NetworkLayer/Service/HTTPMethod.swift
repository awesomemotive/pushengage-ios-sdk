//
//  HTTPMethod.swift
//  PushEngage
//
//  Created by Abhishek on 17/02/21.
//

import Foundation

public typealias HTTPHeaders = [String: String]

public enum HTTPMethod: String {
    case get  = "GET"
    case post = "POST"
    case patch = "PATCH"
    case delete = "DELETE"
    case put = "PUT"
}
