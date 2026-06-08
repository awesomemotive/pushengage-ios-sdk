//
//  SdkEventLog.swift
//  PushEngageExample
//
//  App-wide event log for demo results. Mirrors Android's
//  `SdkEventLog` / `loggingCallback` — every screen routes its
//  PushEngage callback through here so a user can scroll through
//  the full session history from the bottom panel on HomeViewController.
//

import Foundation

/// Notification posted whenever a new entry is appended or the log is cleared.
extension Notification.Name {
    static let sdkEventLogDidChange = Notification.Name("SdkEventLog.didChange")
}

final class SdkEventLog {

    static let shared = SdkEventLog()

    private init() {}

    private let queue = DispatchQueue(label: "com.pushengage.demo.eventlog", attributes: .concurrent)
    private var _entries: [String] = []

    /// Thread-safe snapshot of the current log entries (newest at the bottom).
    var entries: [String] {
        queue.sync { _entries }
    }

    /// Convenience: a single string with one entry per line, ready to render in
    /// a `UITextView`.
    var renderedText: String {
        queue.sync { _entries.joined(separator: "\n") }
    }

    var count: Int {
        queue.sync { _entries.count }
    }

    /// Appends a timestamped entry and broadcasts `.sdkEventLogDidChange`.
    func append(_ message: String) {
        let timestamp = DateFormatter.sdkEventLog.string(from: Date())
        let line = "[\(timestamp)] \(message)"
        queue.async(flags: .barrier) { [weak self] in
            self?._entries.append(line)
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .sdkEventLogDidChange, object: self)
            }
        }
    }

    /// Wipes all entries.
    func clear() {
        queue.async(flags: .barrier) { [weak self] in
            self?._entries.removeAll()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .sdkEventLogDidChange, object: self)
            }
        }
    }
}

private extension DateFormatter {
    static let sdkEventLog: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
