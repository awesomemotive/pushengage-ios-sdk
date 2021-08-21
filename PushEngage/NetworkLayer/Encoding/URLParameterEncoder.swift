//
//  URLParameterEncoder.swift
//  PushEngage
//
//  Created by Abhishek on 17/02/21.
//

import Foundation

struct URLParameterEncoder {
    
    static func encode(urlRequest: inout URLRequest, with parameters: Parameters, isSortedDesc: Bool = false) throws {
        guard let url = urlRequest.url else {throw  PEError.missingURL}
        
        if var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false), !parameters.isEmpty {
            urlComponents.queryItems = [URLQueryItem]()
            for(key, value) in parameters.sorted(by: { isSortedDesc ? $0.key > $1.key :  $0.key < $1.key}) {
                let queryItem = URLQueryItem(name: key, value: "\(value)"
                                                .addingPercentEncoding(withAllowedCharacters: .urlHostAllowed))
                urlComponents.queryItems?.append(queryItem)
            }
            urlRequest.url = urlComponents.url
        }
    }
}
