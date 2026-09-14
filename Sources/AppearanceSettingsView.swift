import AppKit

final class AppearanceSettingsView: NSView {
    var onChooseImage: (() -> Void)?
    var onClearImage: (() -> Void)?
    var onOpacityChanged: ((CGFloat) -> Void)?
    var onAutoCollapseChanged: ((Bool) -> Void)?
    var onCollapseDelayChanged: ((TimeInterval) -> Void)?
    var onMenuBarVisibilityChanged: ((Bool) -> Void)?
    var onLanguageChanged: ((AppLanguage) -> Void)?
    var onAccentColorChanged: ((NSColor) -> Void)?

    private var language = LanguagePreference.current
    private let backgroundLabel = NSTextField(labelWithString: "")
    private let opacityLabel = NSTextField(labelWithString: "")
    private let accentColorLabel = NSTextField(labelWithString: "")
    private let collapseDelayLabel = NSTextField(labelWithString: "")
    private let languageLabel = NSTextField(labelWithString: "")
    private let imagePathLabel = NSTextField(labelWithString: "")
    private let opacitySlider = NSSlider(value: 0.28, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let opacityValueLabel = NSTextField(labelWithString: "28%")
    private let chooseButton = NSButton(title: "选择图片", target: nil, action: nil)
    private let clearButton = NSButton(title: "清除图片", target: nil, action: nil)
    private let autoCollapseButton = NSButton(checkboxWithTitle: "自动缩放为极简卡片", target: nil, action: nil)
    private let menuBarButton = NSButton(checkboxWithTitle: "菜单栏显示 CODEX", target: nil, action: nil)
    private let accentColorWell = NSColorWell(frame: .zero)
    private let resetAccentColorButton = NSButton(title: "恢复默认", target: nil, action: nil)
    private let collapseDelaySlider = NSSlider(value: 2, minValue: 1, maxValue: 10, target: nil, action: nil)
    private let collapseDelayValueLabel = NSTextField(labelWithString: "2 秒")
    private let hintLabel = NSTextField(labelWithString: "主题色保持为当前深色主题，图片只会作为半透明背景叠加。")
    private let languageControl = NSSegmentedControl(
        labels: ["中文", "English"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )

    override var isFlipped: Bool { true }

    init(
        imagePath: String?,
        opacity: CGFloat,
        accentColor: NSColor,
        autoCollapseEnabled: Bool,
        collapseDelay: TimeInterval,
        menuBarVisible: Bool,
        language: AppLanguage = LanguagePreference.current
    ) {
        self.language = language
        super.init(frame: .zero)
        configure(
            imagePath: imagePath,
            opacity: opacity,
            accentColor: accentColor,
            autoCollapseEnabled: autoCollapseEnabled,
            collapseDelay: collapseDelay,
            menuBarVisible: menuBarVisible
        )
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure(
            imagePath: nil,
            opacity: 0.28,
            accentColor: AppearancePreference.defaultAccentColor,
            autoCollapseEnabled: true,
            collapseDelay: 2,
            menuBarVisible: true
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor(calibratedRed: 0.08, green: 0.08, blue: 0.12, alpha: 1).setFill()
        bounds.fill()
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        backgroundLabel.frame = NSRect(x: 18, y: 16, width: 150, height: 20)
        imagePathLabel.frame = NSRect(x: 18, y: 40, width: max(1, width - 36), height: 20)
        chooseButton.frame = NSRect(x: 18, y: 68, width: 88, height: 26)
        clearButton.frame = NSRect(x: 112, y: 68, width: 88, height: 26)
        opacityLabel.frame = NSRect(x: 18, y: 112, width: 86, height: 20)
        opacitySlider.frame = NSRect(x: 112, y: 112, width: max(120, width - 174), height: 20)
        opacityValueLabel.frame = NSRect(x: width - 54, y: 112, width: 42, height: 20)
        autoCollapseButton.frame = NSRect(x: 18, y: 144, width: 220, height: 20)
        menuBarButton.frame = NSRect(x: 232, y: 144, width: max(1, width - 250), height: 20)
        collapseDelayLabel.frame = NSRect(x: 18, y: 178, width: 86, height: 20)
        collapseDelaySlider.frame = NSRect(x: 112, y: 178, width: max(120, width - 174), height: 20)
        collapseDelayValueLabel.frame = NSRect(x: width - 54, y: 178, width: 42, height: 20)
        languageLabel.frame = NSRect(x: 18, y: 212, width: 86, height: 20)
        languageControl.frame = NSRect(x: 112, y: 208, width: 150, height: 24)
        accentColorLabel.frame = NSRect(x: 18, y: 248, width: 86, height: 20)
        accentColorWell.frame = NSRect(x: 112, y: 244, width: 52, height: 28)
        resetAccentColorButton.frame = NSRect(x: 174, y: 245, width: 88, height: 26)
        hintLabel.frame = NSRect(x: 18, y: 286, width: max(1, width - 36), height: 20)
    }

    func updateImagePath(_ path: String?) {
        imagePathLabel.stringValue = path ?? L10n.text("未选择（当前使用纯色背景）", "Not selected (using solid background)")
    }

    func updateOpacity(_ opacity: CGFloat) {
        let value = min(max(opacity, 0), 1)
        opacitySlider.doubleValue = Double(value)
        opacityValueLabel.stringValue = "\(Int((value * 100).rounded()))%"
    }

    func updateAutoCollapse(_ enabled: Bool) {
        autoCollapseButton.state = enabled ? .on : .off
        collapseDelaySlider.isEnabled = enabled
        collapseDelayValueLabel.textColor = enabled
            ? NSColor(white: 0.78, alpha: 1)
            : NSColor(white: 0.4, alpha: 1)
    }

    func updateCollapseDelay(_ delay: TimeInterval) {
        let value = min(max(delay, 1), 10).rounded()
        collapseDelaySlider.doubleValue = value
        collapseDelayValueLabel.stringValue = L10n.text("\(Int(value)) 秒", "\(Int(value)) sec")
    }

    func updateMenuBarVisible(_ visible: Bool) {
        menuBarButton.state = visible ? .on : .off
    }

    func updateAccentColor(_ color: NSColor) {
        accentColorWell.color = color
        chooseButton.contentTintColor = color
        clearButton.contentTintColor = color
        resetAccentColorButton.contentTintColor = color
    }

    func updateLanguage(_ language: AppLanguage) {
        self.language = language
        backgroundLabel.stringValue = L10n.text("背景图片", "Background image")
        chooseButton.title = L10n.text("选择图片", "Choose image")
        clearButton.title = L10n.text("清除图片", "Clear image")
        opacityLabel.stringValue = L10n.text("图片透明度", "Image opacity")
        accentColorLabel.stringValue = L10n.text("红色文字颜色", "Accent text color")
        resetAccentColorButton.title = L10n.text("恢复默认", "Reset")
        accentColorWell.toolTip = L10n.text(
            "调整原红色文字、图表主周期和菜单栏用量颜色",
            "Change the former red text, primary chart series, and menu-bar usage color"
        )
        accentColorWell.setAccessibilityLabel(L10n.text("红色文字颜色", "Accent text color"))
        resetAccentColorButton.toolTip = L10n.text("恢复默认红色", "Restore the default red")
        resetAccentColorButton.setAccessibilityLabel(L10n.text("恢复默认红色", "Restore default red"))
        autoCollapseButton.title = L10n.text("自动缩放为极简卡片", "Auto-collapse to compact card")
        menuBarButton.title = L10n.text("菜单栏显示 CODEX", "Show CODEX in menu bar")
        collapseDelayLabel.stringValue = L10n.text("缩放等待", "Collapse delay")
        languageLabel.stringValue = L10n.text("语言", "Language")
        hintLabel.stringValue = L10n.text(
            "强调色可自定义；图片只会作为半透明背景叠加。",
            "The accent color is customizable; the image is added as a translucent background."
        )
        languageControl.selectedSegment = language.isChinese ? 0 : 1
        languageControl.setAccessibilityLabel(L10n.text("界面语言", "Interface language"))
        updateImagePath(UserDefaults.standard.string(forKey: AppearancePreference.backgroundImagePath))
        updateCollapseDelay(collapseDelaySlider.doubleValue)
        needsDisplay = true
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

    @objc private func autoCollapseChanged() {
        onAutoCollapseChanged?(autoCollapseButton.state == .on)
    }

    @objc private func collapseDelayChanged() {
        onCollapseDelayChanged?(collapseDelaySlider.doubleValue.rounded())
    }

    @objc private func menuBarVisibilityChanged() {
        onMenuBarVisibilityChanged?(menuBarButton.state == .on)
    }

    @objc private func languageChanged() {
        let language = languageControl.selectedSegment == 1 ? AppLanguage.english : .chinese
        onLanguageChanged?(language)
    }

    @objc private func accentColorChanged() {
        onAccentColorChanged?(accentColorWell.color)
    }

    @objc private func resetAccentColor() {
        onAccentColorChanged?(AppearancePreference.defaultAccentColor)
    }

    private func configure(
        imagePath: String?,
        opacity: CGFloat,
        accentColor: NSColor,
        autoCollapseEnabled: Bool,
        collapseDelay: TimeInterval,
        menuBarVisible: Bool
    ) {
        wantsLayer = true
        configureLabel(backgroundLabel, size: 12, weight: .semibold, color: .white)
        configureLabel(opacityLabel, size: 11, weight: .medium, color: NSColor(white: 0.78, alpha: 1))
        configureLabel(accentColorLabel, size: 11, weight: .medium, color: NSColor(white: 0.78, alpha: 1))
        configureLabel(collapseDelayLabel, size: 11, weight: .medium, color: NSColor(white: 0.78, alpha: 1))
        configureLabel(languageLabel, size: 11, weight: .medium, color: NSColor(white: 0.78, alpha: 1))
        addSubview(backgroundLabel)
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

        addSubview(opacityLabel)
        opacitySlider.controlSize = .small
        opacitySlider.isContinuous = true
        opacitySlider.target = self
        opacitySlider.action = #selector(opacitySliderChanged)
        addSubview(opacitySlider)
        opacityValueLabel.alignment = .right
        opacityValueLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        opacityValueLabel.textColor = NSColor(white: 0.78, alpha: 1)
        addSubview(opacityValueLabel)

        autoCollapseButton.font = .systemFont(ofSize: 11, weight: .medium)
        autoCollapseButton.contentTintColor = NSColor(white: 0.82, alpha: 1)
        autoCollapseButton.target = self
        autoCollapseButton.action = #selector(autoCollapseChanged)
        addSubview(autoCollapseButton)

        menuBarButton.font = .systemFont(ofSize: 11, weight: .medium)
        menuBarButton.contentTintColor = NSColor(white: 0.82, alpha: 1)
        menuBarButton.target = self
        menuBarButton.action = #selector(menuBarVisibilityChanged)
        addSubview(menuBarButton)

        addSubview(accentColorLabel)
        accentColorWell.target = self
        accentColorWell.action = #selector(accentColorChanged)
        accentColorWell.isBordered = true
        addSubview(accentColorWell)
        configureButton(resetAccentColorButton)
        resetAccentColorButton.target = self
        resetAccentColorButton.action = #selector(resetAccentColor)
        addSubview(resetAccentColorButton)

        addSubview(collapseDelayLabel)
        collapseDelaySlider.controlSize = .small
        collapseDelaySlider.numberOfTickMarks = 10
        collapseDelaySlider.allowsTickMarkValuesOnly = true
        collapseDelaySlider.isContinuous = true
        collapseDelaySlider.target = self
        collapseDelaySlider.action = #selector(collapseDelayChanged)
        addSubview(collapseDelaySlider)
        collapseDelayValueLabel.alignment = .right
        collapseDelayValueLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        addSubview(collapseDelayValueLabel)

        addSubview(languageLabel)
        languageControl.controlSize = .small
        languageControl.segmentStyle = .rounded
        languageControl.target = self
        languageControl.action = #selector(languageChanged)
        languageControl.setAccessibilityLabel(L10n.text("界面语言", "Interface language"))
        addSubview(languageControl)

        hintLabel.font = .systemFont(ofSize: 10)
        hintLabel.textColor = NSColor(white: 0.5, alpha: 1)
        hintLabel.lineBreakMode = .byTruncatingTail
        addSubview(hintLabel)
        updateImagePath(imagePath)
        updateOpacity(opacity)
        updateAccentColor(accentColor)
        updateAutoCollapse(autoCollapseEnabled)
        updateCollapseDelay(collapseDelay)
        updateMenuBarVisible(menuBarVisible)
        updateLanguage(language)
    }

    private func configureButton(_ button: NSButton) {
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.contentTintColor = accentColor
        button.font = .systemFont(ofSize: 11, weight: .medium)
    }

    private func configureLabel(_ label: NSTextField, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
    }

    private var accentColor: NSColor {
        AccentColorPreference.current
    }
}
