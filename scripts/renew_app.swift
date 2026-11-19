import AppKit
import Foundation

// MARK: - Palette & type

enum Palette {
    static let paper = NSColor(hex: 0xF7F1E7)
    static let card = NSColor(hex: 0xFFFCF6)
    static let ink = NSColor(hex: 0x241F1A)
    static let muted = NSColor(hex: 0x75695C)
    static let faint = NSColor(hex: 0x8C7F6F)
    static let line = NSColor(hex: 0xE7DBC9)
    static let tomato = NSColor(hex: 0xD94A2E)
    static let tomatoDark = NSColor(hex: 0xB7351F)
    static let button = NSColor(hex: 0xC84226)
    static let buttonDark = NSColor(hex: 0xA9321B)
    static let tomatoSoft = NSColor(hex: 0xF7E1D8)
    static let sage = NSColor(hex: 0x4F6B4A)
    static let sageSoft = NSColor(hex: 0xE6EDE2)
    static let amber = NSColor(hex: 0x8F5A17)
    static let amberSoft = NSColor(hex: 0xF4E8D5)
    static let logBG = NSColor(hex: 0x28231F)
    static let logText = NSColor(hex: 0xD8CDBF)
    static let logMuted = NSColor(hex: 0x9C8F80)
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

enum Typeface {
    static func display(_ size: CGFloat) -> NSFont {
        NSFont(name: "STSongti-SC-Bold", size: size)
            ?? NSFont(name: "STSong", size: size)
            ?? .systemFont(ofSize: size, weight: .bold)
    }

    static func body(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        .systemFont(ofSize: size, weight: weight)
    }

    static func number(_ size: CGFloat) -> NSFont {
        NSFont(name: "Georgia-Bold", size: size)
            ?? .systemFont(ofSize: size, weight: .bold)
    }

    static func mono(_ size: CGFloat) -> NSFont {
        NSFont(name: "Menlo-Regular", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

// MARK: - Small native views

final class PaperBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Palette.paper.setFill()
        dirtyRect.fill()

        // A faint seal in the upper-right margin: paper, not chrome.
        let seal = NSRect(x: bounds.maxX - 218, y: bounds.maxY - 190, width: 250, height: 250)
        Palette.tomato.withAlphaComponent(0.035).setFill()
        NSBezierPath(ovalIn: seal).fill()

        let ring = NSBezierPath(ovalIn: seal.insetBy(dx: 12, dy: 12))
        ring.lineWidth = 1
        Palette.tomato.withAlphaComponent(0.06).setStroke()
        ring.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: Typeface.display(78),
            .foregroundColor: Palette.tomato.withAlphaComponent(0.05),
        ]
        let glyph = NSAttributedString(string: "续", attributes: attributes)
        let size = glyph.size()
        glyph.draw(at: NSPoint(x: seal.midX - size.width / 2, y: seal.midY - size.height / 2))
    }
}

final class CardView: NSView {
    init(fill: NSColor = Palette.card, radius: CGFloat = 18, border: NSColor? = Palette.line, shadow: Bool = true) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = fill.cgColor
        layer?.cornerRadius = radius
        layer?.borderWidth = border == nil ? 0 : 1
        layer?.borderColor = border?.cgColor
        if shadow {
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = 0.06
            layer?.shadowRadius = 18
            layer?.shadowOffset = CGSize(width: 0, height: -5)
        }
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class ProgressRailView: NSView {
    var accentColor: NSColor = Palette.tomato {
        didSet { needsDisplay = true }
    }

    var doubleValue: Double = 0 {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 8)
    }

    override func draw(_ dirtyRect: NSRect) {
        let height: CGFloat = 7
        let y = bounds.midY - height / 2
        let track = NSBezierPath(
            roundedRect: NSRect(x: 0, y: y, width: bounds.width, height: height),
            xRadius: height / 2,
            yRadius: height / 2
        )
        Palette.line.setFill()
        track.fill()

        let fraction = CGFloat(min(max(doubleValue, 0), 100) / 100)
        let fillWidth = bounds.width * fraction
        guard fillWidth > 0 else { return }

        let fill = NSBezierPath(
            roundedRect: NSRect(x: 0, y: y, width: max(fillWidth, height), height: height),
            xRadius: height / 2,
            yRadius: height / 2
        )
        accentColor.setFill()
        fill.fill()

        let marker = NSBezierPath(
            ovalIn: NSRect(x: max(0, fillWidth - 4), y: bounds.midY - 4, width: 8, height: 8)
        )
        Palette.card.setFill()
        marker.fill()
        accentColor.setStroke()
        marker.lineWidth = 1.5
        marker.stroke()
    }
}

final class BadgeView: NSView {
    private let label = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 11
        translatesAutoresizingMaskIntoConstraints = false

        label.font = Typeface.body(10.5, .medium)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func set(_ text: String, fill: NSColor, textColor: NSColor) {
        label.stringValue = text
        label.textColor = textColor
        layer?.backgroundColor = fill.cgColor
    }
}

final class CalloutView: NSView {
    private let label = NSTextField(wrappingLabelWithString: "")

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        translatesAutoresizingMaskIntoConstraints = false

        label.font = Typeface.body(11)
        label.maximumNumberOfLines = 4
        label.lineBreakMode = .byWordWrapping
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),
            heightAnchor.constraint(equalToConstant: 62),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func set(_ text: String, fill: NSColor, textColor: NSColor) {
        label.stringValue = text
        label.textColor = textColor
        layer?.backgroundColor = fill.cgColor
    }
}

final class StepDotView: NSView {
    enum State { case pending, active, done, failed }

    var state: State = .pending {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 18, height: 18) }

    override func draw(_ dirtyRect: NSRect) {
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        switch state {
        case .pending:
            let rect = NSRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)
            let path = NSBezierPath(ovalIn: rect)
            Palette.card.setFill()
            path.fill()
            Palette.line.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        case .active:
            let outer = NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: 18, height: 18))
            Palette.tomatoSoft.setFill()
            outer.fill()
            let inner = NSBezierPath(ovalIn: NSRect(x: center.x - 4, y: center.y - 4, width: 8, height: 8))
            Palette.tomato.setFill()
            inner.fill()
        case .done:
            let circle = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 16, height: 16))
            Palette.sage.setFill()
            circle.fill()
            let check = NSBezierPath()
            check.move(to: NSPoint(x: 4.5, y: 9.5))
            check.line(to: NSPoint(x: 7.4, y: 6.3))
            check.line(to: NSPoint(x: 13.2, y: 12.2))
            check.lineWidth = 1.8
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.white.setStroke()
            check.stroke()
        case .failed:
            let circle = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: 16, height: 16))
            Palette.tomato.setFill()
            circle.fill()
            let cross = NSBezierPath()
            cross.move(to: NSPoint(x: 6, y: 6))
            cross.line(to: NSPoint(x: 12, y: 12))
            cross.move(to: NSPoint(x: 12, y: 6))
            cross.line(to: NSPoint(x: 6, y: 12))
            cross.lineWidth = 1.8
            cross.lineCapStyle = .round
            NSColor.white.setStroke()
            cross.stroke()
        }
    }
}

final class TimelineStepView: NSView {
    let dot = StepDotView()
    private let numberLabel: NSTextField
    private let titleLabel: NSTextField
    private let lineTop = NSView()
    private let lineBottom = NSView()

    init(index: Int, title: String, isFirst: Bool, isLast: Bool) {
        numberLabel = NSTextField(labelWithString: String(format: "%02d", index + 1))
        titleLabel = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 29).isActive = true

        for line in [lineTop, lineBottom] {
            line.wantsLayer = true
            line.layer?.backgroundColor = Palette.line.cgColor
            line.translatesAutoresizingMaskIntoConstraints = false
            addSubview(line)
        }
        lineTop.isHidden = isFirst
        lineBottom.isHidden = isLast

        dot.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dot)

        numberLabel.font = Typeface.mono(9)
        numberLabel.textColor = Palette.faint
        numberLabel.alignment = .left
        numberLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(numberLabel)

        titleLabel.font = Typeface.body(13)
        titleLabel.textColor = Palette.muted
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: leadingAnchor),
            dot.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 18),
            dot.heightAnchor.constraint(equalToConstant: 18),

            lineTop.widthAnchor.constraint(equalToConstant: 1),
            lineTop.centerXAnchor.constraint(equalTo: dot.centerXAnchor),
            lineTop.topAnchor.constraint(equalTo: topAnchor),
            lineTop.bottomAnchor.constraint(equalTo: dot.centerYAnchor),
            lineBottom.widthAnchor.constraint(equalToConstant: 1),
            lineBottom.centerXAnchor.constraint(equalTo: dot.centerXAnchor),
            lineBottom.topAnchor.constraint(equalTo: dot.centerYAnchor),
            lineBottom.bottomAnchor.constraint(equalTo: bottomAnchor),

            numberLabel.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 8),
            numberLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            numberLabel.widthAnchor.constraint(equalToConstant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: numberLabel.trailingAnchor, constant: 5),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setState(_ state: StepDotView.State) {
        dot.state = state
        let doneLine = Palette.sage.withAlphaComponent(0.35)
        let pendingLine = Palette.line
        switch state {
        case .pending:
            numberLabel.textColor = Palette.faint
            titleLabel.textColor = Palette.muted
            titleLabel.font = Typeface.body(13)
            lineTop.layer?.backgroundColor = pendingLine.cgColor
            lineBottom.layer?.backgroundColor = pendingLine.cgColor
        case .active:
            numberLabel.textColor = Palette.tomato
            titleLabel.textColor = Palette.tomato
            titleLabel.font = Typeface.body(13, .semibold)
            lineTop.layer?.backgroundColor = doneLine.cgColor
            lineBottom.layer?.backgroundColor = pendingLine.cgColor
        case .done:
            numberLabel.textColor = Palette.faint
            titleLabel.textColor = Palette.ink
            titleLabel.font = Typeface.body(13)
            lineTop.layer?.backgroundColor = doneLine.cgColor
            lineBottom.layer?.backgroundColor = doneLine.cgColor
        case .failed:
            numberLabel.textColor = Palette.tomato
            titleLabel.textColor = Palette.tomato
            titleLabel.font = Typeface.body(13, .semibold)
            lineTop.layer?.backgroundColor = doneLine.cgColor
            lineBottom.layer?.backgroundColor = pendingLine.cgColor
        }
    }
}

final class FilledButton: NSButton {
    private var tracking: NSTrackingArea?
    private var hovering = false

    init(title: String, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 12
        alignment = .center
        font = Typeface.body(13.5, .semibold)
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: Typeface.body(13.5, .semibold),
                .foregroundColor: NSColor.white,
            ]
        )
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 42).isActive = true
        widthAnchor.constraint(greaterThanOrEqualToConstant: 154).isActive = true
        updateColor()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        updateColor()
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        updateColor()
    }

    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = Palette.buttonDark.cgColor
        super.mouseDown(with: event)
        updateColor()
    }

    private func updateColor() {
        layer?.backgroundColor = (hovering ? Palette.buttonDark : Palette.button).cgColor
    }
}

final class TextButton: NSButton {
    init(title: String, target: AnyObject?, action: Selector?, color: NSColor = Palette.muted, size: CGFloat = 11.5) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        alignment = .center
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: Typeface.body(size),
                .foregroundColor: color,
            ]
        )
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

// MARK: - App

@main
struct RenewAppMain {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        delegate.installMenu()
        app.finishLaunching()
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    // Replaced by scripts/build_renew_app.sh with the actual checkout path.
    private let projectDir = URL(fileURLWithPath: "__PROJECT_DIR__")
    private var scriptPath: String { projectDir.appendingPathComponent("scripts/renew_fqapp.sh").path }
    private var installScriptPath: String { projectDir.appendingPathComponent("scripts/install_to_iphone.sh").path }

    private let logDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/fqapp", isDirectory: true)
    private var statusURL: URL { logDir.appendingPathComponent("last-status.txt") }
    private var summaryURL: URL { logDir.appendingPathComponent("last-renewal.txt") }
    private var progressURL: URL { logDir.appendingPathComponent("progress.txt") }

    private var window: NSWindow!
    private var rootStack: NSStackView!
    private var phaseBadge: BadgeView!
    private var privacyBadge: BadgeView!
    private var statusLabel: NSTextField!
    private var detailLabel: NSTextField!
    private var percentBlock: NSStackView!
    private var percentLabel: NSTextField!
    private var percentUnitLabel: NSTextField!
    private var percentCaptionLabel: NSTextField!
    private var heroMetaLabel: NSTextField!
    private var heroNoteLabel: NSTextField!
    private var progressBar: ProgressRailView!
    private var spinner: NSProgressIndicator!
    private var stepRows: [TimelineStepView] = []
    private var logPreviewLabel: NSTextField!
    private var liveDot: NSView!
    private var logButton: TextButton!
    private var startButton: FilledButton!
    private var retryButton: FilledButton!
    private var trustCheckButton: FilledButton!
    private var closeButton: TextButton!
    private var hintLabel: NSTextField!
    private var voucherStageLabel: NSTextField!
    private var voucherStateLabel: NSTextField!
    private var voucherExpiryLabel: NSTextField!
    private var voucherDataLabel: NSTextField!
    private var voucherNote: CalloutView!

    private let stepLabels = ["检查环境", "准备依赖", "检查设备与证书", "构建与签名", "安装到 iPhone", "启动 App"]
    private let stepThresholds: [Double] = [2, 12, 20, 30, 82, 94]

    private var process: Process?
    private var pipe: Pipe?
    private var trustCheckProcess: Process?
    private var recentLogLines: [String] = []
    private var logTimer: Timer?
    private var tickTimer: Timer?
    private var incomingText = ""
    private var lastProgressContent = ""
    private var currentProgress: Double = 0
    private var isRunning = false
    private var buildPhase = false

    private static let ansiRegex = try! NSRegularExpression(
        pattern: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]|\u{001B}\\][^\u{0007}]*\u{0007}",
        options: []
    )

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: "com.weixiaoxun.renew-fqapp")
            .filter { $0.processIdentifier != currentPID }
        if let other = others.first {
            other.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
            return
        }
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        buildUI()
        if let index = CommandLine.arguments.firstIndex(of: "--preview"),
           index + 1 < CommandLine.arguments.count {
            applyPreview(CommandLine.arguments[index + 1])
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot"),
           index + 1 < CommandLine.arguments.count {
            let path = CommandLine.arguments[index + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                self?.saveSnapshot(to: path)
                NSApp.terminate(nil)
            }
        }
        if CommandLine.arguments.contains("--autostart") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.startRenewal()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        stopTimers()
        if let process, process.isRunning { process.terminate() }
        if let trustCheckProcess, trustCheckProcess.isRunning { trustCheckProcess.terminate() }
    }

    func windowWillClose(_ notification: Notification) {
        if let process, process.isRunning { process.terminate() }
        if let trustCheckProcess, trustCheckProcess.isRunning { trustCheckProcess.terminate() }
    }

    func installMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "退出续签番茄小镇",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        NSApp.mainMenu = mainMenu
    }

    // MARK: - Build UI

    private func buildUI() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 740),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "续签番茄小镇"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Palette.paper
        window.appearance = NSAppearance(named: .aqua)
        window.isMovableByWindowBackground = true
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false

        let content = PaperBackgroundView()
        window.contentView = content

        rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .leading
        rootStack.spacing = 16
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            rootStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            rootStack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -22),
        ])

        // Header
        let iconView = NSImageView()
        iconView.image = loadIcon()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 14
        iconView.layer?.masksToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.widthAnchor.constraint(equalToConstant: 54).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 54).isActive = true

        let titleLabel = NSTextField(labelWithString: "续签番茄小镇")
        titleLabel.font = Typeface.display(28)
        titleLabel.textColor = Palette.ink

        let subtitleLabel = NSTextField(labelWithString: "本地重新签名，书架与进度原样保留")
        subtitleLabel.font = Typeface.body(12)
        subtitleLabel.textColor = Palette.muted

        let titleStack = NSStackView(views: [titleLabel, subtitleLabel])
        titleStack.orientation = .vertical
        titleStack.alignment = .leading
        titleStack.spacing = 3

        privacyBadge = BadgeView()
        privacyBadge.set("本地 · 私有", fill: Palette.sageSoft, textColor: Palette.sage)

        let header = NSStackView(views: [iconView, titleStack, NSView(), privacyBadge])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 14
        addFullWidth(header, to: rootStack)

        // Hero card
        let hero = CardView(radius: 20)
        hero.translatesAutoresizingMaskIntoConstraints = false
        rootStack.addArrangedSubview(hero)
        hero.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        hero.heightAnchor.constraint(equalToConstant: 176).isActive = true

        let heroStack = NSStackView()
        heroStack.orientation = .vertical
        heroStack.alignment = .leading
        heroStack.spacing = 7
        heroStack.translatesAutoresizingMaskIntoConstraints = false
        hero.addSubview(heroStack)
        NSLayoutConstraint.activate([
            heroStack.leadingAnchor.constraint(equalTo: hero.leadingAnchor, constant: 20),
            heroStack.trailingAnchor.constraint(equalTo: hero.trailingAnchor, constant: -20),
            heroStack.topAnchor.constraint(equalTo: hero.topAnchor, constant: 18),
            heroStack.bottomAnchor.constraint(lessThanOrEqualTo: hero.bottomAnchor, constant: -16),
        ])

        phaseBadge = BadgeView()
        phaseBadge.set("待开始", fill: Palette.tomatoSoft, textColor: Palette.tomatoDark)

        percentLabel = NSTextField(labelWithString: "0")
        percentLabel.font = Typeface.number(42)
        percentLabel.textColor = Palette.ink
        percentLabel.alignment = .right

        percentUnitLabel = NSTextField(labelWithString: "%")
        percentUnitLabel.font = Typeface.body(14, .medium)
        percentUnitLabel.textColor = Palette.muted
        percentUnitLabel.alignment = .left

        let percentStack = NSStackView(views: [percentLabel, percentUnitLabel])
        percentStack.orientation = .horizontal
        percentStack.alignment = .lastBaseline
        percentStack.spacing = 2

        percentCaptionLabel = NSTextField(labelWithString: "总体进度")
        percentCaptionLabel.font = Typeface.body(10.5)
        percentCaptionLabel.textColor = Palette.muted
        percentCaptionLabel.alignment = .right

        percentBlock = NSStackView(views: [percentStack, percentCaptionLabel])
        percentBlock.orientation = .vertical
        percentBlock.alignment = .trailing
        percentBlock.spacing = 0
        percentBlock.isHidden = true

        heroMetaLabel = NSTextField(labelWithString: "不离开这台 Mac")
        heroMetaLabel.font = Typeface.body(10.5)
        heroMetaLabel.textColor = Palette.muted
        heroMetaLabel.alignment = .right

        let topRow = NSStackView(views: [phaseBadge, NSView(), percentBlock, heroMetaLabel])
        topRow.orientation = .horizontal
        topRow.alignment = .centerY
        topRow.spacing = 12
        addFullWidth(topRow, to: heroStack)

        statusLabel = NSTextField(labelWithString: "准备续签")
        statusLabel.font = Typeface.display(23)
        statusLabel.textColor = Palette.ink
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.widthAnchor.constraint(equalToConstant: 18).isActive = true
        spinner.heightAnchor.constraint(equalToConstant: 18).isActive = true

        let statusRow = NSStackView(views: [statusLabel, spinner, NSView()])
        statusRow.orientation = .horizontal
        statusRow.alignment = .centerY
        statusRow.spacing = 8
        addFullWidth(statusRow, to: heroStack)

        detailLabel = NSTextField(wrappingLabelWithString: "解锁 iPhone 并保持亮屏，然后开始。")
        detailLabel.font = Typeface.body(12.5)
        detailLabel.textColor = Palette.muted
        detailLabel.maximumNumberOfLines = 2
        detailLabel.lineBreakMode = .byTruncatingTail
        addFullWidth(detailLabel, to: heroStack)

        heroNoteLabel = NSTextField(labelWithString: "“把新的 7 天，续在旧的书页上。”")
        heroNoteLabel.font = Typeface.display(15)
        heroNoteLabel.textColor = Palette.tomatoDark.withAlphaComponent(0.72)
        addFullWidth(heroNoteLabel, to: heroStack)

        progressBar = ProgressRailView()
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBar.heightAnchor.constraint(equalToConstant: 8).isActive = true
        progressBar.setAccessibilityRole(.progressIndicator)
        progressBar.setAccessibilityLabel("续签总体进度")
        progressBar.isHidden = true
        addFullWidth(progressBar, to: heroStack)

        // Primary action sits directly under the hero, above the details.
        startButton = FilledButton(title: "开始续签", target: self, action: #selector(startRenewal))
        retryButton = FilledButton(title: "重试续签", target: self, action: #selector(startRenewal))
        retryButton.isHidden = true
        trustCheckButton = FilledButton(title: "我已信任，重新检查", target: self, action: #selector(checkTrust))
        trustCheckButton.isHidden = true
        closeButton = TextButton(title: "关闭", target: NSApp, action: #selector(NSApplication.terminate(_:)), color: Palette.muted, size: 12)

        hintLabel = NSTextField(labelWithString: "预计 1–3 分钟")
        hintLabel.font = Typeface.body(11)
        hintLabel.textColor = Palette.muted

        let actions = NSStackView(views: [startButton, retryButton, trustCheckButton, hintLabel, NSView(), closeButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 12
        addFullWidth(actions, to: rootStack)

        // Columns
        let timelineCard = makeTimelineCard()
        let voucherCard = makeVoucherCard()
        timelineCard.heightAnchor.constraint(equalToConstant: 240).isActive = true
        voucherCard.heightAnchor.constraint(equalToConstant: 240).isActive = true

        let columns = NSStackView(views: [timelineCard, voucherCard])
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.distribution = .fillEqually
        columns.spacing = 16
        addFullWidth(columns, to: rootStack)

        // Quiet technical strip, never a dominant console.
        let logCard = makeLogCard()
        rootStack.addArrangedSubview(logCard)
        logCard.widthAnchor.constraint(equalTo: rootStack.widthAnchor).isActive = true
        logCard.heightAnchor.constraint(equalToConstant: 78).isActive = true

        let footer = NSTextField(labelWithString: "签名材料只保存在本机 · 不经过任何服务器")
        footer.font = Typeface.body(10.5)
        footer.textColor = Palette.muted
        addFullWidth(footer, to: rootStack)

        updateSteps(for: 0)
        setLiveDot(Palette.line)
        voucherStageLabel.stringValue = "开始前"
        voucherStateLabel.stringValue = "等待开始"
        voucherStateLabel.textColor = Palette.ink
        voucherExpiryLabel.stringValue = "—"
        voucherDataLabel.stringValue = "保留"
        voucherNote.set("覆盖安装，不会清除书架与进度。", fill: Palette.tomatoSoft, textColor: Palette.tomatoDark)
    }

    private func addFullWidth(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    private func addFullWidth(_ view: NSView) {
        addFullWidth(view, to: rootStack)
    }

    private func makeTimelineCard() -> CardView {
        let card = CardView(radius: 18)

        let heading = NSTextField(labelWithString: "续签流程")
        heading.font = Typeface.body(11, .semibold)
        heading.textColor = Palette.muted

        let count = NSTextField(labelWithString: "6 个阶段")
        count.font = Typeface.body(10.5)
        count.textColor = Palette.faint
        count.alignment = .right

        let headerRow = NSStackView(views: [heading, NSView(), count])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 8

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        for (index, title) in stepLabels.enumerated() {
            let row = TimelineStepView(
                index: index,
                title: title,
                isFirst: index == 0,
                isLast: index == stepLabels.count - 1
            )
            stack.addArrangedSubview(row)
            stepRows.append(row)
        }

        let inner = NSStackView(views: [headerRow, stack])
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 10
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            inner.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -14),
            headerRow.widthAnchor.constraint(equalTo: inner.widthAnchor),
        ])
        return card
    }

    private func makeVoucherCard() -> CardView {
        let card = CardView(radius: 18)

        let heading = NSTextField(labelWithString: "本次凭证")
        heading.font = Typeface.body(11, .semibold)
        heading.textColor = Palette.muted

        voucherStageLabel = NSTextField(labelWithString: "开始前")
        voucherStageLabel.font = Typeface.body(10.5)
        voucherStageLabel.textColor = Palette.faint
        voucherStageLabel.alignment = .right

        let headerRow = NSStackView(views: [heading, NSView(), voucherStageLabel])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 8

        voucherStateLabel = NSTextField(labelWithString: "等待开始")
        voucherStateLabel.font = Typeface.display(19)
        voucherStateLabel.textColor = Palette.ink
        voucherStateLabel.lineBreakMode = .byTruncatingTail

        voucherExpiryLabel = NSTextField(labelWithString: "—")
        voucherExpiryLabel.font = Typeface.body(11.5, .medium)
        voucherExpiryLabel.textColor = Palette.ink
        voucherExpiryLabel.alignment = .right
        voucherExpiryLabel.lineBreakMode = .byTruncatingTail
        voucherExpiryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        voucherDataLabel = NSTextField(labelWithString: "保留")
        voucherDataLabel.font = Typeface.body(11.5, .medium)
        voucherDataLabel.textColor = Palette.ink
        voucherDataLabel.alignment = .right

        let expiryRow = makeKeyValueRow(key: "新到期日", value: voucherExpiryLabel)
        let dataRow = makeKeyValueRow(key: "书架与进度", value: voucherDataLabel)

        let materialValue = NSTextField(labelWithString: "仅本机")
        materialValue.font = Typeface.body(11.5, .medium)
        materialValue.textColor = Palette.ink
        materialValue.alignment = .right
        let materialRow = makeKeyValueRow(key: "签名材料", value: materialValue)

        voucherNote = CalloutView()

        let inner = NSStackView(views: [headerRow, voucherStateLabel, expiryRow, dataRow, materialRow, voucherNote])
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 7
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            inner.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -14),
            headerRow.widthAnchor.constraint(equalTo: inner.widthAnchor),
            expiryRow.widthAnchor.constraint(equalTo: inner.widthAnchor),
            dataRow.widthAnchor.constraint(equalTo: inner.widthAnchor),
            materialRow.widthAnchor.constraint(equalTo: inner.widthAnchor),
            voucherNote.widthAnchor.constraint(equalTo: inner.widthAnchor),
        ])
        return card
    }

    private func makeKeyValueRow(key: String, value: NSTextField) -> NSView {
        let keyLabel = NSTextField(labelWithString: key)
        keyLabel.font = Typeface.body(11)
        keyLabel.textColor = Palette.muted
        keyLabel.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [keyLabel, NSView(), value])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return row
    }

    private func makeLogCard() -> CardView {
        let card = CardView(radius: 16, shadow: false)

        liveDot = NSView()
        liveDot.wantsLayer = true
        liveDot.layer?.cornerRadius = 3.5
        liveDot.translatesAutoresizingMaskIntoConstraints = false
        liveDot.widthAnchor.constraint(equalToConstant: 7).isActive = true
        liveDot.heightAnchor.constraint(equalToConstant: 7).isActive = true

        let logTitle = NSTextField(labelWithString: "技术详情")
        logTitle.font = Typeface.body(11.5, .medium)
        logTitle.textColor = Palette.muted

        logButton = TextButton(
            title: "打开日志目录",
            target: self,
            action: #selector(openLogs),
            color: Palette.muted,
            size: 10.5
        )

        let header = NSStackView(views: [liveDot, logTitle, NSView(), logButton])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false

        logPreviewLabel = NSTextField(wrappingLabelWithString: "开始后会在这里显示构建进度与错误信息。")
        logPreviewLabel.font = Typeface.mono(10)
        logPreviewLabel.textColor = Palette.muted
        logPreviewLabel.maximumNumberOfLines = 2
        logPreviewLabel.lineBreakMode = .byTruncatingTail
        logPreviewLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        logPreviewLabel.translatesAutoresizingMaskIntoConstraints = false

        let inner = NSStackView(views: [header, logPreviewLabel])
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 6
        inner.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 11),
            inner.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -9),
            header.widthAnchor.constraint(equalTo: inner.widthAnchor),
            logPreviewLabel.widthAnchor.constraint(equalTo: inner.widthAnchor),
        ])
        return card
    }

    private func loadIcon() -> NSImage? {
        if let path = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
           let image = NSImage(contentsOfFile: path) {
            return image
        }
        return NSImage(systemSymbolName: "book.closed.fill", accessibilityDescription: nil)
    }

    // MARK: - Visual state helpers

    private func setPercent(_ value: Double) {
        percentLabel.stringValue = "\(Int(value.rounded()))"
    }

    private func setBadge(_ text: String, fill: NSColor, textColor: NSColor) {
        phaseBadge.set(text, fill: fill, textColor: textColor)
    }

    private func setLiveDot(_ color: NSColor) {
        liveDot.layer?.backgroundColor = color.cgColor
    }

    private func setVoucher(
        _ stage: String,
        state: String,
        stageColor: NSColor = Palette.tomato,
        stateColor: NSColor = Palette.ink
    ) {
        voucherStageLabel.stringValue = stage
        voucherStageLabel.textColor = stageColor
        voucherStateLabel.stringValue = state
        voucherStateLabel.textColor = stateColor
    }

    // MARK: - Actions

    @objc private func openLogs() {
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(logDir)
    }

    @objc private func startRenewal() {
        guard !isRunning else { return }
        guard FileManager.default.fileExists(atPath: scriptPath) else {
            finish(
                state: "failed",
                summary: "找不到续签脚本：\n\(scriptPath)\n请先运行 scripts/build_renew_app.sh 重建。",
                expiry: "",
                exitCode: 1
            )
            return
        }

        isRunning = true
        buildPhase = false
        currentProgress = 0
        lastProgressContent = ""
        incomingText = ""
        recentLogLines.removeAll()
        logPreviewLabel.stringValue = "正在准备续签…"
        setPercent(0)
        progressBar.doubleValue = 0
        progressBar.isHidden = false
        percentBlock.isHidden = false
        heroMetaLabel.isHidden = true
        heroNoteLabel.isHidden = true
        percentUnitLabel.stringValue = "%"
        percentCaptionLabel.stringValue = "总体进度"
        statusLabel.stringValue = "准备续签"
        statusLabel.textColor = Palette.ink
        detailLabel.stringValue = "正在本机构建与签名，请保持 iPhone 解锁。"
        detailLabel.textColor = Palette.muted
        setBadge("进行中", fill: Palette.tomatoSoft, textColor: Palette.tomatoDark)
        progressBar.accentColor = Palette.tomato
        setVoucher("正在进行", state: "构建中", stageColor: Palette.tomatoDark, stateColor: Palette.tomatoDark)
        voucherExpiryLabel.stringValue = "生成中…"
        voucherNote.set("构建期间不要关闭窗口，完成后会尝试自动启动。", fill: Palette.tomatoSoft, textColor: Palette.tomatoDark)
        hintLabel.stringValue = "正在本机运行"
        startButton.isHidden = true
        retryButton.isHidden = true
        trustCheckButton.isHidden = true
        closeButton.isEnabled = true
        spinner.startAnimation(nil)
        setLiveDot(Palette.sage)
        resetSteps()
        setProgress(2, label: "检查环境…")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath]
        var env = ProcessInfo.processInfo.environment
        env["LANG"] = "en_US.UTF-8"
        env["LC_ALL"] = "en_US.UTF-8"
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { self?.consumeOutput(text) }
        }
        process.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async { self?.processFinished(finished) }
        }

        self.process = process
        self.pipe = pipe
        do {
            try process.run()
        } catch {
            finish(state: "failed", summary: "无法启动续签脚本：\(error.localizedDescription)", expiry: "", exitCode: 1)
            return
        }
        startTimers()
    }

    @objc private func checkTrust() {
        guard !isRunning else { return }
        guard FileManager.default.fileExists(atPath: installScriptPath) else {
            finish(state: "needs-trust", summary: "", expiry: readStatus()["expiry"] ?? "", exitCode: 0)
            detailLabel.stringValue = "找不到安装脚本，无法重新检查。请打开日志目录。"
            return
        }

        let expiry = readStatus()["expiry"] ?? ""
        isRunning = true
        spinner.startAnimation(nil)
        startButton.isHidden = true
        retryButton.isHidden = true
        trustCheckButton.isHidden = true
        statusLabel.stringValue = "正在检查 iPhone…"
        statusLabel.textColor = Palette.ink
        detailLabel.stringValue = "确认信任后会尝试直接启动番茄小镇。"
        detailLabel.textColor = Palette.muted
        hintLabel.stringValue = "检查中…"
        logPreviewLabel.stringValue = "正在请求启动“番茄小镇”…"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [installScriptPath, "--launch-only"]
        var env = ProcessInfo.processInfo.environment
        env["LANG"] = "en_US.UTF-8"
        env["LC_ALL"] = "en_US.UTF-8"
        process.environment = env
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finished in
            DispatchQueue.main.async {
                guard let self else { return }
                self.trustCheckProcess = nil
                self.isRunning = false
                self.spinner.stopAnimation(nil)
                if finished.terminationStatus == 0 {
                    self.finish(state: "ok", summary: "", expiry: expiry, exitCode: 0)
                } else {
                    self.finish(state: "needs-trust", summary: "", expiry: expiry, exitCode: 0)
                    self.statusLabel.stringValue = "还没有生效"
                    self.detailLabel.stringValue = "请确认已在 iPhone 上点“信任”，并保持手机解锁，然后再试。"
                    self.trustCheckButton.isHidden = false
                    self.hintLabel.stringValue = "可重新检查"
                    self.setLiveDot(Palette.amber)
                    self.logPreviewLabel.stringValue = "仍未启动：请确认信任状态与手机解锁。"
                }
            }
        }
        trustCheckProcess = process
        do {
            try process.run()
        } catch {
            trustCheckProcess = nil
            isRunning = false
            spinner.stopAnimation(nil)
            finish(state: "needs-trust", summary: "", expiry: expiry, exitCode: 0)
            statusLabel.stringValue = "还没有生效"
            detailLabel.stringValue = "无法执行检查：\(error.localizedDescription)"
            trustCheckButton.isHidden = false
        }
    }

    // MARK: - Output

    private func consumeOutput(_ text: String) {
        incomingText += text
        if incomingText.count > 400_000 {
            incomingText = String(incomingText.suffix(200_000))
        }
    }

    private func flushLog(force: Bool = false) {
        if force { incomingText += "\n" }
        guard !incomingText.isEmpty else { return }
        let normalized = incomingText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = normalized.components(separatedBy: "\n")
        incomingText = lines.removeLast()
        for raw in lines {
            let line = stripANSI(raw).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            appendLogLine(line)
            updateProgress(from: line)
        }
    }

    private func appendLogLine(_ line: String) {
        recentLogLines.append(String(line.prefix(180)))
        if recentLogLines.count > 2 {
            recentLogLines.removeFirst(recentLogLines.count - 2)
        }
        logPreviewLabel.stringValue = recentLogLines.joined(separator: "\n")
    }

    private func stripANSI(_ text: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Self.ansiRegex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }

    private func updateProgress(from line: String) {
        let checks: [(String, Double, String)] = [
            ("==> 更新 CocoaPods", 10, "更新 CocoaPods 依赖…"),
            ("==> CocoaPods 依赖已是最新", 12, "依赖已就绪"),
            ("==> 检查 iPhone 与签名证书", 20, "检查 iPhone 与证书…"),
            ("检查通过：可以开始构建并安装", 28, "设备与签名检查通过"),
            ("==> xcodebuild", 32, "构建与签名（耗时最长）…"),
            ("BUILD SUCCEEDED", 72, "构建成功，校验签名…"),
            ("==> 校验签名", 78, "校验签名…"),
            ("==> 安装到 iPhone", 85, "安装到 iPhone…"),
            ("App installed", 88, "安装完成，准备启动…"),
            ("==> 启动 番茄小镇", 94, "启动 App…"),
            ("Launched application", 98, "App 已启动"),
            ("续签时间：", 100, "完成"),
        ]
        for (needle, value, label) in checks where line.contains(needle) {
            setProgress(value, label: label)
            return
        }
        if line.contains("❌") {
            statusLabel.stringValue = "续签遇到错误"
            statusLabel.textColor = Palette.tomatoDark
            setBadge("错误", fill: Palette.tomatoSoft, textColor: Palette.tomatoDark)
        }
    }

    // MARK: - Progress

    private func setProgress(_ value: Double, label: String? = nil) {
        guard value >= currentProgress else { return }
        currentProgress = value
        progressBar.doubleValue = value
        progressBar.setAccessibilityValue("\(Int(value.rounded()))%")
        setPercent(value)
        if let label { statusLabel.stringValue = label }
        if value >= 70 { buildPhase = false }
        if value >= 30 && value < 70 { buildPhase = true }
        updateSteps(for: value)
        if isRunning {
            if value >= 94 {
                setVoucher("正在进行", state: "启动中", stageColor: Palette.tomatoDark, stateColor: Palette.tomatoDark)
            } else if value >= 82 {
                setVoucher("正在进行", state: "安装中", stageColor: Palette.tomatoDark, stateColor: Palette.tomatoDark)
            } else {
                setVoucher("正在进行", state: "构建中", stateColor: Palette.tomato)
            }
        }
    }

    private func resetSteps() {
        for row in stepRows { row.setState(.pending) }
    }

    private func updateSteps(for value: Double) {
        for (index, row) in stepRows.enumerated() {
            let start = stepThresholds[index]
            let next = index + 1 < stepThresholds.count ? stepThresholds[index + 1] : 100
            if value >= 100 || value >= next {
                row.setState(.done)
            } else if value >= start {
                row.setState(.active)
            } else {
                row.setState(.pending)
            }
        }
    }

    private func markFailureStep() {
        var active = 0
        for index in stepThresholds.indices where currentProgress >= stepThresholds[index] {
            active = index
        }
        stepRows[active].setState(.failed)
    }

    // MARK: - Timers

    private func startTimers() {
        logTimer?.invalidate()
        tickTimer?.invalidate()
        logTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.flushLog()
        }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
        if let logTimer { RunLoop.main.add(logTimer, forMode: .common) }
        if let tickTimer { RunLoop.main.add(tickTimer, forMode: .common) }
    }

    private func stopTimers() {
        logTimer?.invalidate(); logTimer = nil
        tickTimer?.invalidate(); tickTimer = nil
    }

    private func tick() {
        guard isRunning else { return }
        if let content = try? String(contentsOf: progressURL, encoding: .utf8) {
            let line = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty && line != lastProgressContent {
                lastProgressContent = line
                let parts = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
                if let first = parts.first, let value = Double(first) {
                    setProgress(value, label: parts.count > 1 ? String(parts[1]) : nil)
                }
            }
        }
        if buildPhase && currentProgress < 70 {
            currentProgress = min(currentProgress + 0.35, 70)
            progressBar.doubleValue = currentProgress
            setPercent(currentProgress)
            updateSteps(for: currentProgress)
            if statusLabel.stringValue.isEmpty || statusLabel.stringValue.hasSuffix("…") {
                statusLabel.stringValue = "构建与签名（耗时最长）…"
            }
        }
    }

    // MARK: - Finish

    private func processFinished(_ finished: Process) {
        pipe?.fileHandleForReading.readabilityHandler = nil
        flushLog(force: true)
        stopTimers()
        process = nil
        pipe = nil

        let status = readStatus()
        let state = status["status"] ?? (finished.terminationStatus == 0 ? "ok" : "failed")
        let expiry = status["expiry"] ?? ""
        let summary = (try? String(contentsOf: summaryURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        finish(state: state, summary: summary, expiry: expiry, exitCode: finished.terminationStatus)
    }

    private func readStatus() -> [String: String] {
        guard let text = try? String(contentsOf: statusURL, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            if let index = line.firstIndex(of: "=") {
                let key = String(line[..<index]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: index)...]).trimmingCharacters(in: .whitespaces)
                values[key] = value
            }
        }
        return values
    }

    private func showMetric(_ number: String, unit: String, caption: String, showRail: Bool, railColor: NSColor) {
        percentBlock.isHidden = false
        heroMetaLabel.isHidden = true
        percentLabel.stringValue = number
        percentUnitLabel.stringValue = unit
        percentCaptionLabel.stringValue = caption
        progressBar.isHidden = !showRail
        progressBar.accentColor = railColor
    }

    private func finish(state: String, summary: String, expiry: String, exitCode: Int32) {
        isRunning = false
        buildPhase = false
        stopTimers()
        spinner.stopAnimation(nil)
        closeButton.isEnabled = true
        startButton.isHidden = true
        retryButton.isHidden = true
        trustCheckButton.isHidden = true
        heroNoteLabel.isHidden = true

        let expiryText = expiry.isEmpty ? "未更新" : expiry
        voucherExpiryLabel.stringValue = expiryText
        voucherDataLabel.stringValue = "保留"

        switch state {
        case "ok":
            showMetric("100", unit: "%", caption: "已完成", showRail: true, railColor: Palette.sage)
            setProgress(100, label: "续签完成")
            statusLabel.textColor = Palette.ink
            detailLabel.stringValue = expiry.isEmpty
                ? "新的 7 天已经盖好，打开“番茄小镇”继续读。"
                : "新的 7 天已经盖好，到期：\(expiry)。"
            detailLabel.textColor = Palette.muted
            setBadge("已完成", fill: Palette.sageSoft, textColor: Palette.sage)
            setVoucher("本次结果", state: "已续签", stageColor: Palette.faint, stateColor: Palette.sage)
            voucherNote.set("App 已安装并启动。书架与进度原样保留。", fill: Palette.sageSoft, textColor: Palette.sage)
            setLiveDot(Palette.sage)
            hintLabel.stringValue = "可关闭窗口"
            logPreviewLabel.stringValue = "本次续签完成，完整日志在日志目录。"
        case "needs-trust":
            currentProgress = 100
            progressBar.doubleValue = 100
            updateSteps(for: 100)
            showMetric("1", unit: "步", caption: "还差一步", showRail: false, railColor: Palette.amber)
            heroNoteLabel.isHidden = false
            heroNoteLabel.stringValue = "设置 → 通用 → VPN 与设备管理 → 开发者 App → 信任。"
            heroNoteLabel.textColor = Palette.amber
            statusLabel.stringValue = "已安装，待信任"
            statusLabel.textColor = Palette.amber
            detailLabel.stringValue = "App 已安装。只差在 iPhone 上信任开发者证书。"
            detailLabel.textColor = Palette.muted
            setBadge("待信任", fill: Palette.amberSoft, textColor: Palette.amber)
            setVoucher("还差一步", state: "待信任", stageColor: Palette.amber, stateColor: Palette.amber)
            voucherNote.set(
                "iPhone：设置 → 通用 → VPN 与设备管理 → 开发者 App → Apple Development → 信任。",
                fill: Palette.amberSoft,
                textColor: Palette.amber
            )
            setLiveDot(Palette.amber)
            hintLabel.stringValue = "在 iPhone 上完成信任"
            logPreviewLabel.stringValue = "构建完成，等待在 iPhone 上信任。"
            trustCheckButton.isHidden = false
        case "failed-unlock", "needs-unlock":
            showMetric("\(Int(currentProgress.rounded()))", unit: "%", caption: "总体进度", showRail: true, railColor: Palette.amber)
            statusLabel.stringValue = "iPhone 锁屏了"
            statusLabel.textColor = Palette.tomato
            detailLabel.stringValue = "解锁手机并保持亮屏，然后重试。"
            detailLabel.textColor = Palette.muted
            setBadge("需解锁", fill: Palette.amberSoft, textColor: Palette.amber)
            setVoucher("没有完成", state: "需解锁", stageColor: Palette.amber, stateColor: Palette.amber)
            voucherNote.set("锁屏时 Xcode 无法启用开发服务。解锁后点“重试续签”。", fill: Palette.amberSoft, textColor: Palette.amber)
            setLiveDot(Palette.amber)
            hintLabel.stringValue = "可重试"
            logPreviewLabel.stringValue = "iPhone 锁屏，开发服务未启用。完整日志在日志目录。"
            markFailureStep()
            retryButton.isHidden = false
        case "failed":
            showMetric("\(Int(currentProgress.rounded()))", unit: "%", caption: "总体进度", showRail: true, railColor: Palette.tomato)
            statusLabel.stringValue = "续签没有完成"
            statusLabel.textColor = Palette.tomato
            let firstLine = summary.components(separatedBy: .newlines).first ?? ""
            detailLabel.stringValue = firstLine.isEmpty ? "完整原因在技术日志目录里。" : firstLine
            detailLabel.textColor = Palette.muted
            setBadge("失败", fill: Palette.tomatoSoft, textColor: Palette.tomatoDark)
            setVoucher("没有完成", state: "需重试", stageColor: Palette.tomatoDark, stateColor: Palette.tomatoDark)
            voucherNote.set("构建或签名没有完成。打开日志目录查看原因，然后重试。", fill: Palette.tomatoSoft, textColor: Palette.tomatoDark)
            setLiveDot(Palette.tomato)
            hintLabel.stringValue = "可重试"
            logPreviewLabel.stringValue = recentLogLines.isEmpty
                ? "构建失败，完整日志在日志目录。"
                : recentLogLines.joined(separator: "\n")
            markFailureStep()
            retryButton.isHidden = false
        default:
            if exitCode == 0 {
                finish(state: "ok", summary: summary, expiry: expiry, exitCode: 0)
            } else {
                finish(state: "failed", summary: summary, expiry: expiry, exitCode: 1)
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Preview / snapshot hooks

    private func applyPreview(_ state: String) {
        switch state {
        case "running":
            isRunning = true
            startButton.isHidden = true
            retryButton.isHidden = true
            spinner.startAnimation(nil)
            setBadge("进行中", fill: Palette.tomatoSoft, textColor: Palette.tomatoDark)
            detailLabel.stringValue = "正在本机构建与签名，请保持 iPhone 解锁。"
            detailLabel.textColor = Palette.muted
            setVoucher("正在进行", state: "构建中", stageColor: Palette.tomatoDark, stateColor: Palette.tomatoDark)
            voucherExpiryLabel.stringValue = "生成中…"
            voucherNote.set("构建期间不要关闭窗口，完成后会尝试自动启动。", fill: Palette.tomatoSoft, textColor: Palette.tomatoDark)
            setLiveDot(Palette.sage)
            hintLabel.stringValue = "正在本机运行"
            trustCheckButton.isHidden = true
            percentBlock.isHidden = false
            heroMetaLabel.isHidden = true
            heroNoteLabel.isHidden = true
            progressBar.isHidden = false
            percentUnitLabel.stringValue = "%"
            percentCaptionLabel.stringValue = "总体进度"
            logPreviewLabel.stringValue = "==> xcodebuild（Release，自动签名）…\nBuilding Runner…"
            setProgress(55, label: "构建与签名（耗时最长）…")
        case "done":
            finish(state: "ok", summary: "", expiry: "2026-11-18 08:42", exitCode: 0)
        case "trust":
            finish(state: "needs-trust", summary: "", expiry: "2026-11-18 08:42", exitCode: 0)
        case "failed":
            currentProgress = 30
            progressBar.doubleValue = 30
            setPercent(30)
            updateSteps(for: 30)
            finish(state: "failed-unlock", summary: "", expiry: "", exitCode: 1)
        default:
            break
        }
    }

    private func saveSnapshot(to path: String) {
        guard let view = window.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        if let data = rep.representation(using: .png, properties: [:]) {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}
