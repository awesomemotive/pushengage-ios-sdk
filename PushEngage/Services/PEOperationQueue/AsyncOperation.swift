//
//  AsyncOperation.swift
//  PushEngage
//
//  Created by Abhishek on 31/03/21.
//

import Foundation

open class AsyncOperation: Operation {
    private let lockQueue = DispatchQueue(label: "com.pushengage.lock.queue", attributes: .concurrent)

    override open var isAsynchronous: Bool {
        return true
    }

    private var _isExecuting: Bool = false
    override open private(set) var isExecuting: Bool {
        get {
            return lockQueue.sync { () -> Bool in
                return _isExecuting
            }
        }
        set {
            willChangeValue(forKey: "isExecuting")
            lockQueue.sync(flags: [.barrier]) {
                _isExecuting = newValue
            }
            didChangeValue(forKey: "isExecuting")
        }
    }

    private var _isFinished: Bool = false
    override open private(set) var isFinished: Bool {
        get {
            return lockQueue.sync { () -> Bool in
                return _isFinished
            }
        }
        set {
            willChangeValue(forKey: "isFinished")
            lockQueue.sync(flags: [.barrier]) {
                _isFinished = newValue
            }
            didChangeValue(forKey: "isFinished")
        }
    }

    override open func start() {
        guard !isCancelled else {
            finish()
            return
        }

        isFinished = false
        isExecuting = true
        main()
    }

    override open func main() {
        print("main execution")
        finish()
    }

    open func finish() {
        isExecuting = false
        isFinished = true
    }
}


public extension Operation {
    @discardableResult func observeStateChanges() -> [NSKeyValueObservation] {
        let keyPaths: [KeyPath<Operation, Bool>] = [
            \Operation.isExecuting,
            \Operation.isCancelled,
            \Operation.isFinished
        ]

        return keyPaths.map { keyPath in
            observe(keyPath, options: .new) { (_, value) in
                print("- \(keyPath._kvcKeyPathString!) is now \(value.newValue!)")
            }
        }
    }
}
