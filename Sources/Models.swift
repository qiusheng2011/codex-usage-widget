import Foundation
import AppKit

enum AppLanguage: String, Codable {
    case chinese = "zh-Hans"
    case english = "en"

    var isChinese: Bool { self == .chinese }

    static func from(rawValue: String?) -> AppLanguage {
        guard let rawValue, let language = AppLanguage(rawValue: rawValue) else {
            return .chinese
        }
        return language
    }
}

enum LanguagePreference {
    static let key = "appearance.language"
    static let defaultLanguage = AppLanguage.chinese
    private static let sharedLanguageFileName = "language"

    static var current: AppLanguage {
        AppLanguage.from(rawValue: UserDefaults.standard.string(forKey: key))
    }

    static func set(_ language: AppLanguage) {
        UserDefaults.standard.set(language.rawValue, forKey: key)
        persistForDesktopWidget(language)
    }

    static func synchronizeDesktopWidget() {
        persistForDesktopWidget(current)
    }

    private static func persistForDesktopWidget(_ language: AppLanguage) {
        guard let directoryURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Codex Usage Widget", isDirectory: true) else {
            return
        }

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try Data(language.rawValue.utf8).write(
                to: directoryURL.appendingPathComponent(sharedLanguageFileName),
                options: .atomic
            )
        } catch {
            // The app UserDefaults value remains authoritative if the Widget marker cannot be written.
        }
    }
}

enum L10n {
    static var language: AppLanguage { LanguagePreference.current }

    static func text(_ chinese: String, _ english: String) -> String {
        language.isChinese ? chinese : english
    }

    static func dateFormatter(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.isChinese ? "zh_CN" : "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }
}

struct ManualResetCredit: Codable {
    var resetType: String
    var status: String
    var title: String?
    var description: String?
    var expiresAt: TimeInterval?
}

enum AppearancePreference {
    static let backgroundImagePath = "appearance.backgroundImagePath"
    static let backgroundImageOpacity = "appearance.backgroundImageOpacity"
    static let accentColor = "appearance.accentColor"
    static let autoCollapseEnabled = "appearance.autoCollapseEnabled"
    static let compactCollapseDelay = "appearance.compactCollapseDelay"
    static let menuBarStatusVisible = "appearance.menuBarStatusVisible"
    static let language = LanguagePreference.key
    static let defaultBackgroundImageOpacity = 0.28
    static let defaultAccentColor = NSColor(calibratedRed: 0.97, green: 0.32, blue: 0.26, alpha: 1)
    static let defaultAutoCollapseEnabled = true
    static let defaultCompactCollapseDelay = 2.0
    static let defaultMenuBarStatusVisible = true
}

enum AccentColorPreference {
    private static let redKey = "red"
    private static let greenKey = "green"
    private static let blueKey = "blue"
    private static let alphaKey = "alpha"

    static var current: NSColor {
        guard let values = UserDefaults.standard.dictionary(forKey: AppearancePreference.accentColor),
              let red = component(values[redKey]),
              let green = component(values[greenKey]),
              let blue = component(values[blueKey]) else {
            return AppearancePreference.defaultAccentColor
        }
        let alpha = component(values[alphaKey]) ?? 1
        return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }

    static func set(_ color: NSColor) {
        guard let rgbColor = color.usingColorSpace(.deviceRGB) else { return }
        UserDefaults.standard.set([
            redKey: Double(rgbColor.redComponent),
            greenKey: Double(rgbColor.greenComponent),
            blueKey: Double(rgbColor.blueComponent),
            alphaKey: Double(rgbColor.alphaComponent)
        ], forKey: AppearancePreference.accentColor)
    }

    private static func component(_ value: Any?) -> CGFloat? {
        guard let number = value as? NSNumber else { return nil }
        return CGFloat(min(max(number.doubleValue, 0), 1))
    }
}

/// Keeps existing appearance preferences when the development bundle identifier changes.
enum LegacyPreferenceMigration {
    private static let completedKey = "migration.local.codex.usage-widget.completed"
    private static let legacyBundleIdentifier = "local.codex.usage-widget"
    private static let keys = [
        AppearancePreference.backgroundImagePath,
        AppearancePreference.backgroundImageOpacity,
        AppearancePreference.accentColor,
        AppearancePreference.autoCollapseEnabled,
        AppearancePreference.compactCollapseDelay,
        AppearancePreference.menuBarStatusVisible,
        AppearancePreference.language,
    ]

    static func applyIfNeeded() {
        let currentDefaults = UserDefaults.standard
        guard !currentDefaults.bool(forKey: completedKey),
              let legacyDefaults = UserDefaults(suiteName: legacyBundleIdentifier) else {
            return
        }

        for key in keys where currentDefaults.object(forKey: key) == nil {
            if let value = legacyDefaults.object(forKey: key) {
                currentDefaults.set(value, forKey: key)
            }
        }
        currentDefaults.set(true, forKey: completedKey)
    }
}

struct UsageSnapshot: Codable {
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

struct UsageHistoryRecord: Codable {
    let version: Int
    let recordedAt: TimeInterval
    let language: String?
    let snapshot: UsageSnapshot
}

enum ChartRange: Int {
    case day
    case week
    case month
    case all

    func title(for language: AppLanguage) -> String {
        switch self {
        case .day: return language.isChinese ? "24 小时" : "24 Hours"
        case .week: return language.isChinese ? "7 天" : "7 Days"
        case .month: return language.isChinese ? "30 天" : "30 Days"
        case .all: return language.isChinese ? "全部" : "All"
        }
    }
}

enum ChartSeries: Int {
    case primary
    case secondary
    case both
}
