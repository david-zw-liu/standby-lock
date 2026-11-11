import Foundation

enum Settings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let preventSleepWhileLocked = "preventSleepWhileLocked"
        static let idleLockMinutes = "idleLockMinutes"
        static let backgroundImageFileName = "backgroundImageFileName"
        static let maskPercent = "maskPercent"
    }

    static let idleLockChoices: [Int] = [0, 1, 3, 5, 10, 30]

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.preventSleepWhileLocked: true,
            Key.idleLockMinutes: 0,
            Key.maskPercent: 50,
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

    /// 背景圖在 Application Support/StandbyLock 內的檔名；nil 表示使用預設漸層。
    static var backgroundImageFileName: String? {
        get { defaults.string(forKey: Key.backgroundImageFileName) }
        set { defaults.set(newValue, forKey: Key.backgroundImageFileName) }
    }

    /// 背景遮罩程度，0–100。
    static var maskPercent: Int {
        get { Mask.clamp(defaults.integer(forKey: Key.maskPercent)) }
        set { defaults.set(Mask.clamp(newValue), forKey: Key.maskPercent) }
    }
}
