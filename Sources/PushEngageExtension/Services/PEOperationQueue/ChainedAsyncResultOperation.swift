//
//  AsyncChainedOperation.swift
//  PushEngage
//
//  Created by Abhishek on 31/03/21.
//

import Foundation

protocol ChainedOperationOutputProviding {
    var output: Any? { get }
}

package class ChainedAsyncResultOperation<Input, Output, Failure>: AsyncResultOperation<Output, Failure>
                                                                    where Failure: Error {

    private(set) var input: Input?

    init(input: Input? = nil) {
        self.input = input
        super.init()
    }

    package override func start() {
        if input == nil {
            updateInputFromDependencies()
        }
        super.start()
    }

    private func updateInputFromDependencies() {
        guard input == nil else { return }
        input = dependencies.compactMap { dependency in
            return (dependency as? ChainedOperationOutputProviding)?.output as? Input
        }.first
    }
}
