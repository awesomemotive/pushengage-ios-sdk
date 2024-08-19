//
//  JSONParameterEncoder.swift
//  PushEngage
//
//  Created by Abhishek on 17/02/21.
//

import Foundation

public struct JSONParameterEncoder {
    
    public static func encode<T: Codable>(urlRequest: inout URLRequest,
                                          with object: T)  throws {
        do {
            let jsonData = try JSONEncoder().encode(object.self)
            urlRequest.httpBody = jsonData
        } catch {
            throw PEError.encodingFailed
        }
    }
    
    public static func encode(urlRequest: inout URLRequest,
                              for parameter: Parameters) throws {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: parameter, options: .prettyPrinted)
            urlRequest.httpBody = jsonData
        } catch {
            throw PEError.encodingFailed
        }
    }
    
}
