import AppKit

private enum SettingsLayout {
    static let popoverWidth: CGFloat = PopoverLayout.width
    static let popoverHeight: CGFloat = PopoverLayout.height
    static let horizontalInset: CGFloat = PopoverLayout.horizontalInset
    static let topInset: CGFloat = PopoverLayout.topInset
    static let bottomInset: CGFloat = PopoverLayout.bottomInset
    static let headerSpacing: CGFloat = 8
    static let sectionSpacing: CGFloat = 16
    static let rowHorizontalInset: CGFloat = 12
    static let rowVerticalInset: CGFloat = 8
    static let rowNoteSpacing: CGFloat = 4
    static let rowSeparatorHeight: CGFloat = 1
    static let rowSeparatorColor = NSColor.separatorColor.withAlphaComponent(0.4)
    static let rowHighlightColor = NSColor.controlAccentColor.withAlphaComponent(0.12)
    static let groupCornerRadius: CGFloat = 12
    static let groupBorderWidth: CGFloat = 1
    static let groupBorderColor = NSColor.separatorColor.withAlphaComponent(0.4)
    static let groupBackgroundColor = NSColor.controlBackgroundColor
    static let sliderWidth: CGFloat = 88
    static let sliderValueSpacing: CGFloat = 8
    static let sliderTickCount = 11
    static let topicIconSize: CGFloat = 14
    static let topicIconSpacing: CGFloat = 8
    static let detailIconSize: CGFloat = 22
    static let detailIconContainer: CGFloat = 44
    static let detailHeaderSpacing: CGFloat = 6
}

private enum SettingsTopicID: String {
    case alerts
    case privacy
    case developer
}

private struct SettingsTopic: Equatable {
    let id: SettingsTopicID
    let title: String
    let subtitle: String
    let iconName: String
}

private enum SettingsPage {
    case topics
    case detail(SettingsTopic)
}

private final class SettingsGroupView: NSView {
    override var wantsUpdateLayer: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func updateLayer() {
        guard let layer else {
            return
        }
        layer.cornerRadius = SettingsLayout.groupCornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        layer.borderWidth = SettingsLayout.groupBorderWidth
        layer.borderColor = SettingsLayout.groupBorderColor.cgColor
        layer.backgroundColor = SettingsLayout.groupBackgroundColor.cgColor
    }
}

private final class SettingsRowView: NSView {
    private let separator = NSView()
    private let highlightView = NSView()
    var onClick: (() -> Void)?
    var topic: SettingsTopic?
    private var isInteractive = false
    private var trackingAreaRef: NSTrackingArea?
    private var isHovering = false

    init(
        leading: NSView,
        trailing: NSView? = nil,
        note: NSTextField? = nil,
        isInteractive: Bool = false,
        onClick: (() -> Void)? = nil
    ) {
        self.onClick = onClick
        self.isInteractive = isInteractive
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        highlightView.translatesAutoresizingMaskIntoConstraints = false
        highlightView.wantsLayer = true
        highlightView.layer?.backgroundColor = SettingsLayout.rowHighlightColor.cgColor
        highlightView.isHidden = true
        addSubview(highlightView)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        var rowViews: [NSView] = [leading, spacer]
        if let trailing {
            rowViews.append(trailing)
        }

        let rowStack = NSStackView(views: rowViews)
        rowStack.orientation = .horizontal
        rowStack.alignment = .centerY
        rowStack.distribution = .fill
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowStack)

        leading.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        leading.setContentHuggingPriority(.defaultLow, for: .horizontal)
        trailing?.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        trailing?.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        var constraints: [NSLayoutConstraint] = [
            highlightView.leadingAnchor.constraint(equalTo: leadingAnchor),
            highlightView.trailingAnchor.constraint(equalTo: trailingAnchor),
            highlightView.topAnchor.constraint(equalTo: topAnchor),
            highlightView.bottomAnchor.constraint(equalTo: bottomAnchor),
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SettingsLayout.rowHorizontalInset),
            rowStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -SettingsLayout.rowHorizontalInset),
            rowStack.topAnchor.constraint(equalTo: topAnchor, constant: SettingsLayout.rowVerticalInset)
        ]

        if let note {
            note.translatesAutoresizingMaskIntoConstraints = false
            addSubview(note)
            constraints.append(contentsOf: [
                note.leadingAnchor.constraint(equalTo: rowStack.leadingAnchor),
                note.trailingAnchor.constraint(equalTo: rowStack.trailingAnchor),
                note.topAnchor.constraint(equalTo: rowStack.bottomAnchor, constant: SettingsLayout.rowNoteSpacing),
                note.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -SettingsLayout.rowVerticalInset)
            ])
        } else {
            constraints.append(rowStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -SettingsLayout.rowVerticalInset))
        }

        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.wantsLayer = true
        separator.layer?.backgroundColor = SettingsLayout.rowSeparatorColor.cgColor
        addSubview(separator)

        constraints.append(contentsOf: [
            separator.heightAnchor.constraint(equalToConstant: SettingsLayout.rowSeparatorHeight),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SettingsLayout.rowHorizontalInset),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -SettingsLayout.rowHorizontalInset),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        NSLayoutConstraint.activate(constraints)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func setShowsSeparator(_ show: Bool) {
        separator.isHidden = !show
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
            self.trackingAreaRef = nil
        }
        guard isInteractive else {
            return
        }
        let options: NSTrackingArea.Options = [.activeInKeyWindow, .mouseEnteredAndExited, .inVisibleRect]
        let tracking = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(tracking)
        trackingAreaRef = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        setHovering(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        setHovering(false)
    }

    override func mouseDown(with event: NSEvent) {
        guard isInteractive else {
            super.mouseDown(with: event)
            return
        }
        onClick?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        guard isInteractive else {
            return hit
        }
        if hit is NSControl {
            return hit
        }
        return self
    }

    private func setHovering(_ hovering: Bool) {
        guard isInteractive else {
            return
        }
        if isHovering == hovering {
            return
        }
        isHovering = hovering
        highlightView.isHidden = !hovering
    }
}

final class SettingsPopoverController: NSViewController {
    var onBack: (() -> Void)?
    var onTestNotification: (() -> Void)?

    private let headerTitle = NSTextField(labelWithString: "Settings")
    private let backButton = NSButton(title: "Back", target: nil, action: nil)
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)
    private let headerRow = NSStackView()
    private let contentContainer = NSView()

    private let idleThresholdLabel = NSTextField(labelWithString: "Idle alert threshold")
    private let idleThresholdValue = NSTextField(labelWithString: "—")
    private let idleThresholdSlider = NSSlider(
        value: Settings.idleAlertDefaultThreshold,
        minValue: Settings.percentMin,
        maxValue: Settings.percentMax,
        target: nil,
        action: nil
    )
    private let idleSoundLabel = NSTextField(labelWithString: "Play idle alert sound")
    private let idleSoundSwitch = NSSwitch()
    private let idleSoundNote = NSTextField(labelWithString: "Only used when notifications are silent.")
    private let notificationLabel = NSTextField(labelWithString: "Show notifications")
    private let notificationSwitch = NSSwitch()

    private let telemetryLabel = NSTextField(labelWithString: "Enable telemetry")
    private let telemetrySwitch = NSSwitch()

    private let spinnerLabel = NSTextField(labelWithString: "Force spinner")
    private let spinnerSwitch = NSSwitch()
    private let queueColorOverrideLabel = NSTextField(labelWithString: "Override queue color")
    private let queueColorOverrideSwitch = NSSwitch()
    private let queueColorLabel = NSTextField(labelWithString: "Queue icon color")
    private let queueColorValue = NSTextField(labelWithString: "—")
    private let queueColorSlider = NSSlider(
        value: Settings.percentMin,
        minValue: Settings.percentMin,
        maxValue: Settings.percentMax,
        target: nil,
        action: nil
    )
    private let testNotificationLabel = NSTextField(labelWithString: "Test notification")
    private let testNotificationButton = NSButton(title: "Send", target: nil, action: nil)
    private let simulateAgentsLabel = NSTextField(labelWithString: "Simulate agents")
    private let simulateAgentsButton = NSButton(title: "Start", target: nil, action: nil)

    private let topicsStack = NSStackView()
    private let detailStack = NSStackView()
    private let detailHeaderContainer = NSView()
    private let detailHeaderStack = NSStackView()
    private let detailIconContainer = NSView()
    private let detailIconView = NSImageView()
    private let detailTitleLabel = NSTextField(labelWithString: "")
    private let detailSubtitleLabel = NSTextField(labelWithString: "")

    private var currentPage: SettingsPage = .topics
    private var currentContentView: NSView?
    private var contentConstraints: [NSLayoutConstraint] = []
    private var topicsList: [SettingsTopic] = []
    private var detailGroupView: NSView?
    private var detailGroupWidthConstraint: NSLayoutConstraint?
    private var topicsGroupWidthConstraint: NSLayoutConstraint?
    private var topicRows: [SettingsRowView] = []

    private var alertsGroup: NSView?
    private var privacyGroup: NSView?
    private var devGroup: NSView?

    private var devObserver: NSObjectProtocol?
    private var lastIdleThresholdReported: Int?
    private var lastQueueColorReported: Int?

    override func loadView() {
        view = CursorRectsView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: SettingsLayout.popoverWidth,
                height: SettingsLayout.popoverHeight
            )
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupContent()
        showTopics()
        syncFromSettings()
        updateCursorTargets()

        devObserver = NotificationCenter.default.addObserver(
            forName: .settingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncFromSettings()
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateCursorTargets()
    }

    deinit {
        if let devObserver {
            NotificationCenter.default.removeObserver(devObserver)
        }
    }

    private var topics: [SettingsTopic] {
        var items = [
            SettingsTopic(
                id: .alerts,
                title: "Alerts",
                subtitle: "Control idle alerts, sounds, and notifications.",
                iconName: "bell.badge"
            ),
            SettingsTopic(
                id: .privacy,
                title: "Privacy",
                subtitle: "Manage telemetry and data sharing for AgentBuffer.",
                iconName: "hand.raised"
            )
        ]
        if Settings.devModeEnabled {
            items.append(
                SettingsTopic(
                    id: .developer,
                    title: "Developer",
                    subtitle: "Debug tools for testing and simulation.",
                    iconName: "hammer"
                )
            )
        }
        return items
    }

    private func setupContent() {
        backButton.bezelStyle = .inline
        backButton.controlSize = .small
        backButton.target = self
        backButton.action = #selector(backTapped)

        doneButton.bezelStyle = .inline
        doneButton.controlSize = .small
        doneButton.target = self
        doneButton.action = #selector(doneTapped)
        doneButton.isHidden = true

        headerTitle.font = .systemFont(ofSize: NSFont.systemFontSize + 2, weight: .semibold)
        headerTitle.textColor = .labelColor
        headerTitle.alignment = .center

        let leftSpacer = NSView()
        let rightSpacer = NSView()
        leftSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        rightSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = SettingsLayout.headerSpacing
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addArrangedSubview(backButton)
        headerRow.addArrangedSubview(leftSpacer)
        headerRow.addArrangedSubview(headerTitle)
        headerRow.addArrangedSubview(rightSpacer)
        headerRow.addArrangedSubview(doneButton)

        styleRowLabel(idleThresholdLabel)
        styleRowLabel(idleSoundLabel)
        styleRowLabel(notificationLabel)
        styleRowLabel(telemetryLabel)
        styleRowLabel(spinnerLabel)
        styleRowLabel(queueColorOverrideLabel)
        styleRowLabel(queueColorLabel)
        styleRowLabel(testNotificationLabel)
        styleRowLabel(simulateAgentsLabel)

        styleValueLabel(idleThresholdValue)
        styleValueLabel(queueColorValue)

        idleSoundNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        idleSoundNote.textColor = .tertiaryLabelColor
        idleSoundNote.lineBreakMode = .byWordWrapping
        idleSoundNote.maximumNumberOfLines = 2

        styleSwitch(idleSoundSwitch)
        styleSwitch(notificationSwitch)
        styleSwitch(telemetrySwitch)
        styleSwitch(spinnerSwitch)
        styleSwitch(queueColorOverrideSwitch)

        idleThresholdSlider.target = self
        idleThresholdSlider.action = #selector(idleThresholdChanged)
        idleThresholdSlider.numberOfTickMarks = SettingsLayout.sliderTickCount
        idleThresholdSlider.allowsTickMarkValuesOnly = false
        idleThresholdSlider.controlSize = .small

        notificationSwitch.target = self
        notificationSwitch.action = #selector(notificationToggled)
        idleSoundSwitch.target = self
        idleSoundSwitch.action = #selector(idleSoundToggled)

        telemetrySwitch.target = self
        telemetrySwitch.action = #selector(telemetryToggled)

        spinnerSwitch.target = self
        spinnerSwitch.action = #selector(devSpinnerToggled)

        queueColorSlider.target = self
        queueColorSlider.action = #selector(devQueueColorChanged)
        queueColorSlider.numberOfTickMarks = SettingsLayout.sliderTickCount
        queueColorSlider.allowsTickMarkValuesOnly = false
        queueColorSlider.controlSize = .small

        queueColorOverrideSwitch.target = self
        queueColorOverrideSwitch.action = #selector(devQueueOverrideToggled)

        testNotificationButton.target = self
        testNotificationButton.action = #selector(testNotificationTapped)
        testNotificationButton.bezelStyle = .rounded
        testNotificationButton.controlSize = .small

        simulateAgentsButton.target = self
        simulateAgentsButton.action = #selector(simulateAgentsTapped)
        simulateAgentsButton.bezelStyle = .rounded
        simulateAgentsButton.controlSize = .small
        simulateAgentsButton.setButtonType(.pushOnPushOff)

        let idleThresholdTrailing = makeSliderTrailing(slider: idleThresholdSlider, value: idleThresholdValue)
        alertsGroup = makeGroup(rows: [
            SettingsRowView(leading: idleThresholdLabel, trailing: idleThresholdTrailing),
            SettingsRowView(leading: idleSoundLabel, trailing: idleSoundSwitch, note: idleSoundNote),
            SettingsRowView(leading: notificationLabel, trailing: notificationSwitch)
        ])

        privacyGroup = makeGroup(rows: [
            SettingsRowView(leading: telemetryLabel, trailing: telemetrySwitch)
        ])

        if Settings.devModeEnabled {
            let queueColorTrailing = makeSliderTrailing(slider: queueColorSlider, value: queueColorValue)
            devGroup = makeGroup(rows: [
                SettingsRowView(leading: spinnerLabel, trailing: spinnerSwitch),
                SettingsRowView(leading: queueColorOverrideLabel, trailing: queueColorOverrideSwitch),
                SettingsRowView(leading: queueColorLabel, trailing: queueColorTrailing),
                SettingsRowView(leading: testNotificationLabel, trailing: testNotificationButton),
                SettingsRowView(leading: simulateAgentsLabel, trailing: simulateAgentsButton)
            ])
        }

        buildTopicsList()
        setupDetailHeader()
        configureDetailStack()

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerRow)
        view.addSubview(contentContainer)

        NSLayoutConstraint.activate([
            headerRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SettingsLayout.horizontalInset),
            headerRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SettingsLayout.horizontalInset),
            headerRow.topAnchor.constraint(equalTo: view.topAnchor, constant: SettingsLayout.topInset),
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SettingsLayout.horizontalInset),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SettingsLayout.horizontalInset),
            contentContainer.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: SettingsLayout.sectionSpacing),
            contentContainer.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -SettingsLayout.bottomInset)
        ])
    }

    private func buildTopicsList() {
        topicsList = topics
        topicRows = topicsList.map { topic in
            let row = makeTopicRow(for: topic)
            row.topic = topic
            row.onClick = { [weak self, weak row] in
                guard let self, let topic = row?.topic else { return }
                self.showDetail(for: topic)
            }
            return row
        }

        let topicsGroup = makeGroup(rows: topicRows)
        topicsGroup.translatesAutoresizingMaskIntoConstraints = false

        topicsStack.orientation = .vertical
        topicsStack.spacing = SettingsLayout.sectionSpacing
        topicsStack.alignment = .leading
        topicsStack.translatesAutoresizingMaskIntoConstraints = false
        topicsStack.addArrangedSubview(topicsGroup)

        topicsGroupWidthConstraint = topicsGroup.widthAnchor.constraint(equalTo: topicsStack.widthAnchor)
        topicsGroupWidthConstraint?.isActive = true
    }

    private func setupDetailHeader() {
        detailIconContainer.translatesAutoresizingMaskIntoConstraints = false
        detailIconContainer.wantsLayer = true
        detailIconContainer.layer?.cornerRadius = SettingsLayout.detailIconContainer / 2
        detailIconContainer.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.8).cgColor

        detailIconView.translatesAutoresizingMaskIntoConstraints = false
        detailIconView.imageScaling = .scaleProportionallyUpOrDown
        detailIconView.contentTintColor = .labelColor
        detailIconContainer.addSubview(detailIconView)

        NSLayoutConstraint.activate([
            detailIconContainer.widthAnchor.constraint(equalToConstant: SettingsLayout.detailIconContainer),
            detailIconContainer.heightAnchor.constraint(equalToConstant: SettingsLayout.detailIconContainer),
            detailIconView.centerXAnchor.constraint(equalTo: detailIconContainer.centerXAnchor),
            detailIconView.centerYAnchor.constraint(equalTo: detailIconContainer.centerYAnchor),
            detailIconView.widthAnchor.constraint(equalToConstant: SettingsLayout.detailIconSize),
            detailIconView.heightAnchor.constraint(equalToConstant: SettingsLayout.detailIconSize)
        ])

        detailTitleLabel.font = .systemFont(ofSize: NSFont.systemFontSize + 3, weight: .semibold)
        detailTitleLabel.textColor = .labelColor
        detailTitleLabel.alignment = .center

        detailSubtitleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detailSubtitleLabel.textColor = .secondaryLabelColor
        detailSubtitleLabel.alignment = .center
        detailSubtitleLabel.lineBreakMode = .byWordWrapping
        detailSubtitleLabel.maximumNumberOfLines = 2

        detailHeaderStack.orientation = .vertical
        detailHeaderStack.alignment = .centerX
        detailHeaderStack.spacing = SettingsLayout.detailHeaderSpacing
        detailHeaderStack.translatesAutoresizingMaskIntoConstraints = false
        detailHeaderStack.addArrangedSubview(detailIconContainer)
        detailHeaderStack.addArrangedSubview(detailTitleLabel)
        detailHeaderStack.addArrangedSubview(detailSubtitleLabel)

        detailHeaderContainer.translatesAutoresizingMaskIntoConstraints = false
        detailHeaderContainer.addSubview(detailHeaderStack)

        NSLayoutConstraint.activate([
            detailHeaderStack.centerXAnchor.constraint(equalTo: detailHeaderContainer.centerXAnchor),
            detailHeaderStack.topAnchor.constraint(equalTo: detailHeaderContainer.topAnchor),
            detailHeaderStack.bottomAnchor.constraint(equalTo: detailHeaderContainer.bottomAnchor),
            detailHeaderStack.leadingAnchor.constraint(greaterThanOrEqualTo: detailHeaderContainer.leadingAnchor),
            detailHeaderStack.trailingAnchor.constraint(lessThanOrEqualTo: detailHeaderContainer.trailingAnchor)
        ])
    }

    private func configureDetailStack() {
        detailStack.orientation = .vertical
        detailStack.spacing = SettingsLayout.sectionSpacing
        detailStack.alignment = .leading
        detailStack.translatesAutoresizingMaskIntoConstraints = false
        detailStack.addArrangedSubview(detailHeaderContainer)

        let headerWidth = detailHeaderContainer.widthAnchor.constraint(equalTo: detailStack.widthAnchor)
        headerWidth.isActive = true
    }

    private func showContent(_ content: NSView) {
        if let currentContentView {
            currentContentView.removeFromSuperview()
        }
        if !contentConstraints.isEmpty {
            NSLayoutConstraint.deactivate(contentConstraints)
            contentConstraints.removeAll()
        }
        currentContentView = content
        content.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(content)

        contentConstraints = [
            content.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            content.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            content.bottomAnchor.constraint(lessThanOrEqualTo: contentContainer.bottomAnchor)
        ]
        NSLayoutConstraint.activate(contentConstraints)
    }

    private func showTopics() {
        currentPage = .topics
        headerTitle.stringValue = "Settings"
        backButton.title = "Back"
        doneButton.isHidden = true
        showContent(topicsStack)
        updateCursorTargets()
    }

    private func showDetail(for topic: SettingsTopic) {
        currentPage = .detail(topic)
        headerTitle.stringValue = topic.title
        backButton.title = "Settings"
        doneButton.isHidden = false
        Telemetry.trackUi("ui.settings_topic_opened", properties: [
            "topic": topic.id.rawValue
        ])
        updateDetailHeader(for: topic)
        showContent(detailStack)
        updateCursorTargets()
    }

    private func updateDetailHeader(for topic: SettingsTopic) {
        detailTitleLabel.stringValue = topic.title
        detailSubtitleLabel.stringValue = topic.subtitle
        if let image = NSImage(systemSymbolName: topic.iconName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: SettingsLayout.detailIconSize, weight: .medium)
            detailIconView.image = image.withSymbolConfiguration(config)
        } else {
            detailIconView.image = nil
        }

        if let detailGroupView {
            detailStack.removeArrangedSubview(detailGroupView)
            detailGroupView.removeFromSuperview()
        }

        let group: NSView?
        switch topic.id {
        case .alerts:
            group = alertsGroup
        case .privacy:
            group = privacyGroup
        case .developer:
            group = devGroup
        }

        if let group {
            detailStack.addArrangedSubview(group)
            group.translatesAutoresizingMaskIntoConstraints = false
            detailGroupWidthConstraint?.isActive = false
            detailGroupWidthConstraint = group.widthAnchor.constraint(equalTo: detailStack.widthAnchor)
            detailGroupWidthConstraint?.isActive = true
            detailGroupView = group
        }
    }

    private func makeGroup(rows: [SettingsRowView]) -> NSView {
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        let group = SettingsGroupView()
        group.translatesAutoresizingMaskIntoConstraints = false
        group.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: group.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: group.trailingAnchor),
            stack.topAnchor.constraint(equalTo: group.topAnchor),
            stack.bottomAnchor.constraint(equalTo: group.bottomAnchor)
        ])

        for (index, row) in rows.enumerated() {
            row.setShowsSeparator(index < rows.count - 1)
        }

        return group
    }

    private func makeSliderTrailing(slider: NSSlider, value: NSTextField) -> NSView {
        slider.translatesAutoresizingMaskIntoConstraints = false
        value.alignment = .right
        NSLayoutConstraint.activate([
            slider.widthAnchor.constraint(greaterThanOrEqualToConstant: SettingsLayout.sliderWidth)
        ])

        let stack = NSStackView(views: [slider, value])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = SettingsLayout.sliderValueSpacing
        return stack
    }

    private func makeTopicRow(for topic: SettingsTopic) -> SettingsRowView {
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let image = NSImage(systemSymbolName: topic.iconName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: SettingsLayout.topicIconSize, weight: .medium)
            iconView.image = image.withSymbolConfiguration(config)
        }
        iconView.contentTintColor = .secondaryLabelColor
        iconView.setContentHuggingPriority(.required, for: .horizontal)

        let label = NSTextField(labelWithString: topic.title)
        styleTopicLabel(label)

        let leadingStack = NSStackView(views: [iconView, label])
        leadingStack.orientation = .horizontal
        leadingStack.alignment = .centerY
        leadingStack.spacing = SettingsLayout.topicIconSpacing

        let chevron = NSImageView()
        if let image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
            chevron.image = image.withSymbolConfiguration(config)
        }
        chevron.contentTintColor = .tertiaryLabelColor

        return SettingsRowView(
            leading: leadingStack,
            trailing: chevron,
            isInteractive: true
        )
    }

    private func styleRowLabel(_ label: NSTextField) {
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    private func styleTopicLabel(_ label: NSTextField) {
        label.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }

    private func styleValueLabel(_ label: NSTextField) {
        label.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        label.textColor = .secondaryLabelColor
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func styleSwitch(_ control: NSSwitch) {
        control.controlSize = .small
    }

    private func syncFromSettings() {
        let idlePercent = Settings.idleAlertThresholdPercent
        idleThresholdSlider.doubleValue = idlePercent
        idleThresholdValue.stringValue = percentString(idlePercent)
        lastIdleThresholdReported = Int(round(idlePercent))
        idleSoundSwitch.state = Settings.idleAlertSoundEnabled ? .on : .off
        notificationSwitch.state = Settings.idleAlertNotificationEnabled ? .on : .off
        telemetrySwitch.state = Settings.telemetryEnabled ? .on : .off

        spinnerSwitch.state = Settings.devForceSpinner ? .on : .off
        queueColorOverrideSwitch.state = Settings.devQueueIconOverrideEnabled ? .on : .off
        let percent = Settings.devQueueIconPercent ?? 0
        queueColorSlider.doubleValue = percent
        queueColorValue.stringValue = percentString(percent)
        lastQueueColorReported = Int(round(percent))
        queueColorLabel.textColor = Settings.devQueueIconOverrideEnabled ? .labelColor : .tertiaryLabelColor
        queueColorValue.textColor = Settings.devQueueIconOverrideEnabled ? .secondaryLabelColor : .tertiaryLabelColor
        queueColorSlider.isEnabled = Settings.devQueueIconOverrideEnabled
        simulateAgentsButton.state = Settings.devSimulateAgents ? .on : .off
        simulateAgentsButton.title = Settings.devSimulateAgents ? "Stop" : "Start"
    }

    @objc private func devSpinnerToggled() {
        let enabled = spinnerSwitch.state == .on
        Settings.devForceSpinner = enabled
        Telemetry.trackSettingToggle("dev_force_spinner", enabled: enabled)
    }

    @objc private func idleThresholdChanged() {
        let percent = Settings.clampPercent(idleThresholdSlider.doubleValue)
        Settings.idleAlertThresholdPercent = percent
        idleThresholdValue.stringValue = percentString(percent)
        let rounded = Int(round(percent))
        if lastIdleThresholdReported != rounded {
            lastIdleThresholdReported = rounded
            Telemetry.trackSettingValue("idle_alert_threshold_percent", value: Double(rounded))
        }
    }

    @objc private func devQueueColorChanged() {
        let percent = Settings.clampPercent(queueColorSlider.doubleValue)
        Settings.devQueueIconPercent = percent
        queueColorValue.stringValue = percentString(percent)
        let rounded = Int(round(percent))
        if lastQueueColorReported != rounded {
            lastQueueColorReported = rounded
            Telemetry.trackSettingValue("dev_queue_icon_percent", value: Double(rounded))
        }
    }

    @objc private func idleSoundToggled() {
        let enabled = idleSoundSwitch.state == .on
        Settings.idleAlertSoundEnabled = enabled
        Telemetry.trackSettingToggle("idle_alert_sound", enabled: enabled)
    }

    @objc private func notificationToggled() {
        let enabled = notificationSwitch.state == .on
        Settings.idleAlertNotificationEnabled = enabled
        Telemetry.trackSettingToggle("idle_alert_notifications", enabled: enabled)
    }

    @objc private func telemetryToggled() {
        let enabled = telemetrySwitch.state == .on
        Settings.telemetryEnabled = enabled
        Telemetry.trackOptChange(enabled: enabled)
    }

    @objc private func devQueueOverrideToggled() {
        let enabled = queueColorOverrideSwitch.state == .on
        Settings.devQueueIconOverrideEnabled = enabled
        Telemetry.trackSettingToggle("dev_queue_icon_override", enabled: enabled)
        syncFromSettings()
    }

    @objc private func simulateAgentsTapped() {
        let enabled = simulateAgentsButton.state == .on
        Settings.devSimulateAgents = enabled
        Telemetry.trackSettingToggle("dev_simulate_agents", enabled: enabled)
        syncFromSettings()
    }

    @objc private func backTapped() {
        Telemetry.trackUi("ui.settings_back_clicked", properties: [
            "page": currentPage == .topics ? "topics" : "detail"
        ])
        switch currentPage {
        case .topics:
            onBack?()
        case .detail:
            showTopics()
        }
    }

    @objc private func doneTapped() {
        Telemetry.trackUi("ui.settings_done_clicked")
        onBack?()
    }

    @objc private func testNotificationTapped() {
        Telemetry.trackUi("ui.test_notification_clicked")
        onTestNotification?()
    }

    private func percentString(_ value: Double) -> String {
        "\(Int(round(value)))%"
    }

    private func updateCursorTargets() {
        var targets: [NSView] = [backButton]
        if !doneButton.isHidden {
            targets.append(doneButton)
        }

        switch currentPage {
        case .topics:
            targets.append(contentsOf: topicRows)
        case .detail(let topic):
            switch topic.id {
            case .alerts:
                targets.append(contentsOf: [idleSoundSwitch, notificationSwitch])
            case .privacy:
                targets.append(telemetrySwitch)
            case .developer:
                targets.append(contentsOf: [
                    spinnerSwitch,
                    queueColorOverrideSwitch,
                    testNotificationButton,
                    simulateAgentsButton
                ])
            }
        }

        guard let contentView = view as? CursorRectsView else {
            return
        }
        contentView.cursorTargets = targets
        contentView.window?.invalidateCursorRects(for: contentView)
    }
}
