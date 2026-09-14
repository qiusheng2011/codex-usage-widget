import AppKit
import UniformTypeIdentifiers

final class UsagePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class UsageView: NSView {
    var onManualResetClick: (() -> Void)?
    var onDragEnded: (() -> Void)?
    var onMouseEnteredPanel: (() -> Void)?
    var onMouseExitedPanel: (() -> Void)?
    var snapshot = UsageSnapshot.loading {
        didSet {
            needsDisplay = true
            updateManualResetButton()
        }
    }
    var backgroundImage: NSImage? {
        didSet { needsDisplay = true }
    }
    var backgroundImageOpacity: CGFloat = 0.28 {
        didSet { needsDisplay = true }
    }
    private var isCompactPresentation = false {
        didSet {
            guard oldValue != isCompactPresentation else { return }
            for subview in subviews {
                subview.isHidden = isCompactPresentation
            }
            if !isCompactPresentation {
                updateManualResetButton()
            }
            needsDisplay = true
        }
    }

    private let manualResetButton = NSButton(title: "", target: nil, action: nil)
    private var trackingArea: NSTrackingArea?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureManualResetButton()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureManualResetButton()
    }

    override func layout() {
        super.layout()
        let width = min(125, max(100, bounds.width - 195))
        manualResetButton.frame = NSRect(x: bounds.width - width - 18, y: 121, width: width, height: 20)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onMouseEnteredPanel?()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onMouseExitedPanel?()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 16, yRadius: 16)
        NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.12, alpha: 0.95).setFill()
        card.fill()
        drawBackgroundImage(in: card)
        NSColor(calibratedRed: 0.95, green: 0.25, blue: 0.22, alpha: 0.5).setStroke()
        card.lineWidth = 1
        card.stroke()

        if isCompactPresentation {
            let primary = snapshot.primaryUsedPercent.map { "\($0)%" } ?? "—"
            let secondary = snapshot.secondaryUsedPercent.map { "\($0)%" } ?? "—"
            let primaryLabel = L10n.text("5 小时", "5h")
            let secondaryLabel = L10n.text("长周期", "Long")
            drawCenteredText("\(primaryLabel)  \(primary)", y: 12, font: .systemFont(ofSize: 11, weight: .semibold), color: .white)
            drawCenteredText("\(secondaryLabel)  \(secondary)", y: 35, font: .systemFont(ofSize: 11, weight: .medium), color: NSColor(white: 0.72, alpha: 1))
            return
        }

        let headerY: CGFloat = L10n.language.isChinese ? 16 : 32
        drawText(L10n.text("Codex·用量", "Codex Usage"), at: NSPoint(x: 18, y: headerY), font: .systemFont(ofSize: 13, weight: .bold), color: .white)
        drawText(snapshot.available ? "LIVE" : L10n.text("读取中", "Loading"), at: NSPoint(x: L10n.language.isChinese ? 92 : 113, y: headerY + 2), font: .monospacedSystemFont(ofSize: 10, weight: .bold), color: accentColor)

        guard snapshot.available, let usedPercent = snapshot.primaryUsedPercent else {
            drawText(L10n.text("正在连接 Codex…", "Connecting to Codex…"), at: NSPoint(x: 18, y: 53), font: .systemFont(ofSize: 15, weight: .semibold), color: NSColor(white: 0.86, alpha: 1))
            drawText(L10n.text("不会读取或保存登录凭据", "No login credentials are read or stored"), at: NSPoint(x: 18, y: 86), font: .systemFont(ofSize: 11), color: NSColor(white: 0.62, alpha: 1))
            drawText(L10n.text("点击并拖动可调整位置", "Click and drag to move"), at: NSPoint(x: 18, y: 125), font: .systemFont(ofSize: 11), color: NSColor(white: 0.5, alpha: 1))
            return
        }

        let windowLabel = limitLabel(snapshot.primaryWindowMinutes)
        drawText(windowLabel, at: NSPoint(x: 18, y: 50), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor(white: 0.68, alpha: 1))
        drawRightAlignedText(updateLabel(snapshot.fetchedAt), rightX: bounds.width - 18, y: 50, font: .systemFont(ofSize: 10), color: NSColor(white: 0.58, alpha: 1))
        drawText(L10n.text("\(usedPercent)% 已用", "\(usedPercent)% used"), at: NSPoint(x: 18, y: 68), font: .systemFont(ofSize: 22, weight: .bold), color: .white)
        if let secondary = snapshot.secondaryUsedPercent {
            drawRightAlignedText("\(L10n.text("长周期", "Long")) \(secondary)%", rightX: bounds.width - 18, y: 75, font: .systemFont(ofSize: 11, weight: .medium), color: NSColor(white: 0.7, alpha: 1))
        }

        let trackWidth = max(1, bounds.width - 36)
        let track = NSBezierPath(roundedRect: NSRect(x: 18, y: 105, width: trackWidth, height: 8), xRadius: 4, yRadius: 4)
        NSColor(white: 0.25, alpha: 1).setFill()
        track.fill()
        let progressWidth = trackWidth * CGFloat(min(max(usedPercent, 0), 100)) / 100
        let progress = NSBezierPath(roundedRect: NSRect(x: 18, y: 105, width: progressWidth, height: 8), xRadius: 4, yRadius: 4)
        progressColor(usedPercent).setFill()
        progress.fill()

        drawText(resetLabel(snapshot.primaryResetsAt), at: NSPoint(x: 18, y: 125), font: .systemFont(ofSize: 11), color: NSColor(white: 0.66, alpha: 1))
        let latest = tokenLabel(snapshot.latestDailyTokens)
        let total = tokenLabel(snapshot.lifetimeTokens)
        drawText(L10n.text("最近一天 \(latest)    累计 \(total)", "Daily \(latest)    Total \(total)"), at: NSPoint(x: 18, y: 146), font: .monospacedSystemFont(ofSize: 11, weight: .regular), color: NSColor(white: 0.82, alpha: 1))
    }

    private func configureManualResetButton() {
        manualResetButton.bezelStyle = .inline
        manualResetButton.isBordered = false
        manualResetButton.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        manualResetButton.contentTintColor = accentColor
        manualResetButton.alignment = .right
        manualResetButton.target = self
        manualResetButton.action = #selector(manualResetTapped)
        manualResetButton.toolTip = L10n.text("查看每个手动重置的到期时间", "View expiration dates for manual reset credits")
        manualResetButton.setAccessibilityLabel(L10n.text("使用限额重置次数", "Manual reset credits"))
        manualResetButton.isHidden = true
        addSubview(manualResetButton)
        updateManualResetButton()
    }

    private func updateManualResetButton() {
        guard let count = snapshot.manualResetCount else {
            manualResetButton.isHidden = true
            return
        }
        manualResetButton.title = L10n.text("使用限额重置 \(count) 次", "Manual resets: \(count)")
        manualResetButton.isHidden = false
    }

    func updateLanguage() {
        updateManualResetButton()
        needsDisplay = true
    }

    func updateAccentColor() {
        manualResetButton.contentTintColor = accentColor
        needsDisplay = true
    }

    private func drawBackgroundImage(in card: NSBezierPath) {
        guard let backgroundImage,
              backgroundImageOpacity > 0,
              backgroundImage.size.width > 0,
              backgroundImage.size.height > 0 else { return }

        NSGraphicsContext.saveGraphicsState()
        card.addClip()
        let imageSize = backgroundImage.size
        let scale = max(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let drawSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let drawRect = NSRect(
            x: bounds.midX - drawSize.width / 2,
            y: bounds.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        backgroundImage.draw(
            in: drawRect,
            from: NSRect(origin: .zero, size: imageSize),
            operation: .sourceOver,
            fraction: min(max(backgroundImageOpacity, 0), 1),
            respectFlipped: isFlipped,
            hints: nil
        )
        NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.12, alpha: 0.48).setFill()
        card.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    @objc private func manualResetTapped() {
        onManualResetClick?()
    }

    override func mouseDown(with event: NSEvent) {
        if isCompactPresentation {
            onMouseEnteredPanel?()
        }
        window?.performDrag(with: event)
        onDragEnded?()
    }

    func setCompactPresentation(_ compact: Bool) {
        isCompactPresentation = compact
    }

    private var accentColor: NSColor {
        AccentColorPreference.current
    }

    private func drawText(_ text: String, at point: NSPoint, font: NSFont, color: NSColor) {
        (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }

    private func drawRightAlignedText(_ text: String, rightX: CGFloat, y: CGFloat, font: NSFont, color: NSColor) {
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        drawText(text, at: NSPoint(x: rightX - width, y: y), font: font, color: color)
    }

    private func drawCenteredText(_ text: String, y: CGFloat, font: NSFont, color: NSColor) {
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        drawText(text, at: NSPoint(x: bounds.midX - width / 2, y: y), font: font, color: color)
    }

    private func progressColor(_ value: Int) -> NSColor {
        if value >= 90 { return NSColor(calibratedRed: 0.95, green: 0.2, blue: 0.2, alpha: 1) }
        if value >= 70 { return NSColor(calibratedRed: 0.96, green: 0.57, blue: 0.17, alpha: 1) }
        return accentColor
    }

    private func limitLabel(_ minutes: Int?) -> String {
        guard let minutes else { return L10n.text("当前额度", "Current limit") }
        if minutes >= 60 {
            return L10n.text("\(minutes / 60) 小时额度", "\(minutes / 60)-hour limit")
        }
        return L10n.text("\(minutes) 分钟额度", "\(minutes)-minute limit")
    }

    private func resetLabel(_ timestamp: TimeInterval?) -> String {
        guard let timestamp else { return L10n.text("重置时间未知", "Reset time unknown") }
        let interval = max(0, Int(timestamp - Date().timeIntervalSince1970))
        if interval < 60 { return L10n.text("即将重置", "Resetting soon") }
        if interval < 86_400 {
            let hours = interval / 3_600
            let minutes = (interval % 3_600) / 60
            return L10n.text("约 \(hours) 小时 \(minutes) 分钟后重置", "Resets in about \(hours)h \(minutes)m")
        }
        let date = L10n.dateFormatter(format: "MM-dd HH:mm").string(from: Date(timeIntervalSince1970: timestamp))
        return L10n.text("重置：\(date)", "Reset: \(date)")
    }

    private func tokenLabel(_ count: Int?) -> String {
        guard let count else { return "—" }
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    private func updateLabel(_ timestamp: TimeInterval) -> String {
        let date = L10n.dateFormatter(format: "MM-dd HH:mm:ss").string(from: Date(timeIntervalSince1970: timestamp))
        return L10n.text("更新：\(date)", "Updated: \(date)")
    }
}

final class ManualResetDetailsView: NSView {
    private var count: Int
    private var credits: [ManualResetCredit]

    init(count: Int, credits: [ManualResetCredit], frame frameRect: NSRect) {
        self.count = count
        self.credits = credits
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        count = 0
        credits = []
        super.init(coder: coder)
    }

    override var isFlipped: Bool { true }

    func update(count: Int, credits: [ManualResetCredit]) {
        self.count = count
        self.credits = credits
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.12, alpha: 0.98).setFill()
        bounds.fill()

        drawText(L10n.text("使用限额重置", "Manual Reset Credits"), at: NSPoint(x: 18, y: 16), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        drawText(L10n.text("可用次数：\(count)", "Available: \(count)"), at: NSPoint(x: 18, y: 40), font: .systemFont(ofSize: 11), color: NSColor(white: 0.62, alpha: 1))

        guard count > 0 else {
            drawText(L10n.text("暂无可用的手动重置", "No manual resets available"), at: NSPoint(x: 18, y: 78), font: .systemFont(ofSize: 13), color: NSColor(white: 0.65, alpha: 1))
            return
        }
        guard !credits.isEmpty else {
            drawText(L10n.text("当前接口未返回逐条到期时间", "The server did not return individual expiration dates"), at: NSPoint(x: 18, y: 78), font: .systemFont(ofSize: 13), color: NSColor(white: 0.65, alpha: 1))
            return
        }

        for (index, credit) in credits.enumerated() {
            let title = displayTitle(credit.title)
            let expiration = credit.expiresAt.map { dateLabel($0) } ?? L10n.text("不设置到期时间", "No expiration")
            let y = 74 + CGFloat(index) * 42
            drawText("\(index + 1). \(title)", at: NSPoint(x: 18, y: y), font: .systemFont(ofSize: 12), color: NSColor(white: 0.82, alpha: 1))
            drawText(L10n.text("到期：\(expiration)", "Expires: \(expiration)"), at: NSPoint(x: 36, y: y + 19), font: .systemFont(ofSize: 10), color: NSColor(white: 0.58, alpha: 1))
        }
        if credits.count < count {
            drawText(L10n.text("部分重置的详细信息暂不可用", "Details for some resets are unavailable"), at: NSPoint(x: 18, y: 92 + CGFloat(credits.count) * 42), font: .systemFont(ofSize: 10), color: NSColor(white: 0.5, alpha: 1))
        }
    }

    func updateLanguage() {
        needsDisplay = true
    }

    private func displayTitle(_ title: String?) -> String {
        guard let title, !title.isEmpty else { return L10n.text("使用限额重置", "Manual reset") }
        if L10n.language.isChinese, title == "Full reset (Weekly + 5 hr)" {
            return "完全重置（每周 + 5 小时）"
        }
        return title
    }

    private func drawText(_ text: String, at point: NSPoint, font: NSFont, color: NSColor) {
        (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }

    private func dateLabel(_ timestamp: TimeInterval) -> String {
        return L10n.dateFormatter(format: "yyyy-MM-dd HH:mm:ss").string(from: Date(timeIntervalSince1970: timestamp))
    }
}
