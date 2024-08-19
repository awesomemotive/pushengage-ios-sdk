//
//  AsyncResultOperation.swift
//  PushEngage
//
//  Created by Abhishek on 31/03/21.
//

import Foundation

class AsyncResultOperation<Success, Failure>: AsyncOperation where Failure: Error {
    
    private(set) var result: Result<Success, Failure>? {
        didSet {
            guard let result = result else {return}
            onResult?(result)
        }
    }
    
    var onResult: ((_ result: Result<Success, Failure>) -> Void)?
    
    override func finish() {
        guard !isCancelled else { return super.finish() }
        fatalError("Make use of finish(with:) instead to ensure a result")
    }
    
    func finish(with result: Result<Success, Failure>) {
        self.result = result
        super.finish()
    }
    
    override func cancel() {
        fatalError("Make use of cancel(with:) instead to ensure a result")
    }
    
    func cancel(with error: Failure) {
        self.result = .failure(error)
        super.cancel()
    }
}

extension AsyncResultOperation: ChainedOperationOutputProviding {
    var output: Any? {
        do {
            return try result?.get()
        } catch let failure {
            guard let failureError  = failure as? PEError else {
                return nil
            }
            switch failureError {
            case .sponseredfailWithContent(var attachmentString?, let networkService):
                return (attachmentString, networkService)
            default:
                return nil
            }
        }
    }
}
