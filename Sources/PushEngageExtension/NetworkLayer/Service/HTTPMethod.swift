//
//  HTTPMethod.swift
//  PushEngage
//
//  Created by Abhishek on 17/02/21.
//

import Foundation

typealias HTTPHeaders = [String: String]

enum HTTPMethod: String {
    case get  = "GET"
    case post = "POST"
    case patch = "PATCH"
    case delete = "DELETE"
    case put = "PUT"
}
