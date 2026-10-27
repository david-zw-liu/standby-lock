import AppKit

final class LockWindow: NSWindow {
    let isPrimary: Bool
    private weak var controller: LockController?

    private var passwordField: NSSecureTextField?
    private var messageLabel: NSTextField?
    private var timeLabel: NSTextField!
    private var dateLabel: NSTextField!
    private var clockTimer: Timer?
    private var lockoutTimer: Timer?

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "M月d日 EEEE"
        return f
    }()

    init(screen: NSScreen, isPrimary: Bool, controller: LockController) {
        self.isPrimary = isPrimary
        self.controller = controller
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)

        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = true
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)
        backgroundColor = NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.11, alpha: 1)
        setFrame(screen.frame, display: true)

        buildContent()
        updateClock()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateClock()
        }
    }

    override var canBecomeKey: Bool { isPrimary }
    override var canBecomeMain: Bool { isPrimary }

    override func cancelOperation(_ sender: Any?) {}
    override func performClose(_ sender: Any?) {}
    override func performMiniaturize(_ sender: Any?) {}

    func tearDown() {
        clockTimer?.invalidate()
        clockTimer = nil
        lockoutTimer?.invalidate()
        lockoutTimer = nil
    }

    func focusPasswordField() {
        guard let passwordField, passwordField.isEnabled, passwordField.currentEditor() == nil else { return }
        makeFirstResponder(passwordField)
    }

    // MARK: - UI

    private func buildContent() {
        let root = NSView(frame: NSRect(origin: .zero, size: frame.size))
        let gradient = CAGradientLayer()
        gradient.colors = [
            NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.18, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.08, alpha: 1).cgColor,
        ]
        gradient.startPoint = CGPoint(x: 0.5, y: 1)
        gradient.endPoint = CGPoint(x: 0.5, y: 0)
        root.layer = gradient
        root.wantsLayer = true
        contentView = root

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: -40),
        ])

        timeLabel = makeLabel(font: .monospacedDigitSystemFont(ofSize: 104, weight: .thin), color: .white)
        dateLabel = makeLabel(font: .systemFont(ofSize: 22, weight: .regular), color: NSColor.white.withAlphaComponent(0.75))
        stack.addArrangedSubview(timeLabel)
        stack.addArrangedSubview(dateLabel)
        stack.setCustomSpacing(44, after: dateLabel)

        let iconView = NSImageView()
        iconView.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "已鎖定")
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 34, weight: .regular)
        iconView.contentTintColor = NSColor.white.withAlphaComponent(0.85)
        stack.addArrangedSubview(iconView)
        stack.setCustomSpacing(18, after: iconView)

        if isPrimary {
            let field = NSSecureTextField()
            field.placeholderString = "輸入密碼解鎖"
            field.font = .systemFont(ofSize: 17)
            field.alignment = .center
            field.bezelStyle = .roundedBezel
            field.focusRingType = .none
            field.target = self
            field.action = #selector(submit)
            field.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                field.widthAnchor.constraint(equalToConstant: 300),
                field.heightAnchor.constraint(equalToConstant: 36),
            ])
            field.wantsLayer = true
            passwordField = field
            stack.addArrangedSubview(field)

            let message = makeLabel(font: .systemFont(ofSize: 14), color: NSColor.systemRed.blended(withFraction: 0.25, of: .white) ?? .systemRed)
            message.heightAnchor.constraint(equalToConstant: 20).isActive = true
            messageLabel = message
            stack.addArrangedSubview(message)

            let hint = makeLabel(font: .systemFont(ofSize: 12), color: NSColor.white.withAlphaComponent(0.45))
            hint.stringValue = "按 Return 解鎖"
            stack.addArrangedSubview(hint)
        } else {
            let hint = makeLabel(font: .systemFont(ofSize: 16), color: NSColor.white.withAlphaComponent(0.6))
            hint.stringValue = "請在主螢幕輸入密碼解鎖"
            stack.addArrangedSubview(hint)
        }
    }

    private func makeLabel(font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = font
        label.textColor = color
        label.alignment = .center
        label.isSelectable = false
        return label
    }

    private func updateClock() {
        let now = Date()
        timeLabel.stringValue = Self.timeFormatter.string(from: now)
        dateLabel.stringValue = Self.dateFormatter.string(from: now)
    }

    // MARK: - Unlock flow

    @objc private func submit() {
        guard let passwordField, let controller else { return }
        let password = passwordField.stringValue
        passwordField.stringValue = ""
        guard !password.isEmpty else { return }

        switch controller.attempt(password: password) {
        case .unlocked:
            break
        case .wrong(let remaining):
            shake(passwordField)
            messageLabel?.stringValue = remaining <= 2
                ? "密碼錯誤，再錯 \(remaining) 次將暫停輸入 30 秒"
                : "密碼錯誤"
            focusPasswordField()
        case .lockedOut(let seconds):
            shake(passwordField)
            beginLockout(seconds: seconds)
        }
    }

    private func beginLockout(seconds: Int) {
        guard let passwordField else { return }
        passwordField.isEnabled = false
        var remaining = seconds
        messageLabel?.stringValue = "嘗試次數過多，請等待 \(remaining) 秒"
        lockoutTimer?.invalidate()
        lockoutTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            remaining -= 1
            if remaining <= 0 {
                timer.invalidate()
                self.lockoutTimer = nil
                self.messageLabel?.stringValue = ""
                passwordField.isEnabled = true
                self.focusPasswordField()
            } else {
                self.messageLabel?.stringValue = "嘗試次數過多，請等待 \(remaining) 秒"
            }
        }
    }

    private func shake(_ view: NSView) {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.values = [0, -14, 12, -9, 6, -3, 0]
        animation.duration = 0.4
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        view.layer?.add(animation, forKey: "shake")
    }
}
