import Foundation

final class SleepPreventer {
    private var activity: NSObjectProtocol?

    var isActive: Bool { activity != nil }

    func start() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleDisplaySleepDisabled, .idleSystemSleepDisabled],
            reason: "StandbyLock 鎖定中，避免電腦進入睡眠"
        )
    }

    func stop() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }
}
