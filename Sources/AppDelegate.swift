import AppKit
import Foundation
import UniformTypeIdentifiers
import WidgetKit

enum PanelEdge {
    case left
    case right
    case top
    case bottom
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let expandedPanelSize = NSSize(width: 320, height: 176)
    private let compactPanelSize = NSSize(width: 126, height: 66)
    private let edgeSnapDistance: CGFloat = 28
    private let usageClient = UsageClient()
    private let resetNotificationScheduler = PrimaryResetNotificationScheduler()
    private var panel: UsagePanel?
    private var menuBarStatusItem: NSStatusItem?
    private var usageView: UsageView?
    private let historyStore = UsageHistoryStore()
    private var chartPanel: NSPanel?
    private var chartView: UsageChartView?
    private var manualResetPanel: NSPanel?
    private var manualResetDetailsView: ManualResetDetailsView?
    private var appearanceSettingsPanel: NSPanel?
    private var appearanceSettingsView: AppearanceSettingsView?
    private var panelToolbarButtons: [NSButton] = []
    private var chartRangeLabel: NSTextField?
    private var chartSeriesLabel: NSTextField?
    private var chartRangeControl: NSSegmentedControl?
    private var chartSeriesControl: NSSegmentedControl?
    private var latestSnapshot = UsageSnapshot.loading
    private var panelEdge: PanelEdge?
    private var pointerInsidePanel = false
    private var compactCollapseTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        LegacyPreferenceMigration.applyIfNeeded()
        LanguagePreference.synchronizeDesktopWidget()
        WidgetCenter.shared.reloadAllTimelines()
        NSApp.setActivationPolicy(.accessory)
        resetNotificationScheduler.requestAuthorization()
        configureMenuBarStatusItem()
        showPanel()
        usageClient.onUpdate = { [weak self] snapshot in
            guard let self else { return }
            self.latestSnapshot = snapshot
            self.resetNotificationScheduler.schedule(for: snapshot)
            self.updateMenuBarStatus(snapshot)
            self.usageView?.snapshot = snapshot
            self.reloadChartIfVisible()
            self.updateManualResetDetailsIfVisible()
        }
        usageClient.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        usageClient.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        revealPanel()
        return true
    }

    private func showPanel() {
        if panel != nil {
            revealPanel()
            return
        }

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
        content.onDragEnded = { [weak self] in
            self?.finishPanelDrag()
        }
        content.onMouseEnteredPanel = { [weak self] in
            self?.panelPointerEntered()
        }
        content.onMouseExitedPanel = { [weak self] in
            self?.panelPointerExited()
        }
        let accentColor = savedAccentColor
        let settings = toolbarButton(
            title: L10n.text("设置", "Settings"),
            action: #selector(showAppearanceSettings),
            frame: NSRect(x: 138, y: 11, width: 36, height: 22),
            color: accentColor
        )
        settings.toolTip = L10n.text("设置背景图片、透明度和极简自动缩放", "Set the background image, opacity, and compact mode")
        settings.setAccessibilityLabel(L10n.text("外观设置", "Appearance settings"))
        content.addSubview(settings)
        let chart = toolbarButton(
            title: L10n.text("图表", "Chart"),
            action: #selector(showChart),
            frame: NSRect(x: 174, y: 11, width: 34, height: 22),
            color: accentColor
        )
        chart.toolTip = L10n.text("查看历史图表", "View usage history chart")
        chart.setAccessibilityLabel(L10n.text("查看历史图表", "View usage history chart"))
        content.addSubview(chart)
        let refresh = toolbarButton(
            title: L10n.text("刷新", "Refresh"),
            action: #selector(forceRefresh),
            frame: NSRect(x: 208, y: 11, width: 34, height: 22),
            color: accentColor
        )
        refresh.toolTip = L10n.text("立即刷新用量", "Refresh usage now")
        refresh.setAccessibilityLabel(L10n.text("立即刷新用量", "Refresh usage now"))
        content.addSubview(refresh)
        let hide = toolbarButton(
            title: L10n.text("隐藏", "Hide"),
            action: #selector(hidePanel),
            frame: NSRect(x: 242, y: 11, width: 36, height: 22),
            color: accentColor
        )
        hide.toolTip = L10n.text("隐藏用量浮窗，数据会继续更新", "Hide the widget; usage will keep updating")
        hide.setAccessibilityLabel(L10n.text("隐藏用量浮窗", "Hide usage widget"))
        content.addSubview(hide)
        let close = toolbarButton(
            title: L10n.text("退出", "Quit"),
            action: #selector(quit),
            frame: NSRect(x: 278, y: 11, width: 35, height: 22),
            color: accentColor
        )
        close.toolTip = L10n.text("关闭用量浮窗", "Quit Codex Usage Widget")
        close.setAccessibilityLabel(L10n.text("退出", "Quit"))
        content.addSubview(close)
        panel.contentView = content

        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - 350, y: frame.maxY - 196))
        }
        panel.orderFrontRegardless()
        self.panel = panel
        usageView = content
        panelToolbarButtons = [settings, chart, refresh, hide, close]
        updatePanelLanguage()
    }

    private func revealPanel() {
        guard let panel else {
            showPanel()
            return
        }
        compactCollapseTimer?.invalidate()
        compactCollapseTimer = nil
        pointerInsidePanel = false
        if panelEdge != nil {
            setPanelCompact(false)
        }
        panel.orderFrontRegardless()
    }

    private func updatePanelLanguage() {
        usageView?.updateLanguage()
        menuBarStatusItem?.button?.toolTip = L10n.text("打开 Codex 用量浮窗", "Open Codex Usage Widget")
        let language = LanguagePreference.current
        let titles = language.isChinese
            ? ["设置", "图表", "刷新", "隐藏", "退出"]
            : ["Settings", "Chart", "Refresh", "Hide", "Quit"]
        let tooltips = language.isChinese
            ? [
                "设置背景图片、透明度和极简自动缩放",
                "查看历史图表",
                "立即刷新用量",
                "隐藏用量浮窗，数据会继续更新",
                "关闭用量浮窗"
            ]
            : [
                "Set the background image, opacity, and compact mode",
                "View usage history chart",
                "Refresh usage now",
                "Hide the widget; usage will keep updating",
                "Quit Codex Usage Widget"
            ]
        let accessibilityLabels = language.isChinese
            ? ["外观设置", "查看历史图表", "立即刷新用量", "隐藏用量浮窗", "退出"]
            : ["Appearance settings", "View usage history chart", "Refresh usage now", "Hide usage widget", "Quit"]
        let frames = language.isChinese
            ? [
                NSRect(x: 138, y: 11, width: 36, height: 22),
                NSRect(x: 174, y: 11, width: 34, height: 22),
                NSRect(x: 208, y: 11, width: 34, height: 22),
                NSRect(x: 242, y: 11, width: 36, height: 22),
                NSRect(x: 278, y: 11, width: 35, height: 22)
            ]
            : [
                NSRect(x: 112, y: 11, width: 48, height: 22),
                NSRect(x: 160, y: 11, width: 36, height: 22),
                NSRect(x: 196, y: 11, width: 48, height: 22),
                NSRect(x: 244, y: 11, width: 32, height: 22),
                NSRect(x: 276, y: 11, width: 28, height: 22)
            ]
        let toolbarFont = NSFont.monospacedSystemFont(ofSize: language.isChinese ? 10 : 9, weight: .bold)
        for (index, button) in panelToolbarButtons.enumerated() {
            guard index < titles.count else { continue }
            button.frame = frames[index]
            button.toolTip = tooltips[index]
            button.setAccessibilityLabel(accessibilityLabels[index])
            button.attributedTitle = NSAttributedString(
                string: titles[index],
                attributes: [
                    .font: toolbarFont,
                    .foregroundColor: savedAccentColor
                ]
            )
        }
    }

    private func panelPointerEntered() {
        pointerInsidePanel = true
        compactCollapseTimer?.invalidate()
        compactCollapseTimer = nil
        guard panelEdge != nil else { return }
        setPanelCompact(false)
    }

    private func panelPointerExited() {
        pointerInsidePanel = false
        scheduleCompactCollapse()
    }

    private func scheduleCompactCollapse() {
        compactCollapseTimer?.invalidate()
        compactCollapseTimer = nil
        guard autoCollapseEnabled, panelEdge != nil else { return }
        compactCollapseTimer = Timer.scheduledTimer(withTimeInterval: compactCollapseDelay, repeats: false) { [weak self] _ in
            guard let self, !self.pointerInsidePanel, self.panelEdge != nil else { return }
            self.setPanelCompact(true)
        }
    }

    private func finishPanelDrag() {
        compactCollapseTimer?.invalidate()
        compactCollapseTimer = nil
        guard let panel else { return }

        let frame = panel.frame
        guard let screen = screen(for: frame) else {
            panelEdge = nil
            setPanelCompact(false)
            return
        }
        let visibleFrame = screen.visibleFrame
        let candidates: [(PanelEdge, CGFloat)] = [
            (.left, abs(frame.minX - visibleFrame.minX)),
            (.right, abs(visibleFrame.maxX - frame.maxX)),
            (.top, abs(visibleFrame.maxY - frame.maxY)),
            (.bottom, abs(frame.minY - visibleFrame.minY))
        ]
        guard let nearest = candidates.min(by: { $0.1 < $1.1 }), nearest.1 <= edgeSnapDistance else {
            panelEdge = nil
            setPanelCompact(false)
            return
        }

        panelEdge = nearest.0
        let expandedOrigin = anchoredOrigin(
            for: nearest.0,
            size: expandedPanelSize,
            in: visibleFrame,
            currentOrigin: frame.origin
        )
        panel.setFrame(NSRect(origin: expandedOrigin, size: expandedPanelSize), display: true)
        pointerInsidePanel = panel.frame.contains(NSEvent.mouseLocation)
        setPanelCompact(autoCollapseEnabled && !pointerInsidePanel)
    }

    private func setPanelCompact(_ compact: Bool) {
        guard let panel else { return }
        let size = compact ? compactPanelSize : expandedPanelSize
        let currentFrame = panel.frame
        var origin = currentFrame.origin
        if let edge = panelEdge, let screen = screen(for: currentFrame) {
            origin = anchoredOrigin(
                for: edge,
                size: size,
                in: screen.visibleFrame,
                currentOrigin: currentFrame.origin
            )
        } else if !compact {
            origin = currentFrame.origin
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        usageView?.setCompactPresentation(compact)
    }

    private func screen(for frame: NSRect) -> NSScreen? {
        let center = NSPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(center) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func anchoredOrigin(
        for edge: PanelEdge,
        size: NSSize,
        in visibleFrame: NSRect,
        currentOrigin: NSPoint
    ) -> NSPoint {
        let maxX = max(visibleFrame.minX, visibleFrame.maxX - size.width)
        let maxY = max(visibleFrame.minY, visibleFrame.maxY - size.height)
        switch edge {
        case .left:
            return NSPoint(
                x: visibleFrame.minX,
                y: min(max(currentOrigin.y, visibleFrame.minY), maxY)
            )
        case .right:
            return NSPoint(
                x: maxX,
                y: min(max(currentOrigin.y, visibleFrame.minY), maxY)
            )
        case .top:
            return NSPoint(
                x: min(max(currentOrigin.x, visibleFrame.minX), maxX),
                y: maxY
            )
        case .bottom:
            return NSPoint(
                x: min(max(currentOrigin.x, visibleFrame.minX), maxX),
                y: visibleFrame.minY
            )
        }
    }

    @objc private func showAppearanceSettings() {
        if let appearanceSettingsPanel {
            appearanceSettingsView?.updateImagePath(savedBackgroundImagePath)
            appearanceSettingsView?.updateOpacity(savedBackgroundImageOpacity)
            appearanceSettingsView?.updateAccentColor(savedAccentColor)
            appearanceSettingsView?.updateAutoCollapse(autoCollapseEnabled)
            appearanceSettingsView?.updateCollapseDelay(compactCollapseDelay)
            appearanceSettingsView?.updateMenuBarVisible(menuBarStatusVisible)
            appearanceSettingsView?.updateLanguage(LanguagePreference.current)
            appearanceSettingsPanel.makeKeyAndOrderFront(nil)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 324),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = L10n.text("外观设置", "Appearance Settings")
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false

        let settings = AppearanceSettingsView(
            imagePath: savedBackgroundImagePath,
            opacity: savedBackgroundImageOpacity,
            accentColor: savedAccentColor,
            autoCollapseEnabled: autoCollapseEnabled,
            collapseDelay: compactCollapseDelay,
            menuBarVisible: menuBarStatusVisible,
            language: LanguagePreference.current
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
        settings.onAutoCollapseChanged = { [weak self] enabled in
            self?.setAutoCollapseEnabled(enabled)
        }
        settings.onCollapseDelayChanged = { [weak self] delay in
            self?.setCompactCollapseDelay(delay)
        }
        settings.onMenuBarVisibilityChanged = { [weak self] visible in
            self?.setMenuBarStatusVisible(visible)
        }
        settings.onAccentColorChanged = { [weak self] color in
            self?.setAccentColor(color)
        }
        settings.onLanguageChanged = { [weak self] language in
            self?.setLanguage(language)
        }
        panel.contentView = settings
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        appearanceSettingsPanel = panel
        appearanceSettingsView = settings
    }

    private func configureMenuBarStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(menuBarStatusItemClicked)
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
            button.font = menuBarFont
            button.contentTintColor = menuBarAccentColor
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
            button.toolTip = L10n.text("打开 Codex 用量浮窗", "Open Codex Usage Widget")
        }
        menuBarStatusItem = statusItem
        statusItem.isVisible = menuBarStatusVisible
        updateMenuBarStatus(latestSnapshot)
    }

    private func updateMenuBarStatus(_ snapshot: UsageSnapshot) {
        guard let button = menuBarStatusItem?.button else { return }
        let primary = snapshot.primaryUsedPercent.map { "\($0)%" } ?? "—"
        let secondary = snapshot.secondaryUsedPercent.map { "\($0)%" } ?? "—"
        let title = "CODEX(5h:\(primary)|1W:\(secondary))"
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.image = menuBarImage(primary: primary, secondary: secondary)
        button.setAccessibilityLabel(title)
    }

    private var menuBarFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: 13, weight: .bold)
    }

    private var menuBarAccentColor: NSColor {
        savedAccentColor
    }

    private func menuBarImage(primary: String, secondary: String) -> NSImage {
        let attributedTitle = NSMutableAttributedString()
        let whiteAttributes: [NSAttributedString.Key: Any] = [
            .font: menuBarFont,
            .foregroundColor: NSColor.white
        ]
        let redAttributes: [NSAttributedString.Key: Any] = [
            .font: menuBarFont,
            .foregroundColor: menuBarAccentColor
        ]
        attributedTitle.append(NSAttributedString(string: "CODEX(5h:", attributes: whiteAttributes))
        attributedTitle.append(NSAttributedString(string: primary, attributes: redAttributes))
        attributedTitle.append(NSAttributedString(string: "|1W:", attributes: whiteAttributes))
        attributedTitle.append(NSAttributedString(string: secondary, attributes: redAttributes))
        attributedTitle.append(NSAttributedString(string: ")", attributes: whiteAttributes))

        let textSize = attributedTitle.size()
        let imageSize = NSSize(width: ceil(textSize.width) + 4, height: 20)
        let image = NSImage(size: imageSize, flipped: false) { _ in
            attributedTitle.draw(at: NSPoint(x: 2, y: max(0, (imageSize.height - textSize.height) / 2)))
            return true
        }
        image.isTemplate = false
        return image
    }

    @objc private func menuBarStatusItemClicked() {
        revealPanel()
    }

    private func chooseBackgroundImage() {
        let chooser = NSOpenPanel()
        chooser.title = L10n.text("选择背景图片", "Choose Background Image")
        chooser.message = L10n.text("图片会以当前主题色为底进行半透明叠加", "The image is added as a translucent layer over the current theme")
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

    private func setAutoCollapseEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: AppearancePreference.autoCollapseEnabled)
        compactCollapseTimer?.invalidate()
        compactCollapseTimer = nil
        if enabled {
            if !pointerInsidePanel {
                scheduleCompactCollapse()
            }
        } else {
            setPanelCompact(false)
        }
        appearanceSettingsView?.updateAutoCollapse(enabled)
    }

    private func setCompactCollapseDelay(_ delay: TimeInterval) {
        let value = min(max(delay.rounded(), 1), 10)
        UserDefaults.standard.set(value, forKey: AppearancePreference.compactCollapseDelay)
        appearanceSettingsView?.updateCollapseDelay(value)
    }

    private func setMenuBarStatusVisible(_ visible: Bool) {
        UserDefaults.standard.set(visible, forKey: AppearancePreference.menuBarStatusVisible)
        menuBarStatusItem?.isVisible = visible
        appearanceSettingsView?.updateMenuBarVisible(visible)
    }

    private func setAccentColor(_ color: NSColor) {
        AccentColorPreference.set(color)
        usageView?.updateAccentColor()
        appearanceSettingsView?.updateAccentColor(savedAccentColor)
        chartView?.updateAccentColor()
        updatePanelLanguage()
        updateMenuBarStatus(latestSnapshot)
    }

    private func setLanguage(_ language: AppLanguage) {
        guard LanguagePreference.current != language else { return }
        LanguagePreference.set(language)
        WidgetCenter.shared.reloadAllTimelines()
        updatePanelLanguage()
        appearanceSettingsPanel?.title = L10n.text("外观设置", "Appearance Settings")
        appearanceSettingsView?.updateLanguage(language)
        updateChartLanguage()
        manualResetPanel?.title = L10n.text("使用限额重置", "Manual Reset Credits")
        manualResetDetailsView?.updateLanguage()
        resetNotificationScheduler.schedule(for: latestSnapshot)
    }

    private func updateChartLanguage() {
        chartPanel?.title = L10n.text("Codex 用量历史", "Codex Usage History")
        chartRangeLabel?.stringValue = L10n.text("时间范围", "Range")
        chartSeriesLabel?.stringValue = L10n.text("指标", "Metrics")
        chartRangeControl?.setLabel(L10n.text("24 小时", "24 Hours"), forSegment: 0)
        chartRangeControl?.setLabel(L10n.text("7 天", "7 Days"), forSegment: 1)
        chartRangeControl?.setLabel(L10n.text("30 天", "30 Days"), forSegment: 2)
        chartRangeControl?.setLabel(L10n.text("全部", "All"), forSegment: 3)
        chartRangeControl?.setAccessibilityLabel(L10n.text("历史图表时间范围", "History chart range"))
        chartSeriesControl?.setLabel(L10n.text("主周期", "Primary"), forSegment: 0)
        chartSeriesControl?.setLabel(L10n.text("长周期", "Long cycle"), forSegment: 1)
        chartSeriesControl?.setLabel(L10n.text("全部", "All"), forSegment: 2)
        chartSeriesControl?.setAccessibilityLabel(L10n.text("历史图表指标", "History chart metrics"))
        chartView?.updateLanguage()
    }

    private func applySavedAppearance(to view: UsageView) {
        view.backgroundImage = savedBackgroundImage
        view.backgroundImageOpacity = savedBackgroundImageOpacity
    }

    private var savedBackgroundImagePath: String? {
        UserDefaults.standard.string(forKey: AppearancePreference.backgroundImagePath)
    }

    private var savedAccentColor: NSColor {
        AccentColorPreference.current
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

    private var autoCollapseEnabled: Bool {
        UserDefaults.standard.object(forKey: AppearancePreference.autoCollapseEnabled) as? Bool
            ?? AppearancePreference.defaultAutoCollapseEnabled
    }

    private var compactCollapseDelay: TimeInterval {
        let value = UserDefaults.standard.object(forKey: AppearancePreference.compactCollapseDelay) as? Double
            ?? AppearancePreference.defaultCompactCollapseDelay
        return min(max(value, 1), 10)
    }

    private var menuBarStatusVisible: Bool {
        UserDefaults.standard.object(forKey: AppearancePreference.menuBarStatusVisible) as? Bool
            ?? AppearancePreference.defaultMenuBarStatusVisible
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

    @objc private func hidePanel() {
        compactCollapseTimer?.invalidate()
        compactCollapseTimer = nil
        pointerInsidePanel = false
        panel?.orderOut(nil)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func forceRefresh() {
        usageClient.forceRefresh()
    }

    @objc private func showChart() {
        if let chartPanel {
            updateChartLanguage()
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
        panel.title = L10n.text("Codex 用量历史", "Codex Usage History")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false

        let chart = UsageChartView(frame: panel.contentView?.bounds ?? .zero)
        chart.autoresizingMask = [.width, .height]
        let rangeLabel = chartLabel(L10n.text("时间范围", "Range"), frame: NSRect(x: 18, y: 59, width: 52, height: 18))
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
        rangeControl.setAccessibilityLabel(L10n.text("历史图表时间范围", "History chart range"))
        rangeControl.target = self
        rangeControl.action = #selector(chartRangeChanged(_:))
        chart.addSubview(rangeControl)

        let seriesLabel = chartLabel(L10n.text("指标", "Metrics"), frame: NSRect(x: 348, y: 59, width: 34, height: 18))
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
        seriesControl.setAccessibilityLabel(L10n.text("历史图表指标", "History chart metrics"))
        seriesControl.target = self
        seriesControl.action = #selector(chartSeriesChanged(_:))
        chart.addSubview(seriesControl)
        panel.contentView = chart
        panel.center()
        panel.orderFrontRegardless()
        chartPanel = panel
        chartView = chart
        chartRangeLabel = rangeLabel
        chartSeriesLabel = seriesLabel
        chartRangeControl = rangeControl
        chartSeriesControl = seriesControl
        updateChartLanguage()
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
            manualResetPanel.title = L10n.text("使用限额重置", "Manual Reset Credits")
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
        panel.title = L10n.text("使用限额重置", "Manual Reset Credits")
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

}

extension AppDelegate {
    @MainActor
    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: { $0.scheme == "codexusagewidget" }) else { return }
        revealPanel()
    }
}

/// Runs the connectivity check without initializing an AppKit application bundle. This prevents
/// LaunchServices from registering a temporary build as a competing WidgetKit host app.
final class OneShotUsageRunner {
    private let usageClient = UsageClient()
    private var hasPrintedSnapshot = false

    func run() {
        usageClient.onUpdate = { [weak self] snapshot in
            guard let self, !self.hasPrintedSnapshot else { return }
            self.hasPrintedSnapshot = true
            if let data = try? JSONEncoder().encode(snapshot),
               let text = String(data: data, encoding: .utf8) {
                FileHandle.standardOutput.write(Data((text + "\n").utf8))
            }
            self.usageClient.stop()
        }
        usageClient.start()
        while !hasPrintedSnapshot {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        }
    }
}

@main
enum CodexUsageWidgetMain {
    static func main() {
        if CommandLine.arguments.contains("--once") {
            let oneShotRunner = OneShotUsageRunner()
            oneShotRunner.run()
        } else {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.run()
        }
    }
}
