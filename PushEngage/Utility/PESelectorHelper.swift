//
//  PESelectorHelper.swift
//  PushEngage
//
//  Created by Abhishek on 07/05/21.
//

import Foundation

// Selector helpers are implemenated to provide the helper class to achive method swizzling.

final class PESelectorHelper {

    static let shared = PESelectorHelper()

    func checkIfInstanceOverridesSelector(_ instance: AnyClass, _ selector: Selector) -> Bool {
        let instSuperClass: AnyClass? = instance.superclass()
        return instance.instanceMethod(for: selector) != instSuperClass?.instanceMethod(for: selector)
    }

    func getClassWithProtocolInHierarchy(_ searchClass: AnyClass?, _ protocolToFind: Protocol?) -> AnyClass? {
        if !class_conformsToProtocol(searchClass, protocolToFind) {
            if searchClass?.superclass() == nil {
                return nil
            }
            let foundClass: AnyClass? = getClassWithProtocolInHierarchy(searchClass?.superclass(), protocolToFind)
            if foundClass != nil {
                return foundClass
            }
            return searchClass
        }
        return searchClass
    }
    
    @discardableResult
    func injectClassSelectorAtRuntime(_ newClass: AnyClass,
                                      _ newSel: Selector,
                                      _ addToClass: AnyClass,
                                      _ makeLikeSel: Selector) -> Bool {

        guard var unWrappedNewMethod = class_getClassMethod(newClass, newSel) else {
            return false
        }
        let newMethodImplementation = method_getImplementation(unWrappedNewMethod)
        guard let unWrappedTypeEncoding = method_getTypeEncoding(unWrappedNewMethod)  else {
            return false
        }
        let methodTypeEncoding = String(cString: unWrappedTypeEncoding)
        let isExisiting = class_getClassMethod(addToClass, makeLikeSel) != nil

        if isExisiting {
            class_addMethod(addToClass, newSel, newMethodImplementation, methodTypeEncoding)
            guard let unWrappedInstanceMethod = class_getClassMethod(addToClass, newSel) else {
                return false
            }
            unWrappedNewMethod = unWrappedInstanceMethod
            class_replaceMethod(addToClass, makeLikeSel,
                                newMethodImplementation,
                                methodTypeEncoding)
        } else {
            class_addMethod(addToClass, makeLikeSel,
                            newMethodImplementation,
                            methodTypeEncoding)
        }
        return isExisiting
    }

    @discardableResult
    func injectSelectorAtRuntime(_ newClass: AnyClass,
                                 _ newSel: Selector,
                                 _ addToClass: AnyClass,
                                 _ makeLikeSel: Selector) -> Bool {
        guard var unWrappedNewMethod = class_getInstanceMethod(newClass, newSel) else {
            return false
        }
        let newMethodImplementation = method_getImplementation(unWrappedNewMethod)
        guard let unWrappedTypeEncoding = method_getTypeEncoding(unWrappedNewMethod)  else {
            return false
        }
        let methodTypeEncoding = String(cString: unWrappedTypeEncoding)
        let isExisiting = class_getInstanceMethod(addToClass, makeLikeSel) != nil

        if isExisiting {
            class_addMethod(addToClass, newSel, newMethodImplementation, methodTypeEncoding)
            guard let unWrappedInstanceMethod = class_getInstanceMethod(addToClass, newSel) else {
                return false
            }
            unWrappedNewMethod = unWrappedInstanceMethod
            guard let orgMethod: Method = class_getInstanceMethod(addToClass, makeLikeSel) else {
                return false
            }
            method_exchangeImplementations(orgMethod, unWrappedNewMethod)
        } else {
            class_addMethod(addToClass,
                            makeLikeSel,
                            newMethodImplementation,
                            methodTypeEncoding)
        }
        return isExisiting
    }

    func injectToActualClassAtRuntime(_ newSel: Selector,
                                      _ makeLikeSel: Selector,
                                      _ delegateSubClasses: [AnyClass],
                                      _ myClass: AnyClass,
                                      _ delegateClass: AnyClass) {

        for subClass in delegateSubClasses {
            if checkIfInstanceOverridesSelector(subClass, makeLikeSel) {
                injectSelectorAtRuntime(myClass, newSel, subClass, makeLikeSel)
                return
            }
        }
        injectSelectorAtRuntime(myClass, newSel, delegateClass, makeLikeSel)
    }

    func getSubclasses(of theClass: AnyClass) -> [AnyClass] {
        
        let numClasses = objc_getClassList(nil, 0)
        let classes = UnsafeMutablePointer<AnyClass>.allocate(capacity: Int(numClasses))
        let autoreleasingClasses = AutoreleasingUnsafeMutablePointer<AnyClass>(classes)
        var result = [AnyClass]()
        objc_getClassList(autoreleasingClasses, numClasses)
        for index in 0..<numClasses {
            let someClass: AnyClass = classes[Int(index)]
            guard let someSuperClass = class_getSuperclass(someClass),
                  String(describing: someSuperClass) == String(describing: theClass) else { continue }
            result.append(someClass)
        }
        classes.deallocate()
        return result
    }
}
