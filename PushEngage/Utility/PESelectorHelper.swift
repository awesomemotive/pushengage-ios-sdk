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

    
    /// method is used to check weather the instance of the Selector is overriden or not.
    ///  it first get the instance of super class and then checks weather the passed instance
    ///  is having instance method selector is equal to instance super class method instance of selector.
    /// - Parameters:
    ///   - instance: type Any class
    ///   - selector: Selector (basically the signature of the method to check super class has the instance of method.)
    /// - Returns: Bool whether pass class isntance has the instance of method for passed selector is equal or not with
    ///   the instance of method passed for the passed instance spuer class.
    func checkIfClassInstanceOverridesSelector(_ instance: AnyClass, _ selector: Selector) -> Bool {
        let instSuperClass: AnyClass? = instance.superclass()
        return instance.instanceMethod(for: selector) != instSuperClass?.instanceMethod(for: selector)
    }

    /// method check weather the passed class
    /// conforms (means class has extended the protocol and override the protocol methods.)
    /// if passed searchClass does not conforms the passed protocol then check weather
    /// class has super class if super class is nil then return nil
    /// because class must have the super class then check recurcively weather it has
    /// super class or not if you got super class the return that class.
    /// and if class conform the protocol then return the search class.
    /// - Parameters:
    ///   - searchClass: Any class type.
    ///   - protocolToFind: pass  protocol to find the the hierarcy of the passed class
    ///                     instance has conformed protocol or not.
    /// - Returns: AnyClass. if seached class has conformed the protocol then
    ///            return the same class otherwise check recurcively.
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
    
    
    /// method provide the functionality to exchange the implementaion of the new selector to
    /// the selector you want to swizzile.
    /// this method is heart of method swizzling.
    /// What is selector:- In objcetive c as it is uses dynamic dispatch mostly memory
    /// allocation happens in run time so we use
    /// selectors to tell complile perform set of instruction which is
    /// specified in #selector so when we use that syntax we have to
    /// explicitly tell complier by mentioning @objc infront of the func that this function is selector.
    /// - Parameters:
    ///   - newClass: Any Class type class you want to swizzle
    ///   - newSel: Selector you want the swizzile
    ///   - addToClass: Any Class Type class who implement you want to swizzle with new class
    ///   - makeLikeSel: Selector you want to swizzile with new selector
    /// - Returns: Bool as result is discarable
    @discardableResult
    func injectSelectorAtRuntime(_ newClass: AnyClass,
                                 _ newSel: Selector,
                                 _ addToClass: AnyClass,
                                 _ makeLikeSel: Selector) -> Bool {
        // first we get the instance of the method by passing its class and selector
        guard var unWrappedNewMethod = class_getInstanceMethod(newClass, newSel) else {
            return false
        }
        // then obtain the new method implementaion with the help of instance we got.
        let newMethodImplementation = method_getImplementation(unWrappedNewMethod)
        
        // then get the Type Encoding of the method for the instance of method we have the encoding in UnsafePointer<CChar>?.
        guard let unWrappedTypeEncoding = method_getTypeEncoding(unWrappedNewMethod)  else {
            return false
        }
        // then type cast to String as cString (unsigned sequence of bytes UTF-8)
        let methodTypeEncoding = String(cString: unWrappedTypeEncoding)
        
        // check weather the selector which you want your new selector work like. for the addToClass.
        let isExisiting = class_getInstanceMethod(addToClass, makeLikeSel) != nil

        // if exist
        if isExisiting {
            // then add the method to the class with help of selector method impl and encoding.
            class_addMethod(addToClass, newSel, newMethodImplementation, methodTypeEncoding)
            guard let unWrappedInstanceMethod = class_getInstanceMethod(addToClass, newSel) else {
                return false
            }
            unWrappedNewMethod = unWrappedInstanceMethod
            guard let orgMethod: Method = class_getInstanceMethod(addToClass, makeLikeSel) else {
                return false
            }
            // then exchange the implementation of the orgmethod with the new method.
            method_exchangeImplementations(orgMethod, unWrappedNewMethod)
        } else {
            // if not exist the simply add that method with implementation you want to execute.
            class_addMethod(addToClass,
                            makeLikeSel,
                            newMethodImplementation,
                            methodTypeEncoding)
        }
        return isExisiting
    }
    
    /// this method is combination of the checkIfClassInstanceOverridesSelector and
    /// injectSelectorAtRuntime it check weather the delegateSubClasses overrides the selector or not
    /// if there are not then just pass the delegate class to the injectSelectorAtRuntime.
    /// - Parameters:
    ///   - newSel: Selector Type
    ///   - makeLikeSel: Selctor
    ///   - delegateSubClasses: Array of [AnyClass] Type
    ///   - myClass: AnyClass
    ///   - delegateClass: AnyClass
    func injectToActualClassAtRuntime(_ newSel: Selector,
                                      _ makeLikeSel: Selector,
                                      _ delegateSubClasses: [AnyClass],
                                      _ myClass: AnyClass,
                                      _ delegateClass: AnyClass) {

        for subClass in delegateSubClasses {
            if checkIfClassInstanceOverridesSelector(subClass, makeLikeSel) {
                injectSelectorAtRuntime(myClass, newSel, subClass, makeLikeSel)
                return
            }
        }
        injectSelectorAtRuntime(myClass, newSel, delegateClass, makeLikeSel)
    }

    // This func obtains all the array of subclasses for the passed class instance if available.
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
