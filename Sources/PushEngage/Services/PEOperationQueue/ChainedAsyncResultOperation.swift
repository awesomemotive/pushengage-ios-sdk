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

class ChainedAsyncResultOperation<Input, Output, Failure>: AsyncResultOperation<Output, Failure>
                                                            where Failure: Error {
    
    private(set) var input: Input?
    
    init(input: Input? = nil) {
        self.input = input
        super.init()
    }
    
    override func start() {
        if input == nil {
            updateInputFromDependencies()
        }
        super.start()
    }
    
    // If dependent operation is asking the input after updated from the parent operation.
    // then first opers output if sencod opeation needed as input then  ChainedOperationProviding
    // protocol will provide the first.ops output as input to the second.input = first.output.
    
    private func updateInputFromDependencies() {
        guard input == nil else { return }
        input = dependencies.compactMap { dependency in
            return (dependency as? ChainedOperationOutputProviding)?.output as? Input
        }.first
    }
}

