import AppKit

extension Notification.Name {
    static let lockStateDidChange = Notification.Name("StandbyLock.lockStateDidChange")
}

final class LockController {
    static let shared = LockController()

    enum AttemptResult {
        case unlocked
        case wrong(remainingBeforeLockout: Int)
        case lockedOut(seconds: Int)
    }

    private let maxAttempts = 5
    private let lockoutSeconds: TimeInterval = 30

    private(set) var isLocked = false
    private var windows: [LockWindow] = []
    private let sleepPreventer = SleepPreventer()
    private let keyboardGuard = KeyboardGuard()
    private var observerRemovers: [() -> Void] = []
    private var watchdog: Timer?
    private var idleTimer: Timer?
    private var failedAttempts = 0
    private var lockoutUntil: Date?

    private init() {
        startIdleMonitor()
    }

    var isPreventingSleep: Bool { sleepPreventer.isActive }
    var isBlockingShortcuts: Bool { keyboardGuard.isActive }

    func lock() {
        guard !isLocked, PasswordStore.hasPassword else { return }
        isLocked = true
        failedAttempts = 0
        lockoutUntil = nil

        NSApp.presentationOptions = [
            .hideDock, .hideMenuBar,
            .disableProcessSwitching, .disableForceQuit,
            .disableSessionTermination, .disableHideApplication,
        ]
        if Settings.preventSleepWhileLocked { sleepPreventer.start() }
        if Settings.blockSystemShortcuts { keyboardGuard.start() }

        buildWindows()
        installObservers()
        bringToFront()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.bringToFront()
        }
        NotificationCenter.default.post(name: .lockStateDidChange, object: nil)
    }

    func unlock() {
        guard isLocked else { return }
        isLocked = false
        watchdog?.invalidate()
        watchdog = nil
        observerRemovers.forEach { $0() }
        observerRemovers = []
        tearDownWindows()
        keyboardGuard.stop()
        sleepPreventer.stop()
        NSApp.presentationOptions = []
        failedAttempts = 0
        lockoutUntil = nil
        NotificationCenter.default.post(name: .lockStateDidChange, object: nil)
    }

    func attempt(password: String) -> AttemptResult {
        if let until = lockoutUntil, until > Date() {
            return .lockedOut(seconds: Int(until.timeIntervalSinceNow.rounded(.up)))
        }
        lockoutUntil = nil
        if PasswordStore.verify(password) {
            unlock()
            return .unlocked
        }
        failedAttempts += 1
        if failedAttempts >= maxAttempts {
            failedAttempts = 0
            lockoutUntil = Date().addingTimeInterval(lockoutSeconds)
            return .lockedOut(seconds: Int(lockoutSeconds))
        }
        return .wrong(remainingBeforeLockout: maxAttempts - failedAttempts)
    }

    // MARK: - Windows

    private func buildWindows() {
        tearDownWindows()
        let screens = NSScreen.screens
        windows = screens.enumerated().map { index, screen in
            LockWindow(screen: screen, isPrimary: index == 0, controller: self)
        }
        windows.forEach { $0.orderFrontRegardless() }
    }

    private func tearDownWindows() {
        windows.forEach {
            $0.tearDown()
            $0.orderOut(nil)
        }
        windows = []
    }

    private func bringToFront() {
        guard isLocked else { return }
        if !NSApp.isActive {
            NSApp.activate(ignoringOtherApps: true)
        }
        windows.forEach { $0.orderFrontRegardless() }
        guard let primary = windows.first(where: { $0.isPrimary }) else { return }
        if !primary.isKeyWindow {
            primary.makeKeyAndOrderFront(nil)
        }
        primary.focusPasswordField()
    }

    private func installObservers() {
        let center = NSCenterPair(center: NotificationCenter.default)
        let workspace = NSCenterPair(center: NSWorkspace.shared.notificationCenter)

        observerRemovers.append(center.observe(NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.buildWindows()
            self?.bringToFront()
        })
        observerRemovers.append(center.observe(NSApplication.didResignActiveNotification) { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self?.bringToFront() }
        })
        observerRemovers.append(workspace.observe(NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in
            self?.bringToFront()
        })
        observerRemovers.append(workspace.observe(NSWorkspace.didWakeNotification) { [weak self] in
            self?.bringToFront()
        })
        observerRemovers.append(workspace.observe(NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.bringToFront()
        })
    }

    // MARK: - Idle auto-lock

    func restartIdleMonitor() {
        startIdleMonitor()
    }

    private func startIdleMonitor() {
        idleTimer?.invalidate()
        idleTimer = nil
        let minutes = Settings.idleLockMinutes
        guard minutes > 0 else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, !self.isLocked, PasswordStore.hasPassword else { return }
            let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
            if idle >= TimeInterval(minutes * 60) {
                self.lock()
            }
        }
    }
}

private struct NSCenterPair {
    let center: NotificationCenter

    func observe(_ name: Notification.Name, handler: @escaping () -> Void) -> () -> Void {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in handler() }
        return { [center] in center.removeObserver(token) }
    }
}
