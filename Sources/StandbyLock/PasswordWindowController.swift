import AppKit

final class PasswordWindowController: NSWindowController {
    private let currentField = NSSecureTextField()
    private let newField = NSSecureTextField()
    private let confirmField = NSSecureTextField()
    private let errorLabel = NSTextField(labelWithString: "")
    private let hasExisting = PasswordStore.hasPassword

    var onPasswordChanged: (() -> Void)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 10),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = hasExisting ? "變更待機密碼" : "設定待機密碼"
        window.isReleasedWhenClosed = false
        window.level = .floating
        super.init(window: window)
        buildContent()
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    func present() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(hasExisting ? currentField : newField)
    }

    private func buildContent() {
        guard let window, let content = window.contentView else { return }

        let intro = NSTextField(wrappingLabelWithString: hasExisting
            ? "輸入目前密碼後設定新密碼。鎖定時需輸入此密碼才能繼續使用電腦。"
            : "設定一組待機密碼。鎖定時需輸入此密碼才能繼續使用電腦。")
        intro.font = .systemFont(ofSize: 12)
        intro.textColor = .secondaryLabelColor

        for field in [currentField, newField, confirmField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 240).isActive = true
            field.target = self
            field.action = #selector(save)
        }

        let grid = NSGridView(views: [
            [label("目前密碼"), currentField],
            [label("新密碼"), newField],
            [label("確認新密碼"), confirmField],
        ])
        grid.rowSpacing = 10
        grid.columnSpacing = 12
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        if !hasExisting { grid.row(at: 0).isHidden = true }

        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .systemRed
        errorLabel.alignment = .left
        errorLabel.heightAnchor.constraint(equalToConstant: 16).isActive = true

        let cancel = NSButton(title: "取消", target: self, action: #selector(cancel))
        cancel.keyEquivalent = "\u{1b}"
        let saveButton = NSButton(title: "儲存", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        let remove = NSButton(title: "移除密碼", target: self, action: #selector(removePassword))
        remove.isHidden = !hasExisting

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [remove, spacer, cancel, saveButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [intro, grid, errorLabel, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            intro.widthAnchor.constraint(equalToConstant: 360),
            buttons.widthAnchor.constraint(equalTo: intro.widthAnchor),
            grid.centerXAnchor.constraint(equalTo: stack.centerXAnchor),
        ])
    }

    private func label(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.alignment = .right
        return l
    }

    private func fail(_ message: String, focus: NSTextField) {
        errorLabel.stringValue = message
        window?.makeFirstResponder(focus)
        NSSound.beep()
    }

    @objc private func save() {
        if hasExisting && !PasswordStore.verify(currentField.stringValue) {
            fail("目前密碼不正確", focus: currentField)
            return
        }
        let newPassword = newField.stringValue
        if newPassword.count < PasswordStore.minimumLength {
            fail("新密碼至少需要 \(PasswordStore.minimumLength) 個字元", focus: newField)
            return
        }
        if newPassword != confirmField.stringValue {
            fail("兩次輸入的密碼不一致", focus: confirmField)
            return
        }
        PasswordStore.setPassword(newPassword)
        close()
        onPasswordChanged?()
    }

    @objc private func removePassword() {
        guard PasswordStore.verify(currentField.stringValue) else {
            fail("請先輸入正確的目前密碼", focus: currentField)
            return
        }
        PasswordStore.clear()
        close()
        onPasswordChanged?()
    }

    @objc private func cancel() {
        close()
    }
}
