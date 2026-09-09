import AppKit
import Foundation

private struct UsageSnapshot: Codable {
    var available: Bool
    var primaryUsedPercent: Int?
    var primaryWindowMinutes: Int?
    var primaryResetsAt: TimeInterval?
    var secondaryUsedPercent: Int?
    var latestDailyTokens: Int?
    var lifetimeTokens: Int?
    var fetchedAt: TimeInterval

    static let loading = UsageSnapshot(
        available: false,
        primaryUsedPercent: nil,
        primaryWindowMinutes: nil,
        primaryResetsAt: nil,
        secondaryUsedPercent: nil,
        latestDailyTokens: nil,
        lifetimeTokens: nil,
        fetchedAt: Date().timeIntervalSince1970
    )
}

private struct UsageHistoryRecord: Codable {
    let version: Int
    let recordedAt: TimeInterval
    let snapshot: UsageSnapshot
}

/// Appends successful usage responses outside the app bundle so app updates do not remove history.
private final class UsageHistoryStore {
    private let fileURL: URL?

    init() {
        fileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Codex Usage Widget", isDirectory: true)
            .appendingPathComponent("usage-history.jsonl")
    }

    func append(_ snapshot: UsageSnapshot) {
        guard let fileURL,
              let data = try? JSONEncoder().encode(UsageHistoryRecord(
                  version: 1,
                  recordedAt: Date().timeIntervalSince1970,
                  snapshot: snapshot
              )) else { return }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: fileURL)
            handle.seekToEndOfFile()
            handle.write(data)
            handle.write(Data([0x0A]))
            handle.closeFile()
        } catch {
            // History is supplementary; a storage error must not interrupt live updates.
        }
    }

    func recentRecords(limit: Int) -> [UsageHistoryRecord] {
        guard limit > 0, let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return [] }

        let records = text.split(whereSeparator: { $0.isNewline }).compactMap { line in
            try? JSONDecoder().decode(UsageHistoryRecord.self, from: Data(line.utf8))
        }
        return Array(records.suffix(limit))
    }
}

/// A read-only JSON-RPC client for the locally installed Codex app server.
/// It never reads, writes, or exposes authentication tokens.
private final class UsageClient {
    typealias UpdateHandler = (UsageSnapshot) -> Void

    var onUpdate: UpdateHandler?

    private let codexPath: String
    private let historyStore = UsageHistoryStore()
    private var process: Process?
    private var input: FileHandle?
    private var outputBuffer = Data()
    private var nextRequestID = 1
    private var initializeRequestID: Int?
    private var rateLimitRequestID: Int?
    private var usageRequestID: Int?
    private var rateLimitPayload: [String: Any]?
    private var usagePayload: [String: Any]?
    private var refreshTimer: Timer?
    private var refreshTimeoutTimer: Timer?
    private var initializationTimeoutTimer: Timer?
    private var isStarted = false
    private var isStopping = false
    private var isInitialized = false
    private var refreshInFlight = false

    private let refreshInterval: TimeInterval = 30
    private let retryInterval: TimeInterval = 1
    private let requestTimeout: TimeInterval = 5

    init() {
        codexPath = ProcessInfo.processInfo.environment["CODEX_BIN"]
            ?? "/Applications/ChatGPT.app/Contents/Resources/codex"
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        isStopping = false
        launch()
    }

    func forceRefresh() {
        guard isStarted else { return }
        refreshTimer?.invalidate()
        refreshTimer = nil
        guard !refreshInFlight else { return }
        if isInitialized {
            refresh()
        } else {
            retryAfterFailure()
        }
    }

    func stop() {
        isStopping = true
        isStarted = false
        refreshTimer?.invalidate()
        refreshTimer = nil
        refreshTimeoutTimer?.invalidate()
        refreshTimeoutTimer = nil
        initializationTimeoutTimer?.invalidate()
        initializationTimeoutTimer = nil
        if let output = process?.standardOutput as? Pipe {
            output.fileHandleForReading.readabilityHandler = nil
        }
        process?.terminate()
        process = nil
        input = nil
    }

    private func launch() {
        guard process == nil else { return }
        let task = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()

        task.executableURL = URL(fileURLWithPath: codexPath)
        task.arguments = ["app-server", "--listen", "stdio://"]
        task.standardInput = stdin
        task.standardOutput = stdout
        task.standardError = stderr
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async {
                self?.consume(data)
            }
        }
        task.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.isStarted, !self.isStopping, self.process != nil else { return }
                self.process = nil
                self.input = nil
                self.retryAfterFailure()
            }
        }

        do {
            try task.run()
            process = task
            input = stdin.fileHandleForWriting
            initializeRequestID = send(
                method: "initialize",
                params: ["clientInfo": ["name": "codex-usage-widget", "version": "1.0.0"]]
            )
            initializationTimeoutTimer?.invalidate()
            initializationTimeoutTimer = Timer.scheduledTimer(withTimeInterval: requestTimeout, repeats: false) { [weak self] _ in
                guard let self, !self.isInitialized else { return }
                self.retryAfterFailure()
            }
        } catch {
            retryAfterFailure()
        }
    }

    private func refresh() {
        refreshTimer = nil
        guard isStarted else { return }
        guard isInitialized, process != nil else {
            launch()
            return
        }
        guard !refreshInFlight else { return }

        rateLimitPayload = nil
        usagePayload = nil
        refreshInFlight = true
        rateLimitRequestID = send(method: "account/rateLimits/read")
        usageRequestID = send(method: "account/usage/read")
        refreshTimeoutTimer?.invalidate()
        refreshTimeoutTimer = Timer.scheduledTimer(withTimeInterval: requestTimeout, repeats: false) { [weak self] _ in
            self?.retryAfterFailure()
        }
    }

    private func scheduleRefresh(after interval: TimeInterval) {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.refresh()
        }
    }

    private func retryAfterFailure() {
        guard isStarted else { return }
        refreshTimer?.invalidate()
        refreshTimer = nil
        refreshTimeoutTimer?.invalidate()
        refreshTimeoutTimer = nil
        initializationTimeoutTimer?.invalidate()
        initializationTimeoutTimer = nil
        isInitialized = false
        refreshInFlight = false
        initializeRequestID = nil
        rateLimitRequestID = nil
        usageRequestID = nil
        rateLimitPayload = nil
        usagePayload = nil
        onUpdate?(UsageSnapshot.loading)
        guard isStarted else { return }

        if let process {
            process.terminate()
            self.process = nil
            input = nil
        }
        scheduleRefresh(after: retryInterval)
    }

    @discardableResult
    private func send(method: String, params: [String: Any]? = nil) -> Int {
        let id = nextRequestID
        nextRequestID += 1
        var request: [String: Any] = ["id": id, "method": method]
        if let params {
            request["params"] = params
        }
        guard let data = try? JSONSerialization.data(withJSONObject: request, options: []),
              let line = String(data: data, encoding: .utf8)?.appending("\n").data(using: .utf8) else {
            return id
        }
        input?.write(line)
        return id
    }

    private func consume(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer.prefix(upTo: newline)
            outputBuffer.removeSubrange(...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line),
                  let message = object as? [String: Any],
                  let id = intValue(message["id"]) else {
                continue
            }

            if id == initializeRequestID {
                initializeRequestID = nil
                initializationTimeoutTimer?.invalidate()
                initializationTimeoutTimer = nil
                if message["error"] == nil {
                    isInitialized = true
                    refresh()
                } else {
                    retryAfterFailure()
                }
            } else if id == rateLimitRequestID {
                rateLimitRequestID = nil
                guard message["error"] == nil,
                      let result = message["result"] as? [String: Any] else {
                    retryAfterFailure()
                    continue
                }
                rateLimitPayload = result
                publishWhenReady()
            } else if id == usageRequestID {
                usageRequestID = nil
                guard message["error"] == nil,
                      let result = message["result"] as? [String: Any] else {
                    retryAfterFailure()
                    continue
                }
                usagePayload = result
                publishWhenReady()
            }
        }
    }

    private func publishWhenReady() {
        guard let rateLimitPayload, let usagePayload else { return }
        let rateLimits = rateLimitPayload["rateLimits"] as? [String: Any]
        let primary = rateLimits?["primary"] as? [String: Any]
        let secondary = rateLimits?["secondary"] as? [String: Any]
        let summary = usagePayload["summary"] as? [String: Any]
        let buckets = usagePayload["dailyUsageBuckets"] as? [[String: Any]]
        let latestBucket = buckets?.max { lhs, rhs in
            (lhs["startDate"] as? String ?? "") < (rhs["startDate"] as? String ?? "")
        }
        let rawReset = doubleValue(primary?["resetsAt"])
        let resetAt = rawReset.map { $0 > 10_000_000_000 ? $0 / 1000 : $0 }

        let snapshot = UsageSnapshot(
            available: primary != nil,
            primaryUsedPercent: intValue(primary?["usedPercent"]),
            primaryWindowMinutes: intValue(primary?["windowDurationMins"]),
            primaryResetsAt: resetAt,
            secondaryUsedPercent: intValue(secondary?["usedPercent"]),
            latestDailyTokens: intValue(latestBucket?["tokens"]),
            lifetimeTokens: intValue(summary?["lifetimeTokens"]),
            fetchedAt: Date().timeIntervalSince1970
        )
        historyStore.append(snapshot)
        refreshTimeoutTimer?.invalidate()
        refreshTimeoutTimer = nil
        refreshInFlight = false
        onUpdate?(snapshot)
        guard isStarted else { return }
        scheduleRefresh(after: refreshInterval)
    }

    private func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let value = value as? Int { return value }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? String { return Double(value) }
        return nil
    }
}

private final class UsagePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class UsageView: NSView {
    var snapshot = UsageSnapshot.loading { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 16, yRadius: 16)
        NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.12, alpha: 0.95).setFill()
        card.fill()
        NSColor(calibratedRed: 0.95, green: 0.25, blue: 0.22, alpha: 0.5).setStroke()
        card.lineWidth = 1
        card.stroke()

        drawText("Codex·用量", at: NSPoint(x: 18, y: 16), font: .systemFont(ofSize: 13, weight: .bold), color: .white)
        drawText(snapshot.available ? "LIVE" : "读取中", at: NSPoint(x: 165, y: 18), font: .monospacedSystemFont(ofSize: 10, weight: .bold), color: accentColor)

        guard snapshot.available, let usedPercent = snapshot.primaryUsedPercent else {
            drawText("正在连接 Codex…", at: NSPoint(x: 18, y: 53), font: .systemFont(ofSize: 15, weight: .semibold), color: NSColor(white: 0.86, alpha: 1))
            drawText("不会读取或保存登录凭据", at: NSPoint(x: 18, y: 86), font: .systemFont(ofSize: 11), color: NSColor(white: 0.62, alpha: 1))
            drawText("点击并拖动可调整位置", at: NSPoint(x: 18, y: 125), font: .systemFont(ofSize: 11), color: NSColor(white: 0.5, alpha: 1))
            return
        }

        let windowLabel = limitLabel(snapshot.primaryWindowMinutes)
        drawText(windowLabel, at: NSPoint(x: 18, y: 50), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor(white: 0.68, alpha: 1))
        drawText(updateLabel(snapshot.fetchedAt), at: NSPoint(x: 126, y: 50), font: .systemFont(ofSize: 10), color: NSColor(white: 0.58, alpha: 1))
        drawText("\(usedPercent)% 已用", at: NSPoint(x: 18, y: 68), font: .systemFont(ofSize: 22, weight: .bold), color: .white)
        if let secondary = snapshot.secondaryUsedPercent {
            drawText("长周期 \(secondary)%", at: NSPoint(x: 176, y: 75), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor(white: 0.7, alpha: 1))
        }

        let track = NSBezierPath(roundedRect: NSRect(x: 18, y: 105, width: 254, height: 8), xRadius: 4, yRadius: 4)
        NSColor(white: 0.25, alpha: 1).setFill()
        track.fill()
        let width = 254 * CGFloat(min(max(usedPercent, 0), 100)) / 100
        let progress = NSBezierPath(roundedRect: NSRect(x: 18, y: 105, width: width, height: 8), xRadius: 4, yRadius: 4)
        progressColor(usedPercent).setFill()
        progress.fill()

        drawText(resetLabel(snapshot.primaryResetsAt), at: NSPoint(x: 18, y: 125), font: .systemFont(ofSize: 11), color: NSColor(white: 0.66, alpha: 1))
        let latest = tokenLabel(snapshot.latestDailyTokens)
        let total = tokenLabel(snapshot.lifetimeTokens)
        drawText("最近一天 \(latest)    累计 \(total)", at: NSPoint(x: 18, y: 146), font: .monospacedSystemFont(ofSize: 11, weight: .regular), color: NSColor(white: 0.82, alpha: 1))
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    private var accentColor: NSColor {
        NSColor(calibratedRed: 0.97, green: 0.32, blue: 0.26, alpha: 1)
    }

    private func drawText(_ text: String, at point: NSPoint, font: NSFont, color: NSColor) {
        (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }

    private func progressColor(_ value: Int) -> NSColor {
        if value >= 90 { return NSColor(calibratedRed: 0.95, green: 0.2, blue: 0.2, alpha: 1) }
        if value >= 70 { return NSColor(calibratedRed: 0.96, green: 0.57, blue: 0.17, alpha: 1) }
        return accentColor
    }

    private func limitLabel(_ minutes: Int?) -> String {
        guard let minutes else { return "当前额度" }
        if minutes >= 60 { return "\(minutes / 60) 小时额度" }
        return "\(minutes) 分钟额度"
    }

    private func resetLabel(_ timestamp: TimeInterval?) -> String {
        guard let timestamp else { return "重置时间未知" }
        let interval = max(0, Int(timestamp - Date().timeIntervalSince1970))
        if interval < 60 { return "即将重置" }
        if interval < 86_400 { return "约 \(interval / 3_600) 小时 \((interval % 3_600) / 60) 分钟后重置" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return "重置：\(formatter.string(from: Date(timeIntervalSince1970: timestamp)))"
    }

    private func tokenLabel(_ count: Int?) -> String {
        guard let count else { return "—" }
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    private func updateLabel(_ timestamp: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return "更新：\(formatter.string(from: Date(timeIntervalSince1970: timestamp)))"
    }
}

private final class UsageChartView: NSView {
    var records: [UsageHistoryRecord] = [] {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.12, alpha: 0.98).setFill()
        bounds.fill()

        drawText("Codex·用量趋势", at: NSPoint(x: 18, y: 16), font: .systemFont(ofSize: 14, weight: .bold), color: .white)
        drawText("最近 \(records.count) 条记录", at: NSPoint(x: 18, y: 38), font: .systemFont(ofSize: 10), color: NSColor(white: 0.55, alpha: 1))

        guard !records.isEmpty else {
            drawText("暂无历史数据", at: NSPoint(x: bounds.midX - 40, y: bounds.midY - 8), font: .systemFont(ofSize: 14, weight: .medium), color: NSColor(white: 0.65, alpha: 1))
            return
        }

        let plot = NSRect(
            x: 52,
            y: 58,
            width: max(1, bounds.width - 72),
            height: max(1, bounds.height - 108)
        )
        drawGrid(in: plot)
        drawSeries(records.map { $0.snapshot.primaryUsedPercent }, in: plot, color: accentColor)
        drawSeries(records.map { $0.snapshot.secondaryUsedPercent }, in: plot, color: secondaryColor)
        drawText("主周期", at: NSPoint(x: plot.minX, y: 40), font: .systemFont(ofSize: 10, weight: .medium), color: accentColor)
        drawText("长周期", at: NSPoint(x: plot.minX + 52, y: 40), font: .systemFont(ofSize: 10, weight: .medium), color: secondaryColor)

        let firstDate = dateLabel(records.first?.recordedAt)
        let lastDate = dateLabel(records.last?.recordedAt)
        drawText(firstDate, at: NSPoint(x: plot.minX, y: plot.maxY + 12), font: .systemFont(ofSize: 9), color: NSColor(white: 0.5, alpha: 1))
        let lastWidth = (lastDate as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 9)]).width
        drawText(lastDate, at: NSPoint(x: plot.maxX - lastWidth, y: plot.maxY + 12), font: .systemFont(ofSize: 9), color: NSColor(white: 0.5, alpha: 1))
    }

    private func drawGrid(in plot: NSRect) {
        for value in stride(from: 0, through: 100, by: 25) {
            let y = plot.maxY - plot.height * CGFloat(value) / 100
            let line = NSBezierPath()
            line.move(to: NSPoint(x: plot.minX, y: y))
            line.line(to: NSPoint(x: plot.maxX, y: y))
            NSColor(white: 0.25, alpha: 0.65).setStroke()
            line.lineWidth = value == 0 ? 1 : 0.5
            line.stroke()
            drawText("\(value)%", at: NSPoint(x: 16, y: y - 6), font: .systemFont(ofSize: 9), color: NSColor(white: 0.48, alpha: 1))
        }
    }

    private func drawSeries(_ values: [Int?], in plot: NSRect, color: NSColor) {
        guard !values.isEmpty else { return }
        var previous: NSPoint?
        for (index, value) in values.enumerated() {
            guard let value else {
                previous = nil
                continue
            }
            let x = values.count == 1
                ? plot.midX
                : plot.minX + plot.width * CGFloat(index) / CGFloat(values.count - 1)
            let y = plot.maxY - plot.height * CGFloat(min(max(value, 0), 100)) / 100
            let point = NSPoint(x: x, y: y)
            if let previous {
                let line = NSBezierPath()
                line.move(to: previous)
                line.line(to: point)
                color.setStroke()
                line.lineWidth = 2
                line.stroke()
            }
            let dot = NSBezierPath(ovalIn: NSRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4))
            color.setFill()
            dot.fill()
            previous = point
        }
    }

    private func drawText(_ text: String, at point: NSPoint, font: NSFont, color: NSColor) {
        (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }

    private func dateLabel(_ timestamp: TimeInterval?) -> String {
        guard let timestamp else { return "—" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    private var accentColor: NSColor {
        NSColor(calibratedRed: 0.97, green: 0.32, blue: 0.26, alpha: 1)
    }

    private var secondaryColor: NSColor {
        NSColor(calibratedRed: 0.32, green: 0.68, blue: 1, alpha: 1)
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let usageClient = UsageClient()
    private var panel: UsagePanel?
    private var usageView: UsageView?
    private let historyStore = UsageHistoryStore()
    private var chartPanel: NSPanel?
    private var chartView: UsageChartView?
    private var isOneShot = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        isOneShot = CommandLine.arguments.contains("--once")
        if !isOneShot {
            NSApp.setActivationPolicy(.accessory)
            showPanel()
        }
        usageClient.onUpdate = { [weak self] snapshot in
            guard let self else { return }
            if self.isOneShot {
                self.printSnapshotAndQuit(snapshot)
            } else {
                self.usageView?.snapshot = snapshot
                self.reloadChartIfVisible()
            }
        }
        usageClient.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        usageClient.stop()
    }

    private func showPanel() {
        let panel = UsagePanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 176),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false

        let content = UsageView(frame: panel.contentView?.bounds ?? .zero)
        content.autoresizingMask = [.width, .height]
        let chart = toolbarButton(
            title: "图表",
            action: #selector(showChart),
            frame: NSRect(x: 205, y: 10, width: 40, height: 24),
            color: NSColor(calibratedRed: 0.16, green: 0.32, blue: 0.48, alpha: 1)
        )
        chart.toolTip = "查看历史图表"
        chart.setAccessibilityLabel("查看历史图表")
        content.addSubview(chart)
        let refresh = toolbarButton(
            title: "刷新",
            action: #selector(forceRefresh),
            frame: NSRect(x: 248, y: 10, width: 40, height: 24),
            color: NSColor(calibratedRed: 0.78, green: 0.34, blue: 0.12, alpha: 1)
        )
        refresh.toolTip = "立即刷新用量"
        refresh.setAccessibilityLabel("立即刷新用量")
        content.addSubview(refresh)
        let close = toolbarButton(
            title: "退出",
            action: #selector(quit),
            frame: NSRect(x: 291, y: 10, width: 40, height: 24),
            color: NSColor(calibratedRed: 0.72, green: 0.16, blue: 0.16, alpha: 1)
        )
        close.toolTip = "关闭用量浮窗"
        close.setAccessibilityLabel("退出")
        content.addSubview(close)
        panel.contentView = content

        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - 370, y: frame.maxY - 196))
        }
        panel.orderFrontRegardless()
        self.panel = panel
        usageView = content
    }

    private func toolbarButton(title: String, action: Selector, frame: NSRect, color: NSColor) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.isBordered = true
        button.bezelColor = color
        button.contentTintColor = .white
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor.white
            ]
        )
        button.frame = frame
        return button
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func forceRefresh() {
        usageClient.forceRefresh()
    }

    @objc private func showChart() {
        if let chartPanel {
            chartPanel.makeKeyAndOrderFront(nil)
            reloadChart()
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 340),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Codex 用量历史"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false

        let chart = UsageChartView(frame: panel.contentView?.bounds ?? .zero)
        chart.autoresizingMask = [.width, .height]
        panel.contentView = chart
        panel.center()
        panel.orderFrontRegardless()
        chartPanel = panel
        chartView = chart
        reloadChart()
    }

    private func reloadChartIfVisible() {
        guard chartPanel?.isVisible == true else { return }
        reloadChart()
    }

    private func reloadChart() {
        guard let chartView else { return }
        DispatchQueue.global(qos: .userInitiated).async { [historyStore] in
            let records = historyStore.recentRecords(limit: 120)
            DispatchQueue.main.async { [weak chartView] in
                chartView?.records = records
            }
        }
    }

    private func printSnapshotAndQuit(_ snapshot: UsageSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot),
              let text = String(data: data, encoding: .utf8) else {
            NSApp.terminate(nil)
            return
        }
        FileHandle.standardOutput.write(Data((text + "\n").utf8))
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
