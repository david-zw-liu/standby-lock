import Foundation

enum Settings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let preventSleepWhileLocked = "preventSleepWhileLocked"
        static let idleLockMinutes = "idleLockMinutes"
    }

    static let idleLockChoices: [Int] = [0, 1, 3, 5, 10, 30]

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.preventSleepWhileLocked: true,
            Key.idleLockMinutes: 0,
        ])
    }

    static var preventSleepWhileLocked: Bool {
        get { defaults.bool(forKey: Key.preventSleepWhileLocked) }
        set { defaults.set(newValue, forKey: Key.preventSleepWhileLocked) }
    }

    static var idleLockMinutes: Int {
        get { defaults.integer(forKey: Key.idleLockMinutes) }
        set { defaults.set(newValue, forKey: Key.idleLockMinutes) }
    }
}
