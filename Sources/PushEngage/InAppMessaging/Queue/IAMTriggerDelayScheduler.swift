import Foundation

/// Reads `trigger.delay` and works out how much of it is left.
enum IAMTriggerDelay {

    /// Seconds still to wait before this campaign may be shown, or `0` when it
    /// declares no delay or the window has already elapsed.
    ///
    /// Measured from `appOpenAt` rather than from now, so time spent in the
    /// app-open sync counts toward the delay instead of being added on top of it:
    /// the effective display time is `max(appOpen + delay, syncComplete)`.
    ///
    /// - Parameters:
    ///   - triggerJSON: the campaign's stored trigger
    ///   - appOpenAt: monotonic time of the app-open instant, or nil when there is
    ///     no recorded one (auto triggers evaluated outside the app-open path)
    ///   - now: current monotonic time
    static func remaining(triggerJSON: Data?,
                          appOpenAt: TimeInterval?,
                          now: TimeInterval) -> TimeInterval {
        guard let triggerJSON = triggerJSON,
              let trigger = (try? JSONSerialization.jsonObject(with: triggerJSON)) as? [String: Any] else {
            return 0
        }

        // The wire field is `delay` and its unit is SECONDS — unitless name,
        // matching frequency.interval and displayDuration.
        guard let number = trigger["delay"] as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return 0
        }
        let delaySeconds = number.doubleValue
        guard delaySeconds > 0 else { return 0 }

        // No recorded app-open instant: fall back to delaying from now.
        guard let appOpenAt = appOpenAt else { return delaySeconds }

        return max(0, appOpenAt + delaySeconds - now)
    }
}

/// One pending countdown. Injectable so tests drive the clock instead of sleeping.
protocol IAMDelayTimer: AnyObject {
    func cancel()
}

protocol IAMDelayTimerFactory {
    func timer(after delay: TimeInterval, _ fire: @escaping () -> Void) -> IAMDelayTimer
}

/// Production timers: a cancellable work item on the given queue.
struct IAMDispatchDelayTimerFactory: IAMDelayTimerFactory {

    let queue: DispatchQueue

    init(queue: DispatchQueue = .main) {
        self.queue = queue
    }

    func timer(after delay: TimeInterval, _ fire: @escaping () -> Void) -> IAMDelayTimer {
        let item = DispatchWorkItem(block: fire)
        queue.asyncAfter(deadline: .now() + delay, execute: item)
        return Timer(item: item)
    }

    private final class Timer: IAMDelayTimer {
        private let item: DispatchWorkItem
        init(item: DispatchWorkItem) { self.item = item }
        func cancel() { item.cancel() }
    }
}

/// Pausable countdown for app-open campaigns that declare `trigger.delay`.
///
/// - **App open only.** Custom (`on event`) triggers ignore `delay`; this
///   scheduler is only fed from the auto-trigger path.
/// - **Backgrounding freezes the countdown** and returning resumes it with the
///   time that was left — background time never counts toward the delay. A 5s
///   delay backgrounded at 2s still has 3s to run when the app comes back.
/// - **Origin is app open, gated on the sync.** Callers pass the *remaining*
///   delay, computed from the app-open instant by `IAMTriggerDelay`.
///
/// Deliberately in-memory only: app open fires once per process, so if the process
/// dies the next launch re-fires app open and the delay starts over.
/// Countdowns are keyed by campaign id and carry no managed object: a sync
/// full-replaces the campaign set, so the row behind a pending countdown can be
/// deleted while it waits. The receiver re-reads the campaign at release.
final class IAMTriggerDelayScheduler {

    private final class Pending {
        let messageId: String
        var remaining: TimeInterval
        var startedAt: TimeInterval
        var timer: IAMDelayTimer?

        init(messageId: String, remaining: TimeInterval, startedAt: TimeInterval) {
            self.messageId = messageId
            self.remaining = remaining
            self.startedAt = startedAt
        }
    }

    private let lock = NSRecursiveLock()
    private var pending: [String: Pending] = [:]
    private var order: [String] = []
    private var isPaused = false

    private let clock: () -> TimeInterval
    private let timerFactory: IAMDelayTimerFactory
    private let onDue: (String) -> Void

    /// - Parameters:
    ///   - clock: monotonic time source. `systemUptime` rather than wall time, so a
    ///     clock change cannot skip or stall a countdown.
    ///   - timerFactory: how delayed work is scheduled
    ///   - onDue: called with a campaign id once its delay has been served. The
    ///     receiver must re-read the campaign — it may no longer exist.
    init(clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         timerFactory: IAMDelayTimerFactory = IAMDispatchDelayTimerFactory(),
         onDue: @escaping (String) -> Void) {
        self.clock = clock
        self.timerFactory = timerFactory
        self.onDue = onDue
    }

    /// Number of countdowns still waiting.
    var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return pending.count
    }

    /// Schedules the campaign `messageId` to be released after `delay` seconds of
    /// foreground time.
    ///
    /// A non-positive delay releases it immediately. Re-scheduling an id that is
    /// already waiting is ignored, so a repeated evaluation cannot double-queue it.
    func schedule(messageId: String, after delay: TimeInterval) {
        guard delay > 0 else {
            onDue(messageId)
            return
        }

        lock.lock()
        if pending[messageId] != nil {
            lock.unlock()
            PELogger.debug(
                className: String(describing: IAMTriggerDelayScheduler.self),
                message: "IAM delay: message \(messageId) already waiting — ignoring re-schedule"
            )
            return
        }

        pending[messageId] = Pending(messageId: messageId, remaining: delay, startedAt: clock())
        order.append(messageId)
        let paused = isPaused
        if !paused { start(messageId) }
        lock.unlock()

        PELogger.debug(
            className: String(describing: IAMTriggerDelayScheduler.self),
            message: "IAM delay: message \(messageId) scheduled in \(delay)s"
                + (paused ? " (paused — will start on resume)" : "")
        )
    }

    /// Freezes every countdown, banking the time already served.
    func pause() {
        lock.lock()
        defer { lock.unlock() }
        guard !isPaused else { return }
        isPaused = true

        let now = clock()
        for entry in pending.values {
            entry.timer?.cancel()
            entry.timer = nil
            entry.remaining = max(0, entry.remaining - (now - entry.startedAt))
        }
        if !pending.isEmpty {
            PELogger.debug(
                className: String(describing: IAMTriggerDelayScheduler.self),
                message: "IAM delay: paused \(pending.count) pending countdown(s)"
            )
        }
    }

    /// Restarts every countdown from the time that was left when `pause` ran.
    func resume() {
        lock.lock()
        defer { lock.unlock() }
        guard isPaused else { return }
        isPaused = false

        for messageId in order where pending[messageId] != nil {
            start(messageId)
        }
        if !pending.isEmpty {
            PELogger.debug(
                className: String(describing: IAMTriggerDelayScheduler.self),
                message: "IAM delay: resumed \(pending.count) pending countdown(s)"
            )
        }
    }

    /// Drops every pending countdown without releasing the messages.
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        pending.values.forEach { $0.timer?.cancel() }
        pending.removeAll()
        order.removeAll()
    }

    private func start(_ messageId: String) {
        guard let entry = pending[messageId] else { return }
        entry.startedAt = clock()
        entry.timer = timerFactory.timer(after: entry.remaining) { [weak self] in
            self?.release(messageId)
        }
    }

    /// Releases a due message. `onDue` runs *outside* the lock — it enqueues into
    /// the queue manager, which takes its own lock.
    private func release(_ messageId: String) {
        lock.lock()
        let entry = pending.removeValue(forKey: messageId)
        order.removeAll { $0 == messageId }
        lock.unlock()

        guard entry != nil else { return }
        PELogger.debug(
            className: String(describing: IAMTriggerDelayScheduler.self),
            message: "IAM delay: message \(messageId) delay elapsed — releasing to queue"
        )
        onDue(messageId)
    }
}
