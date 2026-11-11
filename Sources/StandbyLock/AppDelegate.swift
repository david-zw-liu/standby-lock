import AppKit
import Carbon
import ServiceManagement
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var passwordWindow: PasswordWindowController?
    private let lock = LockController.shared

    private let lockItem = NSMenuItem(title: "立即鎖定", action: #selector(lockNow), keyEquivalent: "l")
    private let passwordItem = NSMenuItem(title: "設定密碼…", action: #selector(showPasswordWindow), keyEquivalent: "")
    private let preventSleepItem = NSMenuItem(title: "鎖定時阻止睡眠", action: #selector(togglePreventSleep), keyEquivalent: "")
    private let accessibilityItem = NSMenuItem(title: "授權輔助使用權限…", action: #selector(requestAccessibility), keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "登入時自動啟動", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let idleMenu = NSMenu()
    private let maskSlider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: nil, action: nil)
    private let maskLabel = NSTextField(labelWithString: "")
    private let resetBackgroundItem = NSMenuItem(title: "使用預設背景", action: #selector(resetBackground), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Settings.registerDefaults()
        setupStatusItem()

        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(shiftKey | optionKey | cmdKey)) { [weak self] in
            self?.lockNow()
        }

        if CommandLine.arguments.contains("--lock") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.lockNow() }
        } else if !PasswordStore.hasPassword {
            showPasswordWindow()
        } else if !KeyboardGuard.hasPermission {
            KeyboardGuard.requestPermission()
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
            button.toolTip = "StandbyLock ─ ⇧⌥⌘L 鎖定"
        }

        let menu = NSMenu()
        menu.delegate = self

        lockItem.keyEquivalentModifierMask = [.shift, .option, .command]
        for item in [lockItem, passwordItem, preventSleepItem, accessibilityItem, launchAtLoginItem] {
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

        let backgroundItem = NSMenuItem(title: "背景圖片", action: nil, keyEquivalent: "")
        let backgroundMenu = NSMenu()
        let chooseItem = NSMenuItem(title: "選擇圖片…", action: #selector(chooseBackground), keyEquivalent: "")
        chooseItem.target = self
        resetBackgroundItem.target = self
        backgroundMenu.addItem(chooseItem)
        backgroundMenu.addItem(resetBackgroundItem)
        backgroundItem.submenu = backgroundMenu
        menu.addItem(backgroundItem)

        let maskItem = NSMenuItem()
        maskItem.view = makeMaskView()
        menu.addItem(maskItem)

        menu.addItem(preventSleepItem)
        menu.addItem(launchAtLoginItem)
        menu.addItem(accessibilityItem)
        menu.addItem(.separator())

        let about = NSMenuItem(title: "關於 StandbyLock", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        let quit = NSMenuItem(title: "結束 StandbyLock", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    /// 選單內嵌的遮罩滑桿：上方標題與百分比，下方滑桿。
    private func makeMaskView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 50))
        maskLabel.font = .menuFont(ofSize: 0)
        maskLabel.frame = NSRect(x: 20, y: 27, width: 200, height: 18)
        maskSlider.frame = NSRect(x: 20, y: 4, width: 200, height: 22)
        maskSlider.isContinuous = true
        maskSlider.target = self
        maskSlider.action = #selector(maskSliderChanged(_:))
        for subview in [maskLabel, maskSlider] {
            subview.autoresizingMask = [.width]
            view.addSubview(subview)
        }
        return view
    }

    private func updateMaskControls() {
        let percent = Settings.maskPercent
        maskSlider.integerValue = percent
        maskLabel.stringValue = "背景遮罩程度：\(percent)%"
        maskSlider.isEnabled = Background.hasImage
        maskLabel.textColor = Background.hasImage ? .labelColor : .disabledControlTextColor
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        lockItem.title = PasswordStore.hasPassword ? "立即鎖定" : "立即鎖定（請先設定密碼）"
        passwordItem.title = PasswordStore.hasPassword ? "變更密碼…" : "設定密碼…"
        preventSleepItem.state = Settings.preventSleepWhileLocked ? .on : .off
        accessibilityItem.isHidden = KeyboardGuard.hasPermission
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        for item in idleMenu.items {
            item.state = item.tag == Settings.idleLockMinutes ? .on : .off
        }
        resetBackgroundItem.state = Background.hasImage ? .off : .on
        updateMaskControls()
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
            if PasswordStore.hasPassword, !KeyboardGuard.hasPermission {
                self?.requestAccessibility()
            }
        }
        passwordWindow = controller
        controller.present()
    }

    @objc private func selectIdleMinutes(_ sender: NSMenuItem) {
        Settings.idleLockMinutes = sender.tag
        lock.restartIdleMonitor()
    }

    @objc private func chooseBackground() {
        let panel = NSOpenPanel()
        panel.title = "選擇鎖定畫面背景圖片"
        panel.prompt = "選擇"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Background.setImage(from: url)
        } catch {
            let alert = NSAlert()
            alert.messageText = "無法使用這張圖片"
            alert.informativeText = "請改選 JPEG、PNG 或 HEIC 等常見格式的圖片。\n\n\(error.localizedDescription)"
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    @objc private func resetBackground() {
        Background.clearImage()
    }

    @objc private func maskSliderChanged(_ sender: NSSlider) {
        Settings.maskPercent = Int(sender.doubleValue.rounded())
        updateMaskControls()
    }

    @objc private func togglePreventSleep() {
        Settings.preventSleepWhileLocked.toggle()
    }

    @objc private func requestAccessibility() {
        KeyboardGuard.requestPermission()
        let alert = NSAlert()
        alert.messageText = "需要「輔助使用」權限"
        alert.informativeText = "鎖定時要攔截 ⌘ / ⌃ 系統快捷鍵（Spotlight、Mission Control 等），macOS 要求在「系統設定 › 隱私權與安全性 › 輔助使用」中允許 StandbyLock。授權後下次鎖定即會生效；未授權時鎖定畫面仍可正常使用。"
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

        • ⇧⌥⌘L 或選單「立即鎖定」進入鎖定畫面
        • 鎖定期間阻止電腦進入睡眠，並攔截系統快捷鍵
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
