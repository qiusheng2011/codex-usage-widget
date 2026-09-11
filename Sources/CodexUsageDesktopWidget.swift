import Foundation
import Darwin
import SwiftUI
import WidgetKit

private struct DesktopWidgetSnapshot: Decodable {
    let available: Bool
    let primaryUsedPercent: Int?
    let primaryWindowMinutes: Int?
    let primaryResetsAt: TimeInterval?
    let secondaryUsedPercent: Int?
    let fetchedAt: TimeInterval

    private enum CodingKeys: String, CodingKey {
        case available
        case primaryUsedPercent
        case primaryWindowMinutes
        case primaryResetsAt
        case secondaryUsedPercent
        case fetchedAt
    }

    init(
        available: Bool,
        primaryUsedPercent: Int?,
        primaryWindowMinutes: Int?,
        primaryResetsAt: TimeInterval?,
        secondaryUsedPercent: Int?,
        fetchedAt: TimeInterval
    ) {
        self.available = available
        self.primaryUsedPercent = primaryUsedPercent
        self.primaryWindowMinutes = primaryWindowMinutes
        self.primaryResetsAt = primaryResetsAt
        self.secondaryUsedPercent = secondaryUsedPercent
        self.fetchedAt = fetchedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        available = try container.decodeIfPresent(Bool.self, forKey: .available) ?? false
        primaryUsedPercent = try container.decodeIfPresent(Int.self, forKey: .primaryUsedPercent)
        primaryWindowMinutes = try container.decodeIfPresent(Int.self, forKey: .primaryWindowMinutes)
        primaryResetsAt = try container.decodeIfPresent(TimeInterval.self, forKey: .primaryResetsAt)
        secondaryUsedPercent = try container.decodeIfPresent(Int.self, forKey: .secondaryUsedPercent)
        fetchedAt = try container.decodeIfPresent(TimeInterval.self, forKey: .fetchedAt) ?? 0
    }

    static let loading = DesktopWidgetSnapshot(
        available: false,
        primaryUsedPercent: nil,
        primaryWindowMinutes: nil,
        primaryResetsAt: nil,
        secondaryUsedPercent: nil,
        fetchedAt: 0
    )
}

private struct DesktopWidgetHistoryRecord: Decodable {
    let recordedAt: TimeInterval
    let snapshot: DesktopWidgetSnapshot
}

private enum DesktopWidgetHistoryStore {
    static func latestSnapshot() -> DesktopWidgetSnapshot {
        // Foundation's applicationSupportDirectory points inside the extension sandbox.
        // The read-only entitlement permits the host's history directory in the real home.
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return .loading }
        let url = URL(fileURLWithPath: String(cString: home), isDirectory: true)
            .appendingPathComponent("Library/Application Support/Codex Usage Widget/usage-history.jsonl")
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return .loading
        }

        let decoder = JSONDecoder()
        return text.split(whereSeparator: { $0.isNewline })
            .reversed()
            .compactMap { line in
                try? decoder.decode(DesktopWidgetHistoryRecord.self, from: Data(line.utf8))
            }
            .first?
            .snapshot ?? .loading
    }
}

private struct DesktopWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: DesktopWidgetSnapshot
}

private struct DesktopWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> DesktopWidgetEntry {
        DesktopWidgetEntry(
            date: Date(),
            snapshot: DesktopWidgetSnapshot(
                available: true,
                primaryUsedPercent: 42,
                primaryWindowMinutes: 300,
                primaryResetsAt: Date().addingTimeInterval(7_200).timeIntervalSince1970,
                secondaryUsedPercent: 18,
                fetchedAt: Date().timeIntervalSince1970
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (DesktopWidgetEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        completion(DesktopWidgetEntry(
            date: Date(),
            snapshot: DesktopWidgetHistoryStore.latestSnapshot()
        ))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DesktopWidgetEntry>) -> Void) {
        let now = Date()
        let entry = DesktopWidgetEntry(
            date: now,
            snapshot: DesktopWidgetHistoryStore.latestSnapshot()
        )
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: now)
            ?? now.addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }
}

private struct DesktopWidgetView: View {
    @Environment(\.widgetFamily) private var family

    let entry: DesktopWidgetEntry

    var body: some View {
        if #available(macOS 14.0, *) {
            content
                .containerBackground(for: .widget) { cardBackground }
        } else {
            content.background(cardBackground)
        }
    }

    private var content: some View {
        Group {
            if family == .systemSmall {
                smallLayout
            } else {
                mediumLayout
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .widgetURL(URL(string: "codexusagewidget://show"))
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            VStack(alignment: .leading, spacing: 3) {
                label("5 小时额度")
                Text(primaryText)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            usageBar
            HStack(spacing: 4) {
                label("长周期")
                Text(secondaryText)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(secondaryColor)
            }
            resetText
        }
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            HStack(alignment: .firstTextBaseline) {
                Text(windowLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.68))
                Spacer()
                Text(updateLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.55))
            }
            HStack(alignment: .bottom) {
                Text(primaryText)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("已用")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    label("长周期")
                    Text(secondaryText)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(secondaryColor)
                }
            }
            usageBar
            HStack {
                resetText
                Spacer()
                Text("点击打开浮窗")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.48))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Codex·用量")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
            Text(entry.snapshot.available ? "LIVE" : "读取中")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(accentColor)
            Spacer()
        }
    }

    private var usageBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.2))
                Capsule()
                    .fill(accentColor)
                    .frame(width: geometry.size.width * progress)
            }
        }
        .frame(height: 8)
    }

    private var resetText: some View {
        Text(resetLabel)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.66))
            .lineLimit(1)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(red: 0.08, green: 0.08, blue: 0.12).opacity(0.97))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(accentColor.opacity(0.55), lineWidth: 1)
            )
    }

    private var primaryText: String {
        guard let value = entry.snapshot.primaryUsedPercent else { return "—" }
        return "\(value)%"
    }

    private var secondaryText: String {
        guard let value = entry.snapshot.secondaryUsedPercent else { return "—" }
        return "\(value)%"
    }

    private var progress: CGFloat {
        guard let value = entry.snapshot.primaryUsedPercent else { return 0 }
        return CGFloat(min(max(value, 0), 100)) / 100
    }

    private var windowLabel: String {
        guard let minutes = entry.snapshot.primaryWindowMinutes else { return "5 小时额度" }
        if minutes % 60 == 0 {
            return "\(minutes / 60) 小时额度"
        }
        return "\(minutes) 分钟额度"
    }

    private var resetLabel: String {
        guard let resetAt = entry.snapshot.primaryResetsAt else { return "重置时间 —" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        return "重置 \(formatter.string(from: Date(timeIntervalSince1970: resetAt)))"
    }

    private var updateLabel: String {
        guard entry.snapshot.fetchedAt > 0 else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSince1970: entry.snapshot.fetchedAt))
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white.opacity(0.68))
    }

    private var accentColor: Color {
        Color(red: 0.97, green: 0.32, blue: 0.26)
    }

    private var secondaryColor: Color {
        Color(red: 0.32, green: 0.68, blue: 1)
    }
}

struct CodexUsageDesktopWidget: Widget {
    private let kind = "CodexUsageDesktopWidget"

    var body: some WidgetConfiguration {
        configuration
            .contentMarginsDisabled()
            .containerBackgroundRemovable(false)
    }

    private var configuration: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DesktopWidgetProvider()) { entry in
            DesktopWidgetView(entry: entry)
        }
        .configurationDisplayName("Codex 用量")
        .description("在 macOS 桌面显示 5 小时和长周期用量。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct CodexUsageDesktopWidgetBundle: WidgetBundle {
    var body: some Widget {
        CodexUsageDesktopWidget()
    }
}
