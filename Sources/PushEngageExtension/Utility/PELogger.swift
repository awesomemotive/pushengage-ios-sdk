//
//  PELogger.swift
//  PushEngage
//
//  Created by Abhishek on 26/02/21.
//

import Foundation
import os.log

typealias Response = (request: URLRequest?, data: Data?, response: URLResponse?)

package struct PELogger {

    package static var isLoggingEnable = false

    static func verbose(className: String, message: String,
                               function: String = #function, line: Int = #line) {
        if isLoggingEnable {
            print(className + ": " + message + " : function name: - \(function) : line no: - \(line) ")
        }
    }

    package static func debug(className: String, message: String,
                             function: String = #function, line: Int = #line) {
        if isLoggingEnable {
            print(className + ": " + message + " : function name: - \(function) : line no: - \(line) ")
        }
    }

    package static func info(className: String, message: String,
                            function: String = #function, line: Int = #line) {
        if isLoggingEnable {
            print(className + ": " + message + " : function name: - \(function) : line no: - \(line) ")
        }
    }

    static func warning(className: String, message: String,
                               function: String = #function, line: Int = #line) {
        if isLoggingEnable {
            print(className + ": " + message + " : function name: - \(function) : line no: - \(line) ")
        }
    }

    // `message` stays %{private}: error paths interpolate URLs and server
    // responses, which must not persist readably in end-user device logs.
    package static func error(className: String, message: String,
                             function: String = #function, line: Int = #line) {
        os_log(.error, "[PushEngage] %{public}@: %{private}@ : function name: - %{public}@ : line no: - %d",
               className, message, function, line)
    }

    package static func debug(className: String, data: Data,
                             function: String = #function, line: Int = #line) {
        if isLoggingEnable {
            guard let value = String(data: data, encoding: .utf8) else {
                return
            }
            print(className + " : " + value + " : function name: - \(function) : line no: - \(line) ")
        }
    }

    static func dedug<T: Codable>(className: String, response: T,
                                         function: String = #function, line: Int = #line) {
        if isLoggingEnable {
            print(className + ":" + "\(response)" + " : function name: - \(function) : line no: - \(line)")
        }
    }

    static func logNetworkRequest(className: String, request: URLRequest,
                                         function: String = #function, line: Int = #line) {
        if isLoggingEnable {
            print(className + ": " + "Request started at : \(Date())")
            print(className + ": " + "Request URL : \(String(describing: request.url))")
            print(className + ": " + "Request Headers : \(String(describing: request.allHTTPHeaderFields))")
            let requestBody = request.httpBody
            if let data = requestBody, let jsonString = String(data: data, encoding: .utf8) {
                print(className + ": " + "Request Body JSON: \(jsonString)")
            }
            print(className + ": " + "function name: \(function)")
            print(className + ": " + "line number: \(line)")
        }
    }

    static func logNetworkResponse(className: String, response: Response,
                                          function: String = #function, line: Int = #line) {
        if isLoggingEnable {
            print(className + ": " + "Response received at : \(Date())")
            print(className + ": " + "Response for  : \(String(describing: response.request?.url))")
            let responseStatus = response.response as? HTTPURLResponse
            print(className + ": " + "Response status code : \(String(describing: responseStatus?.statusCode))")
            if let data = response.data {
                print(className + ": " + "Response Body : \(String(data: data, encoding: .utf8)  ?? "") ")
            }
            print(className + ": " + "function name: \(function)")
            print(className + ": " + "line number: \(line)")
        }
    }

    static func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        if isLoggingEnable {
            Swift.print(items, separator: separator, terminator: terminator)
        }
    }

    static func logError(message: String,
                                name: String,
                                tag: String,
                                subscriberHash: String) {
        let loggerData = SDKServerLogger(app: "ios",
                                         name: name,
                                         loggerData: LoggerData(tag: tag,
                                                                deviceTokenHash: subscriberHash,
                                                                device: Utility.getDevice,
                                                                timezone: Utility.timeZone,
                                                                error: message))
        PECoreServices.getRouter().request(.errorLogging(loggerData), completion: {_ in })
    }
}
