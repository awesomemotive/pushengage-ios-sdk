//
//  NetworkRouter.swift
//  PushEngage
//
//  Created by Abhishek on 17/02/21.
//

import Foundation

typealias NetworkRouterCompletion = (Result<Data, PEError>) -> Void
typealias NetworkRouterDownloadCompletion = (Result<(URL, URLResponse), PEError>) -> Void

protocol NetworkRouterType {
    func request(_ route: PERouter, completion: @escaping NetworkRouterCompletion)
    func requestDownload(_ route: PERouter, completion: @escaping NetworkRouterDownloadCompletion)
    func cancel()
}
