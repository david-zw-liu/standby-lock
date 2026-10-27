import AppKit
import ApplicationServices

/// 鎖定期間透過 CGEventTap 吃掉所有帶 ⌘ / ⌃ 的按鍵，避免 Spotlight、Mission Control 等系統快捷鍵。
/// 需要「輔助使用」權限；沒有權限時靜默跳過，鎖定畫面本身仍然有效。
final class KeyboardGuard {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isActive: Bool { tap != nil }

    static var hasPermission: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func start() {
        guard tap == nil, Self.hasPermission else { return }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            return Unmanaged<KeyboardGuard>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CFMachPortInvalidate(tap)
        self.tap = nil
        runLoopSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
}
