//
//  Router.swift
//  PushEngage
//
//  Created by Abhishek on 17/02/21.
//

import Foundation

class Router: NetworkRouter {

    private static let sessionManager: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        if #available(iOS 11.0, *) {
            config.waitsForConnectivity = true
        }
        config.timeoutIntervalForRequest = NetworkConstants.requestTimeout
        config.timeoutIntervalForResource = NetworkConstants.responseTimeOut
        return URLSession(configuration: config)
    }()

    
    private var task: URLSessionTask?
    
    private static func validation(for range: Range<Int>, statusCode: URLResponse?) -> (Bool?, Int?) {
        guard let code = statusCode as? HTTPURLResponse else {
            return (nil, nil)
        }
        PELogger.debug(className: String(describing: Router.self),
                       message: "error code:- \(code.statusCode)")
        return (range.contains(code.statusCode), code.statusCode)
    }
    
    
    private static func invalidStatusCodeHandler(with data: Data?,
                                                 valicationCode: Int?) -> PEError {
        guard let data = data else {
            return .dataNotFound
        }
        
        do {
            let decodedData = try JSONDecoder().decode(NetworkResponse.self,
                                                       from: data)
            let errorMessage = decodedData.errorMessage
            return .invalidStatusCode(errorMessage, valicationCode)
        } catch {
            return .invalidStatusCode("Not a network response",
                                      valicationCode)
        }
    }
    
    func request(_ route: PERouter,
                 completion: @escaping NetworkRouterCompletion) {
        
        if NetworkConnectivity.isConnectedToInternet == false {
            PELogger.debug(className: String(describing: Router.self),
                           message: "network not reachable.")
            completion(.failure(.networkNotReachable))
        } else {
            do {
                let request = try route.asURLRequest()
                PELogger.logNetworkRequest(className: String(describing: Router.self), request: request)
                task = Router.sessionManager.dataTask(with: request) { (data, response, error) in
                    PELogger.logNetworkResponse(className: String(describing: Router.self),
                                                response: (request, data, response))
                    if let error = error {
                        PELogger.debug(className: String(describing: Router.self),
                                       message: error.localizedDescription)
                        completion(.failure(.networkError))
                    } else {
                        let validationResult = Self.validation(for: 200..<300, statusCode: response)
                        if  validationResult.0 == true {
                            if case .errorLogging = route {
                                PELogger.debug(className: String(describing: Router.self),
                                               message: validationResult.1 == 201 ?
                                               "error logged success" : "failed to log error")
                            }
                            data != nil ? completion(.success(data!)) : completion(.failure(.dataNotFound))
                        } else {
                            completion(.failure((Self.invalidStatusCodeHandler(with: data,
                                                                          valicationCode: validationResult.1))))
                        }
                    }
                }
            } catch {
                PELogger.error(className: String(describing: Router.self ),
                               message: PEError.requestFailureException.errorDescription ?? "")
                completion(.failure(.requestFailureException))
            }
        }
        self.task?.resume()
    }
     
    
    func requestDownload(_ route: PERouter, completion: @escaping NetworkRouterDownloadCompletion) {
        
        if NetworkConnectivity.isConnectedToInternet == false {
            completion(.failure(.networkNotReachable))
        } else {
            do {
                let request = try route.asURLRequest()
                PELogger.logNetworkRequest(className: String(describing: Router.self), request: request)
                task = Router.sessionManager.downloadTask(with: request) { (url, response, error ) in
                    if let error = error {
                        PELogger.error(className: String(describing: Router.self),
                                       message: error.localizedDescription)
                        completion(.failure(.networkError))
                    } else {
                        PELogger.logNetworkResponse(className: String(describing: Router.self),
                                                    response: (request, nil, response))
                        let validationResult = Self.validation(for: 200..<300, statusCode: response)
                        validationResult.0 == true
                            ? url != nil && response != nil
                            ? completion(.success((url!, response!)))
                            : completion(.failure(.downloadAttachmentfailed))
                            : completion(.failure(.invalidStatusCode("failed to download image",
                                                                     validationResult.1 ?? -100)))
                    }
                }
            } catch {
                completion(.failure(.requestFailureException))
            }
        }
        self.task?.resume()
    }
    
    func cancel() {
        self.task?.cancel()
    }
}
