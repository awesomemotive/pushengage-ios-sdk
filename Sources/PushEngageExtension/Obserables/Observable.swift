//
//  Obserable.swift
//  PushEngage
//
//  Created by Abhishek on 19/02/21.
//

import Foundation

// Custom Generic ObservableType.

protocol ObservableType {
    associatedtype DataType
    func subscribe(on: @escaping(DataType) -> Void) -> Disposable
}

package protocol Disposable {

    func dispose()
}

extension Disposable {
    package func disposed(by bag: DisposeBag) {
        bag.insert(self)
    }
}

package class DisposeBag {

    private var disposableList: [Disposable]
    private var lock = NSRecursiveLock()

    package init() {
        self.lock.lock()
        self.disposableList = [Disposable]()
        self.lock.unlock()
    }
    
    func insert(_ disposable: Disposable) {
        self.lock.lock()
        self.disposableList.append(disposable)
        self.lock.unlock()
    }
    
    package func disposedValue() {
        lock.lock()
         _ = disposableList.map { disposable in
            disposable.dispose()
        }
        disposableList.removeAll()
        lock.unlock()
    }
    
    deinit {
        disposedValue()
    }
}

package class Variable<Element>: ObservableType, Disposable {
    
    package typealias DataType = Element
    
    private var lock = NSRecursiveLock()
    
    private var _value: DataType
    
    package var value: DataType {
        get {
            self.lock.lock()
            defer { lock.unlock() }
            return self._value
        }
        set {
            self.lock.lock()
            self._value = newValue
            self.lock.unlock()
            self.triggerSubscription()
        }
    }
    
    typealias SubscriptionHandler = (DataType) -> Void
    
    private var observers =  [SubscriptionHandler]()
    
    package init(_ value: DataType) {
        self.lock.lock()
        self._value = value
        self.lock.unlock()
    }
    
    package func subscribe(on: @escaping (DataType) -> Void) -> Disposable {
        self.lock.lock()
        defer { lock.unlock() }
        observers.append(on)
        return self
    }
    
    
    func bind(to inputVariable: Variable<DataType>) -> Disposable {
        return subscribe { value in
            inputVariable.value = value
        }
    }
    
    package func dispose() {
        self.lock.lock()
        observers.removeAll()
        self.lock.unlock()
    }
    
    // MARK: - private
    
    private func triggerSubscription() {
        self.lock.lock()
        _ = observers.map { observer in
            observer(_value)
        }
        self.lock.unlock()
    }
}
