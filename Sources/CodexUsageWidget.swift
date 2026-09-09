import AppKit
import Foundation
import UniformTypeIdentifiers

private struct ManualResetCredit: Codable {
    var resetType: String
    var status: String
    var title: String?
    var description: String?
    var expiresAt: TimeInterval?
}

private enum AppearancePreference {
    static let backgroundImagePath = "appearance.backgroundImagePath"
    static let backgroundImageOpacity = "appearance.backgroundImageOpacity"
    static let defaultBackgroundImageOpacity = 0.28
}

private struct UsageSnapshot: Codable {
    var available: Bool
    var primaryUsedPercent: Int?
    var primaryWindowMinutes: Int?
    var primaryResetsAt: TimeInterval?
    var secondaryUsedPercent: Int?
    var manualResetCount: Int?
    var manualResetCredits: [ManualResetCredit]
    var latestDailyTokens: Int?
    var lifetimeTokens: Int?
    var fetchedAt: TimeInterval

    private enum CodingKeys: String, CodingKey {
        case available
        case primaryUsedPercent
        case primaryWindowMinutes
        case primaryResetsAt
        case secondaryUsedPercent
        case manualResetCount
        case manualResetCredits
        case manualResetExpirations
        case latestDailyTokens
        case lifetimeTokens
        case fetchedAt
    }

    init(
        available: Bool,
        primaryUsedPercent: Int?,
        primaryWindowMinutes: Int?,
        primaryResetsAt: TimeInterval?,
        secondaryUsedPercent: Int?,
        manualResetCount: Int?,
        manualResetCredits: [ManualResetCredit],
        latestDailyTokens: Int?,
        lifetimeTokens: Int?,
        fetchedAt: TimeInterval
    ) {
        self.available = available
        self.primaryUsedPercent = primaryUsedPercent
        self.primaryWindowMinutes = primaryWindowMinutes
        self.primaryResetsAt = primaryResetsAt
        self.secondaryUsedPercent = secondaryUsedPercent
        self.manualResetCount = manualResetCount
        self.manualResetCredits = manualResetCredits
        self.latestDailyTokens = latestDailyTokens
        self.lifetimeTokens = lifetimeTokens
        self.fetchedAt = fetchedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        available = try container.decode(Bool.self, forKey: .available)
        primaryUsedPercent = try container.decodeIfPresent(Int.self, forKey: .primaryUsedPercent)
        primaryWindowMinutes = try container.decodeIfPresent(Int.self, forKey: .primaryWindowMinutes)
        primaryResetsAt = try container.decodeIfPresent(TimeInterval.self, forKey: .primaryResetsAt)
        secondaryUsedPercent = try container.decodeIfPresent(Int.self, forKey: .secondaryUsedPercent)
        manualResetCount = try container.decodeIfPresent(Int.self, forKey: .manualResetCount)
        if let credits = try container.decodeIfPresent([ManualResetCredit].self, forKey: .manualResetCredits) {
            manualResetCredits = credits
        } else {
            let legacyExpirations = try container.decodeIfPresent([TimeInterval?].self, forKey: .manualResetExpirations) ?? []
            manualResetCredits = legacyExpirations.map {
                ManualResetCredit(
                    resetType: "codexRateLimits",
                    status: "available",
                    title: nil,
                    description: nil,
                    expiresAt: $0
                )
            }
        }
        latestDailyTokens = try container.decodeIfPresent(Int.self, forKey: .latestDailyTokens)
        lifetimeTokens = try container.decodeIfPresent(Int.self, forKey: .lifetimeTokens)
        fetchedAt = try container.decode(TimeInterval.self, forKey: .fetchedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(available, forKey: .available)
        try container.encodeIfPresent(primaryUsedPercent, forKey: .primaryUsedPercent)
        try container.encodeIfPresent(primaryWindowMinutes, forKey: .primaryWindowMinutes)
        try container.encodeIfPresent(primaryResetsAt, forKey: .primaryResetsAt)
        try container.encodeIfPresent(secondaryUsedPercent, forKey: .secondaryUsedPercent)
        try container.encodeIfPresent(manualResetCount, forKey: .manualResetCount)
        try container.encode(manualResetCredits, forKey: .manualResetCredits)
        try container.encodeIfPresent(latestDailyTokens, forKey: .latestDailyTokens)
        try container.encodeIfPresent(lifetimeTokens, forKey: .lifetimeTokens)
        try container.encode(fetchedAt, forKey: .fetchedAt)
    }

    static let loading = UsageSnapshot(
        available: false,
        primaryUsedPercent: nil,
        primaryWindowMinutes: nil,
        primaryResetsAt: nil,
        secondaryUsedPercent: nil,
        manualResetCount: nil,
        manualResetCredits: [],
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

    func allRecords() -> [UsageHistoryRecord] {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return [] }

        let records = text.split(whereSeparator: { $0.isNewline }).compactMap { line in
            try? JSONDecoder().decode(UsageHistoryRecord.self, from: Data(line.utf8))
        }
        return records
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
        let resetCredits = rateLimitPayload["rateLimitResetCredits"] as? [String: Any]
        let manualResetCount = intValue(resetCredits?["availableCount"])
        let manualResetCredits: [ManualResetCredit] = (resetCredits?["credits"] as? [[String: Any]] ?? [])
            .filter { ($0["status"] as? String ?? "available") == "available" }
            .map { credit in
                let rawExpiresAt = doubleValue(credit["expiresAt"])
                let expiresAt = rawExpiresAt.map { $0 > 10_000_000_000 ? $0 / 1000 : $0 }
                return ManualResetCredit(
                    resetType: credit["resetType"] as? String ?? "unknown",
                    status: credit["status"] as? String ?? "available",
                    title: credit["title"] as? String,
                    description: credit["description"] as? String,
                    expiresAt: expiresAt
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.expiresAt, rhs.expiresAt) {
                case let (left?, right?): return left < right
                case (_?, nil): return true
                default: return false
                }
            }

        let snapshot = UsageSnapshot(
            available: primary != nil,
            primaryUsedPercent: intValue(primary?["usedPercent"]),
            primaryWindowMinutes: intValue(primary?["windowDurationMins"]),
            primaryResetsAt: resetAt,
            secondaryUsedPercent: intValue(secondary?["usedPercent"]),
            manualResetCount: manualResetCount,
            manualResetCredits: manualResetCredits,
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
    var onManualResetClick: (() -> Void)?
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

    private let manualResetButton = NSButton(title: "", target: nil, action: nil)

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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 16, yRadius: 16)
        NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.12, alpha: 0.95).setFill()
        card.fill()
        drawBackgroundImage(in: card)
        NSColor(calibratedRed: 0.95, green: 0.25, blue: 0.22, alpha: 0.5).setStroke()
        card.lineWidth = 1
        card.stroke()

        drawText("Codex·用量", at: NSPoint(x: 18, y: 16), font: .systemFont(ofSize: 13, weight: .bold), color: .white)
        drawText(snapshot.available ? "LIVE" : "读取中", at: NSPoint(x: 92, y: 18), font: .monospacedSystemFont(ofSize: 10, weight: .bold), color: accentColor)

        guard snapshot.available, let usedPercent = snapshot.primaryUsedPercent else {
            drawText("正在连接 Codex…", at: NSPoint(x: 18, y: 53), font: .systemFont(ofSize: 15, weight: .semibold), color: NSColor(white: 0.86, alpha: 1))
            drawText("不会读取或保存登录凭据", at: NSPoint(x: 18, y: 86), font: .systemFont(ofSize: 11), color: NSColor(white: 0.62, alpha: 1))
            drawText("点击并拖动可调整位置", at: NSPoint(x: 18, y: 125), font: .systemFont(ofSize: 11), color: NSColor(white: 0.5, alpha: 1))
            return
        }

        let windowLabel = limitLabel(snapshot.primaryWindowMinutes)
        drawText(windowLabel, at: NSPoint(x: 18, y: 50), font: .systemFont(ofSize: 11, weight: .medium), color: NSColor(white: 0.68, alpha: 1))
        drawRightAlignedText(updateLabel(snapshot.fetchedAt), rightX: bounds.width - 18, y: 50, font: .systemFont(ofSize: 10), color: NSColor(white: 0.58, alpha: 1))
        drawText("\(usedPercent)% 已用", at: NSPoint(x: 18, y: 68), font: .systemFont(ofSize: 22, weight: .bold), color: .white)
        if let secondary = snapshot.secondaryUsedPercent {
            drawRightAlignedText("长周期 \(secondary)%", rightX: bounds.width - 18, y: 75, font: .systemFont(ofSize: 11, weight: .medium), color: NSColor(white: 0.7, alpha: 1))
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
        drawText("最近一天 \(latest)    累计 \(total)", at: NSPoint(x: 18, y: 146), font: .monospacedSystemFont(ofSize: 11, weight: .regular), color: NSColor(white: 0.82, alpha: 1))
    }

    private func configureManualResetButton() {
        manualResetButton.bezelStyle = .inline
        manualResetButton.isBordered = false
        manualResetButton.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        manualResetButton.contentTintColor = accentColor
        manualResetButton.alignment = .right
        manualResetButton.target = self
        manualResetButton.action = #selector(manualResetTapped)
        manualResetButton.toolTip = "查看每个手动重置的到期时间"
        manualResetButton.setAccessibilityLabel("使用限额重置次数")
        manualResetButton.isHidden = true
        addSubview(manualResetButton)
        updateManualResetButton()
    }

    private func updateManualResetButton() {
        guard let count = snapshot.manualResetCount else {
            manualResetButton.isHidden = true
            return
        }
        manualResetButton.title = "使用限额重置 \(count) 次"
        manualResetButton.isHidden = false
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
        window?.performDrag(with: event)
    }

    private var accentColor: NSColor {
        NSColor(calibratedRed: 0.97, green: 0.32, blue: 0.26, alpha: 1)
    }

    private func drawText(_ text: String, at point: NSPoint, font: NSFont, color: NSColor) {
        (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }

    private func drawRightAlignedText(_ text: String, rightX: CGFloat, y: CGFloat, font: NSFont, color: NSColor) {
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        drawText(text, at: NSPoint(x: rightX - width, y: y), font: font, color: color)
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

private final class ManualResetDetailsView: NSView {
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

        drawText("使用限额重置", at: NSPoint(x: 18, y: 16), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        drawText("可用次数：\(count)", at: NSPoint(x: 18, y: 40), font: .systemFont(ofSize: 11), color: NSColor(white: 0.62, alpha: 1))

        guard count > 0 else {
            drawText("暂无可用的手动重置", at: NSPoint(x: 18, y: 78), font: .systemFont(ofSize: 13), color: NSColor(white: 0.65, alpha: 1))
            return
        }
        guard !credits.isEmpty else {
            drawText("当前接口未返回逐条到期时间", at: NSPoint(x: 18, y: 78), font: .systemFont(ofSize: 13), color: NSColor(white: 0.65, alpha: 1))
            return
        }

        for (index, credit) in credits.enumerated() {
            let title = displayTitle(credit.title)
            let expiration = credit.expiresAt.map { dateLabel($0) } ?? "不设置到期时间"
            let y = 74 + CGFloat(index) * 42
            drawText("\(index + 1). \(title)", at: NSPoint(x: 18, y: y), font: .systemFont(ofSize: 12), color: NSColor(white: 0.82, alpha: 1))
            drawText("到期：\(expiration)", at: NSPoint(x: 36, y: y + 19), font: .systemFont(ofSize: 10), color: NSColor(white: 0.58, alpha: 1))
        }
        if credits.count < count {
            drawText("部分重置的详细信息暂不可用", at: NSPoint(x: 18, y: 92 + CGFloat(credits.count) * 42), font: .systemFont(ofSize: 10), color: NSColor(white: 0.5, alpha: 1))
        }
    }

    private func displayTitle(_ title: String?) -> String {
        guard let title, !title.isEmpty else { return "使用限额重置" }
        if title == "Full reset (Weekly + 5 hr)" {
            return "完全重置（每周 + 5 小时）"
        }
        return title
    }

    private func drawText(_ text: String, at point: NSPoint, font: NSFont, color: NSColor) {
        (text as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }

    private func dateLabel(_ timestamp: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSince1970: timestamp))
    }
}

private enum ChartRange: Int {
    case day
    case week
    case month
    case all

    var title: String {
        switch self {
        case .day: return "24 小时"
        case .week: return "7 天"
        case .month: return "30 天"
        case .all: return "全部"
        }
    }
}

private enum ChartSeries: Int {
    case primary
    case secondary
    case both
}

private final class UsageChartView: NSView {
    var records: [UsageHistoryRecord] = [] {
        didSet { needsDisplay = true }
    }

    var chartRange: ChartRange = .week {
        didSet { needsDisplay = true }
    }

    var chartSeries: ChartSeries = .both {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.12, alpha: 0.98).setFill()
        bounds.fill()

        let visibleRecords = filteredRecords()
        drawText("Codex·用量趋势", at: NSPoint(x: 18, y: 14), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        drawText(
            "时间：\(chartRange.title)    当前显示 \(visibleRecords.count) 条 / 历史 \(records.count) 条",
            at: NSPoint(x: 18, y: 37),
            font: .systemFont(ofSize: 10),
            color: NSColor(white: 0.58, alpha: 1)
        )

        let plot = NSRect(
            x: 58,
            y: 105,
            width: max(1, bounds.width - 80),
            height: max(1, bounds.height - 160)
        )
        guard !visibleRecords.isEmpty else {
            drawText("当前筛选范围暂无数据", at: NSPoint(x: bounds.midX - 58, y: bounds.midY), font: .systemFont(ofSize: 14, weight: .medium), color: NSColor(white: 0.65, alpha: 1))
            return
        }

        drawGrid(in: plot)
        switch chartSeries {
        case .primary:
            drawSeries(visibleRecords.map { $0.snapshot.primaryUsedPercent }, in: plot, color: accentColor)
        case .secondary:
            drawSeries(visibleRecords.map { $0.snapshot.secondaryUsedPercent }, in: plot, color: secondaryColor)
        case .both:
            drawSeries(visibleRecords.map { $0.snapshot.primaryUsedPercent }, in: plot, color: accentColor)
            drawSeries(visibleRecords.map { $0.snapshot.secondaryUsedPercent }, in: plot, color: secondaryColor)
        }
        drawLegend(at: NSPoint(x: plot.minX, y: 82))

        let firstDate = dateLabel(visibleRecords.first?.recordedAt)
        let lastDate = dateLabel(visibleRecords.last?.recordedAt)
        let dateFont = NSFont.systemFont(ofSize: 9)
        drawText(firstDate, at: NSPoint(x: plot.minX, y: plot.maxY + 12), font: dateFont, color: NSColor(white: 0.5, alpha: 1))
        let lastWidth = (lastDate as NSString).size(withAttributes: [.font: dateFont]).width
        drawText(lastDate, at: NSPoint(x: plot.maxX - lastWidth, y: plot.maxY + 12), font: dateFont, color: NSColor(white: 0.5, alpha: 1))
    }

    private func filteredRecords() -> [UsageHistoryRecord] {
        let sorted = records.sorted { $0.recordedAt < $1.recordedAt }
        let cutoff: TimeInterval
        switch chartRange {
        case .day: cutoff = Date().timeIntervalSince1970 - 86_400
        case .week: cutoff = Date().timeIntervalSince1970 - 604_800
        case .month: cutoff = Date().timeIntervalSince1970 - 2_592_000
        case .all: cutoff = 0
        }
        let matching = sorted.filter { $0.recordedAt >= cutoff }
        return downsample(matching, maximum: 240)
    }

    private func downsample(_ records: [UsageHistoryRecord], maximum: Int) -> [UsageHistoryRecord] {
        guard records.count > maximum, maximum > 1 else { return records }
        return (0..<maximum).map { index in
            let sourceIndex = Int((Double(index) * Double(records.count - 1) / Double(maximum - 1)).rounded())
            return records[sourceIndex]
        }
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

    private func drawLegend(at point: NSPoint) {
        var x = point.x
        if chartSeries != .secondary {
            drawText("主周期", at: NSPoint(x: x, y: point.y), font: .systemFont(ofSize: 10, weight: .medium), color: accentColor)
            x += 54
        }
        if chartSeries != .primary {
            drawText("长周期", at: NSPoint(x: x, y: point.y), font: .systemFont(ofSize: 10, weight: .medium), color: secondaryColor)
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

private final class AppearanceSettingsView: NSView {
    var onChooseImage: (() -> Void)?
    var onClearImage: (() -> Void)?
    var onOpacityChanged: ((CGFloat) -> Void)?

    private let imagePathLabel = NSTextField(labelWithString: "")
    private let opacitySlider = NSSlider(value: 0.28, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let opacityValueLabel = NSTextField(labelWithString: "28%")
    private let chooseButton = NSButton(title: "选择图片", target: nil, action: nil)
    private let clearButton = NSButton(title: "清除图片", target: nil, action: nil)
    private let hintLabel = NSTextField(labelWithString: "主题色保持为当前深色主题，图片只会作为半透明背景叠加。")

    override var isFlipped: Bool { true }

    init(imagePath: String?, opacity: CGFloat) {
        super.init(frame: .zero)
        configure(imagePath: imagePath, opacity: opacity)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure(imagePath: nil, opacity: 0.28)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.12, alpha: 1).setFill()
        bounds.fill()
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        imagePathLabel.frame = NSRect(x: 18, y: 40, width: max(1, width - 36), height: 20)
        chooseButton.frame = NSRect(x: 18, y: 68, width: 88, height: 26)
        clearButton.frame = NSRect(x: 112, y: 68, width: 88, height: 26)
        opacitySlider.frame = NSRect(x: 112, y: 112, width: max(120, width - 174), height: 20)
        opacityValueLabel.frame = NSRect(x: width - 54, y: 112, width: 42, height: 20)
        hintLabel.frame = NSRect(x: 18, y: 154, width: max(1, width - 36), height: 20)
    }

    func updateImagePath(_ path: String?) {
        imagePathLabel.stringValue = path ?? "未选择（当前使用纯色背景）"
    }

    func updateOpacity(_ opacity: CGFloat) {
        let value = min(max(opacity, 0), 1)
        opacitySlider.doubleValue = Double(value)
        opacityValueLabel.stringValue = "\(Int((value * 100).rounded()))%"
    }

    @objc private func chooseImage() {
        onChooseImage?()
    }

    @objc private func clearImage() {
        onClearImage?()
    }

    @objc private func opacitySliderChanged() {
        onOpacityChanged?(CGFloat(opacitySlider.doubleValue))
    }

    private func configure(imagePath: String?, opacity: CGFloat) {
        wantsLayer = true
        addSubview(label("背景图片", frame: NSRect(x: 18, y: 16, width: 100, height: 20), size: 12, weight: .semibold, color: .white))
        imagePathLabel.font = .systemFont(ofSize: 11)
        imagePathLabel.textColor = NSColor(white: 0.6, alpha: 1)
        imagePathLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(imagePathLabel)

        configureButton(chooseButton)
        configureButton(clearButton)
        chooseButton.target = self
        chooseButton.action = #selector(chooseImage)
        clearButton.target = self
        clearButton.action = #selector(clearImage)
        addSubview(chooseButton)
        addSubview(clearButton)

        addSubview(label("图片透明度", frame: NSRect(x: 18, y: 112, width: 86, height: 20), size: 11, weight: .medium, color: NSColor(white: 0.78, alpha: 1)))
        opacitySlider.controlSize = .small
        opacitySlider.isContinuous = true
        opacitySlider.target = self
        opacitySlider.action = #selector(opacitySliderChanged)
        addSubview(opacitySlider)
        opacityValueLabel.alignment = .right
        opacityValueLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        opacityValueLabel.textColor = NSColor(white: 0.78, alpha: 1)
        addSubview(opacityValueLabel)

        hintLabel.font = .systemFont(ofSize: 10)
        hintLabel.textColor = NSColor(white: 0.5, alpha: 1)
        hintLabel.lineBreakMode = .byTruncatingTail
        addSubview(hintLabel)
        updateImagePath(imagePath)
        updateOpacity(opacity)
    }

    private func configureButton(_ button: NSButton) {
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.contentTintColor = accentColor
        button.font = .systemFont(ofSize: 11, weight: .medium)
    }

    private func label(_ text: String, frame: NSRect, size: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.frame = frame
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        return field
    }

    private var accentColor: NSColor {
        NSColor(calibratedRed: 0.97, green: 0.32, blue: 0.26, alpha: 1)
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let usageClient = UsageClient()
    private var panel: UsagePanel?
    private var usageView: UsageView?
    private let historyStore = UsageHistoryStore()
    private var chartPanel: NSPanel?
    private var chartView: UsageChartView?
    private var manualResetPanel: NSPanel?
    private var manualResetDetailsView: ManualResetDetailsView?
    private var appearanceSettingsPanel: NSPanel?
    private var appearanceSettingsView: AppearanceSettingsView?
    private var latestSnapshot = UsageSnapshot.loading
    private var isOneShot = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        isOneShot = CommandLine.arguments.contains("--once")
        if !isOneShot {
            NSApp.setActivationPolicy(.accessory)
            showPanel()
        }
        usageClient.onUpdate = { [weak self] snapshot in
            guard let self else { return }
            self.latestSnapshot = snapshot
            if self.isOneShot {
                self.printSnapshotAndQuit(snapshot)
            } else {
                self.usageView?.snapshot = snapshot
                self.reloadChartIfVisible()
                self.updateManualResetDetailsIfVisible()
            }
        }
        usageClient.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        usageClient.stop()
    }

    private func showPanel() {
        let panel = UsagePanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 176),
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
        applySavedAppearance(to: content)
        content.onManualResetClick = { [weak self] in
            self?.showManualResetDetails()
        }
        let buttonRed = NSColor(calibratedRed: 0.95, green: 0.25, blue: 0.22, alpha: 1)
        let settings = toolbarButton(
            title: "设置",
            action: #selector(showAppearanceSettings),
            frame: NSRect(x: 174, y: 11, width: 36, height: 22),
            color: buttonRed
        )
        settings.toolTip = "设置背景图片和图片透明度"
        settings.setAccessibilityLabel("外观设置")
        content.addSubview(settings)
        let chart = toolbarButton(
            title: "图表",
            action: #selector(showChart),
            frame: NSRect(x: 210, y: 11, width: 34, height: 22),
            color: buttonRed
        )
        chart.toolTip = "查看历史图表"
        chart.setAccessibilityLabel("查看历史图表")
        content.addSubview(chart)
        let refresh = toolbarButton(
            title: "刷新",
            action: #selector(forceRefresh),
            frame: NSRect(x: 244, y: 11, width: 34, height: 22),
            color: buttonRed
        )
        refresh.toolTip = "立即刷新用量"
        refresh.setAccessibilityLabel("立即刷新用量")
        content.addSubview(refresh)
        let close = toolbarButton(
            title: "退出",
            action: #selector(quit),
            frame: NSRect(x: 278, y: 11, width: 35, height: 22),
            color: buttonRed
        )
        close.toolTip = "关闭用量浮窗"
        close.setAccessibilityLabel("退出")
        content.addSubview(close)
        panel.contentView = content

        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - 350, y: frame.maxY - 196))
        }
        panel.orderFrontRegardless()
        self.panel = panel
        usageView = content
    }

    @objc private func showAppearanceSettings() {
        if let appearanceSettingsPanel {
            appearanceSettingsView?.updateImagePath(savedBackgroundImagePath)
            appearanceSettingsView?.updateOpacity(savedBackgroundImageOpacity)
            appearanceSettingsPanel.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 196),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "外观设置"
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false

        let settings = AppearanceSettingsView(
            imagePath: savedBackgroundImagePath,
            opacity: savedBackgroundImageOpacity
        )
        settings.autoresizingMask = [.width, .height]
        settings.onChooseImage = { [weak self] in
            self?.chooseBackgroundImage()
        }
        settings.onClearImage = { [weak self] in
            self?.clearBackgroundImage()
        }
        settings.onOpacityChanged = { [weak self] opacity in
            self?.setBackgroundImageOpacity(opacity)
        }
        panel.contentView = settings
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        appearanceSettingsPanel = panel
        appearanceSettingsView = settings
    }

    private func chooseBackgroundImage() {
        let chooser = NSOpenPanel()
        chooser.title = "选择背景图片"
        chooser.message = "图片会以当前主题色为底进行半透明叠加"
        chooser.canChooseFiles = true
        chooser.canChooseDirectories = false
        chooser.allowsMultipleSelection = false
        chooser.allowedContentTypes = [.image]
        guard chooser.runModal() == .OK, let url = chooser.url,
              let image = NSImage(contentsOf: url) else { return }

        UserDefaults.standard.set(url.path, forKey: AppearancePreference.backgroundImagePath)
        usageView?.backgroundImage = image
        appearanceSettingsView?.updateImagePath(url.path)
    }

    private func clearBackgroundImage() {
        UserDefaults.standard.removeObject(forKey: AppearancePreference.backgroundImagePath)
        usageView?.backgroundImage = nil
        appearanceSettingsView?.updateImagePath(nil)
    }

    private func setBackgroundImageOpacity(_ opacity: CGFloat) {
        let value = min(max(opacity, 0), 1)
        UserDefaults.standard.set(Double(value), forKey: AppearancePreference.backgroundImageOpacity)
        usageView?.backgroundImageOpacity = value
        appearanceSettingsView?.updateOpacity(value)
    }

    private func applySavedAppearance(to view: UsageView) {
        view.backgroundImage = savedBackgroundImage
        view.backgroundImageOpacity = savedBackgroundImageOpacity
    }

    private var savedBackgroundImagePath: String? {
        UserDefaults.standard.string(forKey: AppearancePreference.backgroundImagePath)
    }

    private var savedBackgroundImage: NSImage? {
        guard let path = savedBackgroundImagePath else { return nil }
        return NSImage(contentsOfFile: path)
    }

    private var savedBackgroundImageOpacity: CGFloat {
        let value = UserDefaults.standard.object(forKey: AppearancePreference.backgroundImageOpacity) as? Double
            ?? AppearancePreference.defaultBackgroundImageOpacity
        return CGFloat(min(max(value, 0), 1))
    }

    private func toolbarButton(title: String, action: Selector, frame: NSRect, color: NSColor) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.layer?.borderWidth = 0
        let textColor = color
        button.contentTintColor = textColor
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold),
                .foregroundColor: textColor
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
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 430),
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
        let rangeLabel = chartLabel("时间范围", frame: NSRect(x: 18, y: 59, width: 52, height: 18))
        chart.addSubview(rangeLabel)
        let rangeControl = NSSegmentedControl(
            labels: ["24 小时", "7 天", "30 天", "全部"],
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        rangeControl.controlSize = .small
        rangeControl.segmentStyle = .rounded
        rangeControl.appearance = NSAppearance(named: .darkAqua)
        rangeControl.selectedSegment = ChartRange.week.rawValue
        rangeControl.frame = NSRect(x: 74, y: 56, width: 250, height: 24)
        rangeControl.setAccessibilityLabel("历史图表时间范围")
        rangeControl.target = self
        rangeControl.action = #selector(chartRangeChanged(_:))
        chart.addSubview(rangeControl)

        let seriesLabel = chartLabel("指标", frame: NSRect(x: 348, y: 59, width: 34, height: 18))
        chart.addSubview(seriesLabel)
        let seriesControl = NSSegmentedControl(
            labels: ["主周期", "长周期", "全部"],
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        seriesControl.controlSize = .small
        seriesControl.segmentStyle = .rounded
        seriesControl.appearance = NSAppearance(named: .darkAqua)
        seriesControl.selectedSegment = ChartSeries.both.rawValue
        seriesControl.frame = NSRect(x: 390, y: 56, width: 220, height: 24)
        seriesControl.setAccessibilityLabel("历史图表指标")
        seriesControl.target = self
        seriesControl.action = #selector(chartSeriesChanged(_:))
        chart.addSubview(seriesControl)
        panel.contentView = chart
        panel.center()
        panel.orderFrontRegardless()
        chartPanel = panel
        chartView = chart
        reloadChart()
    }

    private func chartLabel(_ text: String, frame: NSRect) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = NSColor(white: 0.65, alpha: 1)
        return label
    }

    private func showManualResetDetails() {
        let snapshot = latestSnapshot
        if let manualResetPanel {
            manualResetDetailsView?.update(
                count: snapshot.manualResetCount ?? 0,
                credits: snapshot.manualResetCredits
            )
            resizeManualResetPanel(manualResetPanel, creditCount: snapshot.manualResetCredits.count)
            manualResetPanel.makeKeyAndOrderFront(nil)
            return
        }

        let credits = snapshot.manualResetCredits
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: manualResetPanelHeight(creditCount: credits.count)),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "使用限额重置"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false

        let details = ManualResetDetailsView(
            count: snapshot.manualResetCount ?? 0,
            credits: credits,
            frame: panel.contentView?.bounds ?? .zero
        )
        details.autoresizingMask = [.width, .height]
        panel.contentView = details
        panel.center()
        panel.orderFrontRegardless()
        manualResetPanel = panel
        manualResetDetailsView = details
    }

    private func updateManualResetDetailsIfVisible() {
        guard manualResetPanel?.isVisible == true else { return }
        manualResetDetailsView?.update(
            count: latestSnapshot.manualResetCount ?? 0,
            credits: latestSnapshot.manualResetCredits
        )
        if let manualResetPanel {
            resizeManualResetPanel(manualResetPanel, creditCount: latestSnapshot.manualResetCredits.count)
        }
    }

    private func manualResetPanelHeight(creditCount: Int) -> CGFloat {
        max(210, min(420, 105 + CGFloat(max(creditCount, 1)) * 42))
    }

    private func resizeManualResetPanel(_ panel: NSPanel, creditCount: Int) {
        var frame = panel.frame
        let newHeight = manualResetPanelHeight(creditCount: creditCount)
        let heightDelta = newHeight - frame.height
        frame.origin.y -= heightDelta
        frame.size.height = newHeight
        panel.setFrame(frame, display: true, animate: false)
    }

    @objc private func chartRangeChanged(_ sender: NSSegmentedControl) {
        chartView?.chartRange = ChartRange(rawValue: sender.selectedSegment) ?? .week
    }

    @objc private func chartSeriesChanged(_ sender: NSSegmentedControl) {
        chartView?.chartSeries = ChartSeries(rawValue: sender.selectedSegment) ?? .both
    }

    private func reloadChartIfVisible() {
        guard chartPanel?.isVisible == true else { return }
        reloadChart()
    }

    private func reloadChart() {
        guard let chartView else { return }
        DispatchQueue.global(qos: .userInitiated).async { [historyStore] in
            let records = historyStore.allRecords()
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
