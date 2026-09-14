import AppKit
import Foundation
import UserNotifications
import WidgetKit

/// Appends successful usage responses outside the app bundle so app updates do not remove history.
final class UsageHistoryStore {
    private let fileURL: URL?

    init() {
        fileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Codex Usage Widget", isDirectory: true)
            .appendingPathComponent("usage-history.jsonl")
    }

    func append(_ snapshot: UsageSnapshot, language: AppLanguage = LanguagePreference.current) {
        guard let fileURL,
              let data = try? JSONEncoder().encode(UsageHistoryRecord(
                  version: 1,
                  recordedAt: Date().timeIntervalSince1970,
                  language: language.rawValue,
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

/// Schedules one local notification for the current five-hour rate-limit reset.
/// The notification is delivered by macOS and does not require any network access.
final class PrimaryResetNotificationScheduler {
    private let center = UNUserNotificationCenter.current()
    private let requestIdentifier = "codex-usage-widget.primary-reset"
    private var authorizationResolved = false
    private var authorizationGranted = false
    private var pendingResetAt: TimeInterval?

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.authorizationResolved = true
                self.authorizationGranted = granted
                if granted {
                    self.schedulePendingReset()
                } else {
                    self.center.removePendingNotificationRequests(withIdentifiers: [self.requestIdentifier])
                }
            }
        }
    }

    func schedule(for snapshot: UsageSnapshot) {
        guard snapshot.available, let resetAt = snapshot.primaryResetsAt else { return }
        pendingResetAt = resetAt
        guard authorizationResolved, authorizationGranted else { return }
        schedule(resetAt: resetAt)
    }

    private func schedulePendingReset() {
        guard let pendingResetAt else { return }
        schedule(resetAt: pendingResetAt)
    }

    private func schedule(resetAt: TimeInterval) {
        center.removePendingNotificationRequests(withIdentifiers: [requestIdentifier])

        let interval = resetAt - Date().timeIntervalSince1970
        guard interval > 1 else { return }

        let content = UNMutableNotificationContent()
        content.title = L10n.text("5 小时额度已重置", "5-hour limit reset")
        content.body = L10n.text("额度已更新，可以继续使用。", "Your usage is updated and ready to use.")
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(interval, 1),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: requestIdentifier,
            content: content,
            trigger: trigger
        )
        center.add(request)
    }
}

/// A read-only JSON-RPC client for the locally installed Codex app server.
/// It never reads, writes, or exposes authentication tokens.
final class UsageClient {
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
            if let output = process.standardOutput as? Pipe {
                output.fileHandleForReading.readabilityHandler = nil
            }
            process.terminate()
            self.process = nil
            input = nil
        }
        outputBuffer.removeAll()
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
        WidgetCenter.shared.reloadAllTimelines()
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
