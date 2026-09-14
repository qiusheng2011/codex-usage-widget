import AppKit

final class UsageChartView: NSView {
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
        drawText(L10n.text("Codex·用量趋势", "Codex Usage Trend"), at: NSPoint(x: 18, y: 14), font: .systemFont(ofSize: 15, weight: .bold), color: .white)
        drawText(
            L10n.text(
                "时间：\(chartRange.title(for: L10n.language))    当前显示 \(visibleRecords.count) 条 / 历史 \(records.count) 条",
                "Range: \(chartRange.title(for: L10n.language))    Showing \(visibleRecords.count) / \(records.count) records"
            ),
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
            drawText(L10n.text("当前筛选范围暂无数据", "No data in the selected range"), at: NSPoint(x: bounds.midX - 58, y: bounds.midY), font: .systemFont(ofSize: 14, weight: .medium), color: NSColor(white: 0.65, alpha: 1))
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
            drawText(L10n.text("主周期", "Primary"), at: NSPoint(x: x, y: point.y), font: .systemFont(ofSize: 10, weight: .medium), color: accentColor)
            x += 54
        }
        if chartSeries != .primary {
            drawText(L10n.text("长周期", "Long cycle"), at: NSPoint(x: x, y: point.y), font: .systemFont(ofSize: 10, weight: .medium), color: secondaryColor)
        }
    }

    func updateLanguage() {
        needsDisplay = true
    }

    func updateAccentColor() {
        needsDisplay = true
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
        return L10n.dateFormatter(format: "MM-dd HH:mm").string(from: Date(timeIntervalSince1970: timestamp))
    }

    private var accentColor: NSColor {
        AccentColorPreference.current
    }

    private var secondaryColor: NSColor {
        NSColor(calibratedRed: 0.32, green: 0.68, blue: 1, alpha: 1)
    }
}
