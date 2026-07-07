//
//  PEPlatform.swift
//  PushEngage
//
//  String constants for the platform-flavor segment of the SDK User-Agent.
//  Wrapper SDKs (and tests) can reference these to avoid typos, but the
//  field accepts any sanitized string — the SDK does not gatekeep new wrappers.
//
//  Mirrors `com.pushengage.pushengage.helper.PEPlatform` on the Android side.
//

import Foundation

@objcMembers public final class PEPlatform: NSObject {
    public static let iOS              = "iOS"
    public static let flutterIOS       = "FlutterIOS"
    public static let reactNativeIOS   = "ReactNativeIOS"

    private override init() { super.init() }
}
