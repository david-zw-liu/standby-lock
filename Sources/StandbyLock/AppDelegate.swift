import AppKit
import Carbon
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var passwordWindow: PasswordWindowController?
    private let lock = LockController.shared

    private let lockItem = NSMenuItem(title: "立即鎖定", action: #selector(lockNow), keyEquivalent: "l")
    private let passwordItem = NSMenuItem(title: "設定密碼…", action: #selector(showPasswordWindow), keyEquivalent: "")
    private let preventSleepItem = NSMenuItem(title: "鎖定時阻止睡眠", action: #selector(togglePreventSleep), keyEquivalent: "")
    private let blockShortcutsItem = NSMenuItem(title: "鎖定時攔截系統快捷鍵", action: #selector(toggleBlockShortcuts), keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "登入時自動啟動", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let idleMenu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Settings.registerDefaults()
        setupStatusItem()

        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(controlKey | optionKey | cmdKey)) { [weak self] in
            self?.lockNow()
        }

        if CommandLine.arguments.contains("--lock") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.lockNow() }
        } else if !PasswordStore.hasPassword {
            showPasswordWindow()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        lock.isLocked ? .terminateCancel : .terminateNow
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "StandbyLock")
            button.toolTip = "StandbyLock ─ ⌃⌥⌘L 鎖定"
        }

        let menu = NSMenu()
        menu.delegate = self

        lockItem.keyEquivalentModifierMask = [.control, .option, .command]
        for item in [lockItem, passwordItem, preventSleepItem, blockShortcutsItem, launchAtLoginItem] {
            item.target = self
        }

        menu.addItem(lockItem)
        menu.addItem(.separator())
        menu.addItem(passwordItem)

        let idleItem = NSMenuItem(title: "閒置自動鎖定", action: nil, keyEquivalent: "")
        for minutes in Settings.idleLockChoices {
            let title = minutes == 0 ? "關閉" : "\(minutes) 分鐘後"
            let item = NSMenuItem(title: title, action: #selector(selectIdleMinutes(_:)), keyEquivalent: "")
            item.tag = minutes
            item.target = self
            idleMenu.addItem(item)
        }
        idleItem.submenu = idleMenu
        menu.addItem(idleItem)

        menu.addItem(preventSleepItem)
        menu.addItem(blockShortcutsItem)
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())

        let about = NSMenuItem(title: "關於 StandbyLock", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let quit = NSMenuItem(title: "結束 StandbyLock", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        lockItem.title = PasswordStore.hasPassword ? "立即鎖定" : "立即鎖定（請先設定密碼）"
        passwordItem.title = PasswordStore.hasPassword ? "變更密碼…" : "設定密碼…"
        preventSleepItem.state = Settings.preventSleepWhileLocked ? .on : .off
        blockShortcutsItem.state = Settings.blockSystemShortcuts ? .on : .off
        blockShortcutsItem.title = Settings.blockSystemShortcuts && !KeyboardGuard.hasPermission
            ? "鎖定時攔截系統快捷鍵（尚未授權輔助使用）"
            : "鎖定時攔截系統快捷鍵"
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        for item in idleMenu.items {
            item.state = item.tag == Settings.idleLockMinutes ? .on : .off
        }
    }

    // MARK: - Actions

    @objc private func lockNow() {
        guard PasswordStore.hasPassword else {
            showPasswordWindow()
            return
        }
        passwordWindow?.close()
        lock.lock()
    }

    @objc private func showPasswordWindow() {
        if let existing = passwordWindow, existing.window?.isVisible == true {
            existing.present()
            return
        }
        let controller = PasswordWindowController()
        controller.onPasswordChanged = { [weak self] in
            self?.passwordWindow = nil
        }
        passwordWindow = controller
        controller.present()
    }

    @objc private func selectIdleMinutes(_ sender: NSMenuItem) {
        Settings.idleLockMinutes = sender.tag
        lock.restartIdleMonitor()
    }

    @objc private func togglePreventSleep() {
        Settings.preventSleepWhileLocked.toggle()
    }

    @objc private func toggleBlockShortcuts() {
        let enabling = !Settings.blockSystemShortcuts
        Settings.blockSystemShortcuts = enabling
        guard enabling, !KeyboardGuard.hasPermission else { return }

        KeyboardGuard.requestPermission()
        let alert = NSAlert()
        alert.messageText = "需要「輔助使用」權限"
        alert.informativeText = "攔截 ⌘ / ⌃ 系統快捷鍵需要在「系統設定 › 隱私權與安全性 › 輔助使用」中允許 StandbyLock。授權後下次鎖定即會生效；未授權時鎖定畫面仍可正常使用。"
        alert.addButton(withTitle: "開啟系統設定")
        alert.addButton(withTitle: "稍後")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.informativeText = "請確認 StandbyLock.app 位於「應用程式」資料夾後再試一次。"
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "StandbyLock"
        alert.informativeText = """
        macOS 待機鎖定工具。

        • ⌃⌥⌘L 或選單「立即鎖定」進入鎖定畫面
        • 鎖定期間阻止電腦進入睡眠
        • 需輸入待機密碼才能解鎖
        """
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
