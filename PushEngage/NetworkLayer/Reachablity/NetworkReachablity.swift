//
//  NetworkReachablity.swift
//  PushEngage
//
//  Created by Abhishek on 26/03/21.
//

import Foundation
import SystemConfiguration


class NetworkConnectivity {
    class var isConnectedToInternet: Bool {
        return NetworkReachabilityManager()?.isReachable ?? false
    }
}

class NetworkReachabilityManager {
    
    enum NetworkReachabilityStatus {
        case unknown
        case notReachable
        case reachable(ConnectionType)
    }

    enum ConnectionType {
        case ethernetOrWiFi
        case wwan
    }

    typealias Listener = (NetworkReachabilityStatus) -> Void

    // MARK: - Properties

    var isReachable: Bool { return isReachableOnWWAN || isReachableOnEthernetOrWiFi }

    var isReachableOnWWAN: Bool { return networkReachabilityStatus == .reachable(.wwan) }

    var isReachableOnEthernetOrWiFi: Bool { return networkReachabilityStatus == .reachable(.ethernetOrWiFi) }

    var networkReachabilityStatus: NetworkReachabilityStatus {
        guard let flags = self.flags else { return .unknown }
        return networkReachabilityStatusForFlags(flags)
    }
    var listenerQueue: DispatchQueue = DispatchQueue.main

    var listener: Listener?

    var flags: SCNetworkReachabilityFlags? {
        var flags = SCNetworkReachabilityFlags()

        if SCNetworkReachabilityGetFlags(reachability, &flags) {
            return flags
        }

        return nil
    }

    private let reachability: SCNetworkReachability
    var previousFlags: SCNetworkReachabilityFlags

    // MARK: - Initialization

     convenience init?(host: String) {
        guard let reachability = SCNetworkReachabilityCreateWithName(nil, host) else { return nil }
        self.init(reachability: reachability)
     }
    
    /// Reachability treats the 0.0.0.0 address as a special token that causes it to monitor the general routing
    /// status of the device, both IPv4 and IPv6.
    /// - returns: The new `NetworkReachabilityManager` instance.
    public convenience init?() {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)

        guard let reachability = withUnsafePointer(to: &address, { pointer in
            return pointer.withMemoryRebound(to: sockaddr.self, capacity: MemoryLayout<sockaddr>.size) {
                return SCNetworkReachabilityCreateWithAddress(nil, $0)
            }
        }) else { return nil }

        self.init(reachability: reachability)
    }

    private init(reachability: SCNetworkReachability) {
        self.reachability = reachability

        // Set the previous flags to an unreserved value to represent unknown status
        self.previousFlags = SCNetworkReachabilityFlags(rawValue: 1 << 30)
    }

    deinit {
        stopListening()
    }

    // MARK: - Listening

    @discardableResult
    open func startListening() -> Bool {
        var context = SCNetworkReachabilityContext(version: 0,
                                                   info: nil,
                                                   retain: nil,
                                                   release: nil,
                                                   copyDescription: nil)
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let callbackEnabled = SCNetworkReachabilitySetCallback(
            reachability, { (_, flags, info) in
                let reachability = Unmanaged<NetworkReachabilityManager>.fromOpaque(info!).takeUnretainedValue()
                reachability.notifyListener(flags)
            },
            &context
        )

        let queueEnabled = SCNetworkReachabilitySetDispatchQueue(reachability, listenerQueue)

        listenerQueue.async {
            self.previousFlags = SCNetworkReachabilityFlags(rawValue: 1 << 30)

            guard let flags = self.flags else { return }

            self.notifyListener(flags)
        }

        return callbackEnabled && queueEnabled
    }

    open func stopListening() {
        SCNetworkReachabilitySetCallback(reachability, nil, nil)
        SCNetworkReachabilitySetDispatchQueue(reachability, nil)
    }

    // MARK: - Internal - Listener Notification

    func notifyListener(_ flags: SCNetworkReachabilityFlags) {
        guard previousFlags != flags else { return }
        previousFlags = flags

        listener?(networkReachabilityStatusForFlags(flags))
    }

    // MARK: - Internal - Network Reachability Status

    func networkReachabilityStatusForFlags(_ flags: SCNetworkReachabilityFlags) -> NetworkReachabilityStatus {
        guard isNetworkReachable(with: flags) else { return .notReachable }

        var networkStatus: NetworkReachabilityStatus = .reachable(.ethernetOrWiFi)

    #if os(iOS)
        if flags.contains(.isWWAN) { networkStatus = .reachable(.wwan) }
    #endif

        return networkStatus
    }

    func isNetworkReachable(with flags: SCNetworkReachabilityFlags) -> Bool {
        let isReachable = flags.contains(.reachable)
        let needsConnection = flags.contains(.connectionRequired)
        let canConnectAutomatically = flags.contains(.connectionOnDemand) || flags.contains(.connectionOnTraffic)
        let canConnectWithoutUserInteraction = canConnectAutomatically && !flags.contains(.interventionRequired)

        return isReachable && (!needsConnection || canConnectWithoutUserInteraction)
    }
}

// MARK: -

extension NetworkReachabilityManager.NetworkReachabilityStatus: Equatable {}

/// Returns whether the two network reachability status values are equal.
///
/// - parameter lhs: The left-hand side value to compare.
/// - parameter rhs: The right-hand side value to compare.
///
/// - returns: `true` if the two values are equal, `false` otherwise.
 func == (lhs: NetworkReachabilityManager.NetworkReachabilityStatus,
          rhs: NetworkReachabilityManager.NetworkReachabilityStatus) -> Bool {
    switch (lhs, rhs) {
    case (.unknown, .unknown):
        return true
    case (.notReachable, .notReachable):
        return true
    case let (.reachable(lhsConnectionType), .reachable(rhsConnectionType)):
        return lhsConnectionType == rhsConnectionType
    default:
        return false
    }
}

