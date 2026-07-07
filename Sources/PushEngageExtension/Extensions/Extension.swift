//
//  extension.swift
//  PushEngage
//
//  Created by Abhishek on 25/01/21.
//

import Foundation

extension Date {
    func years(from date: Date) -> Int {
        return Calendar.current.dateComponents([.year], from: date, to: self).year ?? 0
    }
    func months(from date: Date) -> Int {
        return Calendar.current.dateComponents([.month], from: date, to: self).month ?? 0
    }
    func weeks(from date: Date) -> Int {
        return Calendar.current.dateComponents([.weekOfMonth], from: date, to: self).weekOfMonth ?? 0
    }
    package func days(from date: Date) -> Int {
        return Calendar.current.dateComponents([.day], from: date, to: self).day ?? 0
    }
    func hours(from date: Date) -> Int {
        return Calendar.current.dateComponents([.hour], from: date, to: self).hour ?? 0
    }
    func minutes(from date: Date) -> Int {
        return Calendar.current.dateComponents([.minute], from: date, to: self).minute ?? 0
    }
    func seconds(from date: Date) -> Int {
        return Calendar.current.dateComponents([.second], from: date, to: self).second ?? 0
    }
    func offset(from date: Date) -> Int {
        if years(from: date)   > 0 { return years(from: date)   }
        if months(from: date)  > 0 { return months(from: date)  }
        if weeks(from: date)   > 0 { return weeks(from: date)   }
        if days(from: date)    > 0 { return days(from: date)    }
        if hours(from: date)   > 0 { return hours(from: date)   }
        if minutes(from: date) > 0 { return minutes(from: date) }
        if seconds(from: date) > 0 { return seconds(from: date) }
        return 0
    }
}


extension Dictionary {

    package subscript(userInfo key: Key) -> [AnyHashable: Any]? {
        get {
            return self[key] as? [AnyHashable: Any]
        }
        set {
            self[key] = newValue as? Value
        }
    }

    package subscript(string key: Key) -> String? {
        get {
            return self[key] as? String
        }

        set {
            self[key] = newValue as? Value
        }
    }

    package subscript(list key: Key) -> [AnyObject]? {
        get {
            return self[key] as? [AnyObject]
        }

        set {
            self[key] = newValue as? Value
        }
    }

    package subscript(boolValue key: Key) -> Bool {
        get {
            return self[key] as? Bool ?? false
        }

        set {
            self[key] = newValue as? Value
        }
    }
}


extension UserDefaults {
    package static var shared: UserDefaults? {
        let combined = UserDefaults(suiteName: Utility.getAppGroupInfo)
        return combined
    }
    
    package struct Key<Value> {
        package var name: String
    }
    
    subscript<T>(key: Key<T>) -> T? {
        get {
            return value(forKey: key.name) as? T
        }
        set {
            setValue(newValue, forKey: key.name)
        }
    }
}

extension UserDefaults.Key {
    static var isSubscriberDeleted: UserDefaults.Key<Bool> {
        return .init(name: UserDefaultConstant.isSubscriberDeleted)
    }
    
    static var isManuallyUnsubscribed: UserDefaults.Key<Bool> {
        return .init(name: UserDefaultConstant.isManuallyUnsubscribed)
    }
    
    static var permissionState: UserDefaults.Key<String> {
        return .init(name: UserDefaultConstant.permissionState)
    }
    
    static var ispermissionAlerted: UserDefaults.Key<Bool> {
        return .init(name: UserDefaultConstant.ispermissionAlertedKey)
    }
    
    package static var deviceToken: UserDefaults.Key<String> {
        return .init(name: UserDefaultConstant.deviceToken)
    }
    
    static var sdkEnvironment: UserDefaults.Key<Int> {
        return .init(name: UserDefaultConstant.environment)
    }
    
    static var badgeCount: UserDefaults.Key<Int> {
        return .init(name: UserDefaultConstant.badgeCount)
    }

    static var isSdkLoggingEnabled: UserDefaults.Key<Bool> {
        return .init(name: UserDefaultConstant.isSdkLoggingEnabled)
    }
    
    package static var subscriberHash: UserDefaults.Key<String> {
        return .init(name: UserDefaultConstant.subscriberHash)
    }
    
    static var geoLocationCountry: UserDefaults.Key<String> {
        return .init(name: UserDefaultConstant.country)
    }
    
    static var geoLocationState: UserDefaults.Key<String> {
        return .init(name: UserDefaultConstant.state)
    }
    
    static var profileID: UserDefaults.Key<String> {
        return .init(name: UserDefaultConstant.profileId)
    }
    
    static var appIsStarting: UserDefaults.Key<Bool> {
        return .init(name: UserDefaultConstant.appIsStarting)
    }
    
    static var lastSmartSubscribeDate: UserDefaults.Key<Date> {
        return .init(name: UserDefaultConstant.lastSmartSubscribeDate)
    }
    
    static var cityKey: UserDefaults.Key<String> {
        return .init(name: UserDefaultConstant.city)
    }
    
    static var siteKey: UserDefaults.Key<String> {
        return .init(name: UserDefaultConstant.siteKey)
    }
    
    static var istriedFirstTime: UserDefaults.Key<Bool> {
        return .init(name: UserDefaultConstant.isTriedFirstTime)
    }
    
    static var isSponseredIdKey: UserDefaults.Key<String> {
        return .init(name: UserDefaultConstant.sponsered)
    }
    
    static var isSwizzled: UserDefaults.Key<Bool> {
        return .init(name: UserDefaultConstant.isSwizzled)
    }

    static var platform: UserDefaults.Key<String> {
        return .init(name: UserDefaultConstant.platform)
    }

    static var wrapperVersion: UserDefaults.Key<String> {
        return .init(name: UserDefaultConstant.wrapperVersion)
    }

    static var subscriberFieldsCache: UserDefaults.Key<Data> {
        return .init(name: UserDefaultConstant.subscriberFieldsCache)
    }

    static var subscriberFieldsCacheTimestamp: UserDefaults.Key<Date> {
        return .init(name: UserDefaultConstant.subscriberFieldsCacheTimestamp)
    }
}
