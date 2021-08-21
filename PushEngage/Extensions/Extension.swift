//
//  extension.swift
//  PushEngage
//
//  Created by Abhishek on 25/01/21.
//

import Foundation

extension Date {
    /// Returns the amount of years from another date
    func years(from date: Date) -> Int {
        return Calendar.current.dateComponents([.year], from: date, to: self).year ?? 0
    }
    /// Returns the amount of months from another date
    func months(from date: Date) -> Int {
        return Calendar.current.dateComponents([.month], from: date, to: self).month ?? 0
    }
    /// Returns the amount of weeks from another date
    func weeks(from date: Date) -> Int {
        return Calendar.current.dateComponents([.weekOfMonth], from: date, to: self).weekOfMonth ?? 0
    }
    /// Returns the amount of days from another date
    func days(from date: Date) -> Int {
        return Calendar.current.dateComponents([.day], from: date, to: self).day ?? 0
    }
    /// Returns the amount of hours from another date
    func hours(from date: Date) -> Int {
        return Calendar.current.dateComponents([.hour], from: date, to: self).hour ?? 0
    }
    /// Returns the amount of minutes from another date
    func minutes(from date: Date) -> Int {
        return Calendar.current.dateComponents([.minute], from: date, to: self).minute ?? 0
    }
    /// Returns the amount of seconds from another date
    func seconds(from date: Date) -> Int {
        return Calendar.current.dateComponents([.second], from: date, to: self).second ?? 0
    }
    /// Returns the a custom time interval description from another date
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
    
    subscript(userInfo key: Key) -> [AnyHashable: Any]? {
        get {
            return self[key] as? [AnyHashable: Any]
        }
        set {
            self[key] = newValue as? Value
        }
    }
    
    subscript(string key: Key) -> String? {
        get {
            return self[key] as? String
        }
        
        set {
            self[key] = newValue as? Value
        }
    }
    
    subscript(list key: Key) -> [AnyObject]? {
        get {
            return self[key] as? [AnyObject]
        }
        
        set {
            self[key] = newValue as? Value
        }
    }
    
    subscript(boolValue key: Key) -> Bool {
        get {
            return self[key] as? Bool ?? false
        }
        
        set {
            self[key] = newValue as? Value
        }
    }
}


extension UserDefaults {
    static var shared: UserDefaults {
        let combined = UserDefaults.standard
        combined.addSuite(named: Utility.getAppGroupInfo)
        return combined
    }
    
    struct Key<Value> {
        var name: String
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
    
    static var permissionState: UserDefaults.Key<String> {
        return .init(name: UserDefaultConstant.permissionState)
    }
    
    static var ispermissionAlerted: UserDefaults.Key<Bool> {
        return .init(name: UserDefaultConstant.ispermissionAlertedKey)
    }
    
    static var deviceToken: UserDefaults.Key<String> {
        return .init(name: UserDefaultConstant.deviceToken)
    }
    
    static var badgeCount: UserDefaults.Key<Int> {
        return .init(name: UserDefaultConstant.badgeCount)
    }
    
    static var subscriberHash: UserDefaults.Key<String> {
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
        return .init(name: UserDefaultConstant.istriedFirstTime)
    }
    
    static var isSponseredIdKey: UserDefaults.Key<String> {
        return .init(name: UserDefaultConstant.sponsered)
    }
    
    static var isSwizzled: UserDefaults.Key<Bool> {
        return .init(name: UserDefaultConstant.isSwizziled)
    }
}
