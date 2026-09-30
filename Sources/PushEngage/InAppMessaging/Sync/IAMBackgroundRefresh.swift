import Foundation
import BackgroundTasks

/// Out-of-foreground campaign refresh, closing the last gap to Android's 6 h WorkManager
/// job (`SYNC_INTERVAL_HOURS = 6`).
///
/// The in-process `Timer` in `IAMSyncManager` cannot do this: it does not fire while the
/// app is backgrounded and dies with the process, so before this an iOS device only ever
/// refreshed campaigns on app open.
///
/// **The host app must opt in.** `BGTaskScheduler` refuses an identifier the app has not
/// declared, and no SDK can declare it on the host's behalf. An integrator has to add, to
/// their app's Info.plist:
///
/// ```xml
/// <key>BGTaskSchedulerPermittedIdentifiers</key>
/// <array><string>com.pushengage.iam.refresh</string></array>
/// ```
///
/// plus the **Background Modes → Background fetch** capability. Without both, this type
/// logs one actionable error and does nothing — IAM keeps working, refreshing on app open
/// exactly as before, so a host that never opts in is no worse off than today.
///
/// **This is opportunistic, not a schedule.** iOS decides when (and whether) a refresh
/// task runs, weighing usage patterns, battery and network. `earliestBeginDate` is a floor,
/// never a promise, so app open remains the dominant refresh path on iOS even with this
/// enabled. That is a platform difference from Android's job, not something the SDK can
/// close.
final class IAMBackgroundRefresh {

    static let shared = IAMBackgroundRefresh()

    /// Task identifier the host must permit. Changing this is a breaking change for every
    /// integrator that has already declared it.
    static let taskIdentifier = "com.pushengage.iam.refresh"

    /// Matches `IAMSyncManager.syncInterval` and Android's 6 h job.
    private let refreshInterval: TimeInterval = 21600

    private let syncManager: IAMSyncManager
    private var didRegister = false

    init(syncManager: IAMSyncManager = .shared) {
        self.syncManager = syncManager
    }

    /// Registers the launch handler. **Must be called before `didFinishLaunching`
    /// returns** — `BGTaskScheduler` raises if a handler is registered after launch — so
    /// this runs synchronously from `IAMController`'s initialiser, which the SDK builds
    /// inside `setInitialInfo`. Safe to call more than once.
    func registerIfPermitted() {
        guard !didRegister else { return }

        guard hostPermitsTaskIdentifier else {
            PELogger.error(
                className: String(describing: IAMBackgroundRefresh.self),
                message: "IAM background refresh disabled: the host app has not declared "
                    + "\"\(Self.taskIdentifier)\" in BGTaskSchedulerPermittedIdentifiers. "
                    + "Add it to Info.plist and enable Background Modes → Background "
                    + "fetch to let campaigns refresh outside the foreground. IAM still "
                    + "refreshes on app open without this."
            )
            return
        }

        didRegister = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil
        ) { [weak self] task in
            self?.handle(task)
        }

        if didRegister {
            PELogger.debug(
                className: String(describing: IAMBackgroundRefresh.self),
                message: "IAM background refresh registered for \(Self.taskIdentifier)"
            )
        } else {
            PELogger.error(
                className: String(describing: IAMBackgroundRefresh.self),
                message: "IAM background refresh registration was refused for "
                    + "\(Self.taskIdentifier) — check the Info.plist identifier matches "
                    + "exactly and that registration happens during didFinishLaunching"
            )
        }
    }

    /// Asks the system for the next refresh. No-op unless registration succeeded, so a
    /// host that has not opted in never submits a request that can only fail.
    func scheduleNext() {
        guard didRegister else { return }

        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: refreshInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
            PELogger.debug(
                className: String(describing: IAMBackgroundRefresh.self),
                message: "IAM background refresh scheduled no earlier than "
                    + "\(refreshInterval / 3600) h from now"
            )
        } catch {
            // Submission legitimately fails when the user has switched Background App
            // Refresh off, or too many requests are pending. Not fatal: app open still
            // refreshes.
            PELogger.error(
                className: String(describing: IAMBackgroundRefresh.self),
                message: "IAM background refresh could not be scheduled: "
                    + "\(error.localizedDescription)"
            )
        }
    }

    private func handle(_ task: BGTask) {
        // Chain the next refresh FIRST. iOS grants one run per request, so a request
        // submitted only after a successful sync would end the chain permanently the
        // first time a sync failed or the task was expired mid-flight.
        scheduleNext()

        // The system kills the app if setTaskCompleted is called twice, and expiry
        // races a completing sync, so the outcome is reported exactly once. The
        // expiration handler and the sync completion arrive on different threads, so
        // the check-and-set needs the lock; setTaskCompleted is called outside it.
        let finishLock = NSLock()
        var finished = false
        let finish: (Bool) -> Void = { success in
            finishLock.lock()
            if finished {
                finishLock.unlock()
                return
            }
            finished = true
            finishLock.unlock()
            task.setTaskCompleted(success: success)
        }

        task.expirationHandler = {
            PELogger.error(
                className: String(describing: IAMBackgroundRefresh.self),
                message: "IAM background refresh expired before the sync finished"
            )
            // Reported as a failure because it is one: the campaigns were not refreshed.
            // Claiming success would teach the scheduler this work is cheap.
            finish(false)
        }

        PELogger.debug(
            className: String(describing: IAMBackgroundRefresh.self),
            message: "IAM background refresh running"
        )

        // Campaigns only. Analytics and triggers are deliberately left to the foreground:
        // this window is short, and a partially-uploaded analytics batch is worse than a
        // late one.
        syncManager.syncMessages { error in
            if let error = error {
                PELogger.error(
                    className: String(describing: IAMBackgroundRefresh.self),
                    message: "IAM background refresh sync failed: \(error.localizedDescription)"
                )
            }
            finish(error == nil)
        }
    }

    /// Whether the host declared our identifier. Checked before registering so an
    /// unprepared host gets one clear log line instead of a system refusal.
    private var hostPermitsTaskIdentifier: Bool {
        let declared = Bundle.main.object(
            forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers"
        ) as? [String]
        return declared?.contains(Self.taskIdentifier) ?? false
    }
}
