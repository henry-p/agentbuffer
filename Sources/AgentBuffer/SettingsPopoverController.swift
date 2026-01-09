import AppKit
import UserNotifications

private enum SettingsLayout {
    static let popoverWidth: CGFloat = PopoverLayout.width
    static let popoverHeight: CGFloat = PopoverLayout.height
    static let horizontalInset: CGFloat = PopoverLayout.horizontalInset
    static let topInset: CGFloat = PopoverLayout.topInset
    static let bottomInset: CGFloat = PopoverLayout.bottomInset
    static let headerSpacing: CGFloat = 8
    static let sectionSpacing: CGFloat = 16
    static let accordionSpacing: CGFloat = 8
    static let rowHorizontalInset: CGFloat = 12
    static let rowVerticalInset: CGFloat = 8
    static let rowNoteSpacing: CGFloat = 4
    static let rowSeparatorHeight: CGFloat = 1
    static let rowSeparatorColor = NSColor.separatorColor.withAlphaComponent(0.25)
    static let groupCornerRadius: CGFloat = 12
    static let groupBorderWidth: CGFloat = 1
    static let groupBorderColor = NSColor.separatorColor.withAlphaComponent(0.25)
    static let groupBackgroundColor = NSColor.clear
    static let accordionCornerRadius: CGFloat = 12
    static let accordionBorderWidth: CGFloat = 1
    static let accordionBorderColor = NSColor.separatorColor.withAlphaComponent(0.25)
    static let accordionHoverBorderColor = NSColor.controlAccentColor.withAlphaComponent(0.8)
    static let accordionBackgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.35)
    static let accordionAnimationDuration: TimeInterval = 0.18
    static let sliderWidth: CGFloat = 88
    static let sliderValueSpacing: CGFloat = 8
    static let sliderValueWidth: CGFloat = 40
    static let sliderTickCount = 11
    static let idleThresholdTickCount = 5
    static let accordionChevronSize: CGFloat = 12
}

private enum SettingsSectionID: String {
    case alerts
    case privacy
    case developer
}

private enum SystemSoundAvailability {
    case available
    case notificationsDisabled
    case systemNotificationsDisabled
    case systemSoundDisabled
    case systemSoundUnsupported
    case bundleRequired
}

private final class SettingsGroupView: NSView {
    var showsBorder = false {
        didSet {
            needsDisplay = true
        }
    }
    var fillColor: NSColor = SettingsLayout.groupBackgroundColor {
        didSet {
            needsDisplay = true
        }
    }

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
        if showsBorder {
            layer.borderWidth = SettingsLayout.groupBorderWidth
            layer.borderColor = SettingsLayout.groupBorderColor.cgColor
        } else {
            layer.borderWidth = 0
            layer.borderColor = nil
        }
        layer.backgroundColor = fillColor.cgColor
    }
}

private final class HoverTrackingView: NSView {
    var onHoverChanged: ((Bool) -> Void)?
    private var trackingAreaRef: NSTrackingArea?
    private var isHovering = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
        let tracking = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(tracking)
        trackingAreaRef = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        guard !isHovering else { return }
        isHovering = true
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        guard isHovering else { return }
        isHovering = false
        onHoverChanged?(false)
    }
}

private final class SettingsRowView: NSView {
    private let separator = NSView()
    var onClick: (() -> Void)?
    private var isInteractive = false
    private var note: NSTextField?
    private var rowStackBottomConstraint: NSLayoutConstraint?
    private var noteConstraints: [NSLayoutConstraint] = []

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
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: SettingsLayout.rowHorizontalInset),
            rowStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -SettingsLayout.rowHorizontalInset),
            rowStack.topAnchor.constraint(equalTo: topAnchor, constant: SettingsLayout.rowVerticalInset)
        ]
        rowStackBottomConstraint = rowStack.bottomAnchor.constraint(
            equalTo: bottomAnchor,
            constant: -SettingsLayout.rowVerticalInset
        )

        if let note {
            self.note = note
            note.translatesAutoresizingMaskIntoConstraints = false
            addSubview(note)
            noteConstraints = [
                note.leadingAnchor.constraint(equalTo: rowStack.leadingAnchor),
                note.trailingAnchor.constraint(equalTo: rowStack.trailingAnchor),
                note.topAnchor.constraint(equalTo: rowStack.bottomAnchor, constant: SettingsLayout.rowNoteSpacing),
                note.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -SettingsLayout.rowVerticalInset)
            ]
            NSLayoutConstraint.activate(noteConstraints)
        } else if let rowStackBottomConstraint {
            constraints.append(rowStackBottomConstraint)
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

    func setNoteHidden(_ hidden: Bool) {
        guard let note else {
            return
        }
        note.isHidden = hidden
        if hidden {
            NSLayoutConstraint.deactivate(noteConstraints)
            rowStackBottomConstraint?.isActive = true
        } else {
            rowStackBottomConstraint?.isActive = false
            NSLayoutConstraint.activate(noteConstraints)
        }
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
        guard hit != nil else {
            return nil
        }
        if hit is NSSwitch || hit is NSButton || hit is NSSlider {
            return hit
        }
        return self
    }
}

private final class SoundModeControl: NSSegmentedControl {
    var onDisabledSegmentClick: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let count = max(segmentCount, 1)
        let segmentWidth = bounds.width / CGFloat(count)
        let index = Int(floor(point.x / max(segmentWidth, 1)))
        let segment = (index >= 0 && index < segmentCount) ? index : -1
        if segment >= 0, !isEnabled(forSegment: segment) {
            onDisabledSegmentClick?(segment)
            return
        }
        super.mouseDown(with: event)
    }
}

private final class SettingsAccordionSection {
    let id: SettingsSectionID
    let headerRow: SettingsRowView
    let contentView: NSView
    let containerView = HoverTrackingView()
    var onToggle: (() -> Void)?
    private let stackView = NSStackView()
    private let contentWrapper = NSView()
    private let chevronView = NSImageView()
    private var contentHeightConstraint: NSLayoutConstraint?
    private(set) var isExpanded: Bool
    private var isHovering = false

    init(
        id: SettingsSectionID,
        title: String,
        contentView: NSView,
        isExpanded: Bool
    ) {
        self.id = id
        self.contentView = contentView
        self.isExpanded = isExpanded

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        chevronView.translatesAutoresizingMaskIntoConstraints = false
        chevronView.contentTintColor = .tertiaryLabelColor
        chevronView.setContentHuggingPriority(.required, for: .horizontal)
        if let image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: SettingsLayout.accordionChevronSize, weight: .semibold)
            chevronView.image = image.withSymbolConfiguration(config)
        }

        headerRow = SettingsRowView(
            leading: titleLabel,
            trailing: chevronView,
            isInteractive: true,
            onClick: nil
        )
        headerRow.onClick = { [weak self] in
            self?.toggle()
        }
        headerRow.setShowsSeparator(false)

        containerView.wantsLayer = true
        containerView.translatesAutoresizingMaskIntoConstraints = false
        if let layer = containerView.layer {
            layer.cornerRadius = SettingsLayout.accordionCornerRadius
            layer.cornerCurve = .continuous
            layer.masksToBounds = true
            layer.borderWidth = SettingsLayout.accordionBorderWidth
            layer.borderColor = SettingsLayout.accordionBorderColor.cgColor
            layer.backgroundColor = SettingsLayout.accordionBackgroundColor.cgColor
        }
        containerView.onHoverChanged = { [weak self] hovering in
            self?.updateHoverState(hovering)
        }

        stackView.orientation = .vertical
        stackView.spacing = isExpanded ? SettingsLayout.accordionSpacing : 0
        stackView.alignment = .leading
        stackView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(stackView)

        contentWrapper.translatesAutoresizingMaskIntoConstraints = false
        contentWrapper.alphaValue = isExpanded ? 1 : 0
        contentWrapper.addSubview(contentView)
        contentView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            contentView.leadingAnchor.constraint(equalTo: contentWrapper.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: contentWrapper.trailingAnchor),
            contentView.topAnchor.constraint(equalTo: contentWrapper.topAnchor),
            contentView.bottomAnchor.constraint(equalTo: contentWrapper.bottomAnchor)
        ])
        contentHeightConstraint = contentWrapper.heightAnchor.constraint(equalToConstant: 0)
        contentHeightConstraint?.isActive = true

        stackView.addArrangedSubview(headerRow)
        stackView.addArrangedSubview(contentWrapper)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            headerRow.widthAnchor.constraint(equalTo: stackView.widthAnchor),
            contentWrapper.widthAnchor.constraint(equalTo: stackView.widthAnchor)
        ])

        updateChevron()
        updateContentHeight(animated: false)
        updateHoverBorder()
    }

    func setExpanded(_ expanded: Bool, animated: Bool = true) {
        guard isExpanded != expanded else {
            return
        }
        isExpanded = expanded
        updateChevron()
        stackView.spacing = isExpanded ? SettingsLayout.accordionSpacing : 0
        updateContentHeight(animated: animated)
        updateHoverBorder()
        onToggle?()
    }

    func refreshContentHeight() {
        guard isExpanded else {
            return
        }
        contentHeightConstraint?.constant = measuredContentHeight()
    }

    private func toggle() {
        setExpanded(!isExpanded)
    }

    private func updateChevron() {
        let name = isExpanded ? "chevron.down" : "chevron.right"
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: SettingsLayout.accordionChevronSize, weight: .semibold)
            chevronView.image = image.withSymbolConfiguration(config)
        }
    }

    private func updateHoverState(_ hovering: Bool) {
        isHovering = hovering
        updateHoverBorder()
    }

    private func updateHoverBorder() {
        guard let layer = containerView.layer else {
            return
        }
        let useHover = isHovering
        layer.borderColor = (useHover ? SettingsLayout.accordionHoverBorderColor : SettingsLayout.accordionBorderColor).cgColor
    }

    private func updateContentHeight(animated: Bool) {
        let targetHeight = isExpanded ? measuredContentHeight() : 0
        if !animated {
            contentHeightConstraint?.constant = targetHeight
            contentWrapper.alphaValue = isExpanded ? 1 : 0
            return
        }

        contentWrapper.alphaValue = isExpanded ? 0 : 1
        NSAnimationContext.runAnimationGroup { context in
            context.duration = SettingsLayout.accordionAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            contentHeightConstraint?.animator().constant = targetHeight
            contentWrapper.animator().alphaValue = isExpanded ? 1 : 0
            containerView.superview?.layoutSubtreeIfNeeded()
        }
    }

    private func measuredContentHeight() -> CGFloat {
        contentWrapper.layoutSubtreeIfNeeded()
        return max(0, contentView.fittingSize.height)
    }
}

final class SettingsPopoverController: NSViewController {
    var onBack: (() -> Void)?
    var onTestNotification: (() -> Void)?

    private let headerTitle = NSTextField(labelWithString: "Settings")
    private let backButton = PaddedButton(title: "Back", target: nil, action: nil)
    private let headerRow = NSStackView()
    private let contentContainer = NSView()
    private let sectionsStack = NSStackView()

    private let idleThresholdLabel = NSTextField(labelWithString: "Idle alert threshold")
    private let idleThresholdValue = NSTextField(labelWithString: "—")
    private let idleThresholdSlider = NSSlider(
        value: Settings.idleAlertDefaultThreshold,
        minValue: Settings.percentMin,
        maxValue: Settings.percentMax,
        target: nil,
        action: nil
    )
    private let soundLabel = NSTextField(labelWithString: "Sound")
    private let soundControl = SoundModeControl(
        labels: ["Off", "Glass", "System"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let soundNote = NSTextField(labelWithString: "")
    private let notificationLabel = NSTextField(labelWithString: "Show notifications")
    private let notificationSwitch = NSSwitch()

    private let telemetryLabel = NSTextField(labelWithString: "Enable telemetry")
    private let telemetrySwitch = NSSwitch()
    private let telemetryNote = NSTextField(labelWithString: "Data is completely anonymous.")

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
    private let testNotificationButton = PaddedButton(title: "Send", target: nil, action: nil)
    private let simulateAgentsLabel = NSTextField(labelWithString: "Simulate agents")
    private let simulateAgentsButton = PaddedButton(title: "Start", target: nil, action: nil)

    private let idleThresholdSnapPoints: [Double] = [0, 25, 50, 75, 100]
    private let idleThresholdSnapThreshold: Double = 1.0

    private var accordionSections: [SettingsAccordionSection] = []
    private var alertsSection: SettingsAccordionSection?
    private var privacySection: SettingsAccordionSection?
    private var devSection: SettingsAccordionSection?

    private var alertsGroup: NSView?
    private var privacyGroup: NSView?
    private var devGroup: NSView?
    private var soundRow: SettingsRowView?
    private var notificationRow: SettingsRowView?
    private var telemetryRow: SettingsRowView?
    private var spinnerRow: SettingsRowView?
    private var queueColorOverrideRow: SettingsRowView?

    private var devObserver: NSObjectProtocol?
    private var lastIdleThresholdReported: Int?
    private var lastQueueColorReported: Int?
    private var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    private var notificationSoundSetting: UNNotificationSetting = .notSupported
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
        applyDefaultExpansion()
        syncFromSettings()
        refreshNotificationSettings()
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
        accordionSections.forEach { $0.refreshContentHeight() }
        updateCursorTargets()
    }

    deinit {
        if let devObserver {
            NotificationCenter.default.removeObserver(devObserver)
        }
    }

    func resetAccordionState() {
        if !isViewLoaded {
            _ = view
        }
        applyDefaultExpansion()
        refreshNotificationSettings()
        updateCursorTargets()
    }

    private func setupContent() {
        backButton.applyStyle(.standard)
        backButton.target = self
        backButton.action = #selector(backTapped)
        if let chevron = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            backButton.image = chevron.withSymbolConfiguration(config)
            backButton.imagePosition = .imageLeading
            backButton.imageHugsTitle = true
        }

        headerTitle.font = .systemFont(ofSize: NSFont.systemFontSize + 2, weight: .semibold)
        headerTitle.textColor = .labelColor
        headerTitle.alignment = .left

        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = SettingsLayout.headerSpacing
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addArrangedSubview(backButton)
        headerRow.addArrangedSubview(headerSpacer)
        headerRow.addArrangedSubview(headerTitle)

        styleRowLabel(idleThresholdLabel)
        styleRowLabel(soundLabel)
        styleRowLabel(notificationLabel)
        styleRowLabel(telemetryLabel)
        styleRowLabel(spinnerLabel)
        styleRowLabel(queueColorOverrideLabel)
        styleRowLabel(queueColorLabel)
        styleRowLabel(testNotificationLabel)
        styleRowLabel(simulateAgentsLabel)

        styleValueLabel(idleThresholdValue)
        styleValueLabel(queueColorValue)

        soundControl.segmentStyle = .texturedRounded
        soundControl.segmentDistribution = .fillEqually
        soundControl.controlSize = .small
        soundControl.setContentHuggingPriority(.required, for: .horizontal)
        soundControl.setContentCompressionResistancePriority(.required, for: .horizontal)
        soundControl.onDisabledSegmentClick = { [weak self] segment in
            guard segment == 2 else {
                return
            }
            self?.showSystemSoundUnavailableNote()
        }

        soundNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        soundNote.textColor = .tertiaryLabelColor
        soundNote.lineBreakMode = .byWordWrapping
        soundNote.maximumNumberOfLines = 0
        soundNote.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        soundNote.setContentHuggingPriority(.defaultLow, for: .horizontal)

        telemetryNote.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        telemetryNote.textColor = .tertiaryLabelColor
        telemetryNote.lineBreakMode = .byWordWrapping
        telemetryNote.maximumNumberOfLines = 0
        telemetryNote.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        telemetryNote.setContentHuggingPriority(.defaultLow, for: .horizontal)

        styleSwitch(notificationSwitch)
        styleSwitch(telemetrySwitch)
        styleSwitch(spinnerSwitch)
        styleSwitch(queueColorOverrideSwitch)

        idleThresholdSlider.target = self
        idleThresholdSlider.action = #selector(idleThresholdChanged)
        idleThresholdSlider.numberOfTickMarks = SettingsLayout.idleThresholdTickCount
        idleThresholdSlider.allowsTickMarkValuesOnly = false
        idleThresholdSlider.controlSize = .small
        let idleThresholdDoubleClick = NSClickGestureRecognizer(
            target: self,
            action: #selector(idleThresholdDoubleClicked)
        )
        idleThresholdDoubleClick.numberOfClicksRequired = 2
        idleThresholdSlider.addGestureRecognizer(idleThresholdDoubleClick)

        notificationSwitch.target = self
        notificationSwitch.action = #selector(notificationToggled)
        soundControl.target = self
        soundControl.action = #selector(soundModeChanged)

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
        testNotificationButton.applyStyle(.compact)

        simulateAgentsButton.target = self
        simulateAgentsButton.action = #selector(simulateAgentsTapped)
        simulateAgentsButton.applyStyle(.compact)
        simulateAgentsButton.setButtonType(.pushOnPushOff)

        let idleThresholdTrailing = makeSliderTrailing(slider: idleThresholdSlider, value: idleThresholdValue)
        let notificationRow = makeToggleRow(leading: notificationLabel, toggle: notificationSwitch)
        let soundRow = SettingsRowView(leading: soundLabel, trailing: soundControl, note: soundNote)
        soundRow.setNoteHidden(true)
        self.notificationRow = notificationRow
        self.soundRow = soundRow

        alertsGroup = makeGroup(rows: [
            SettingsRowView(leading: idleThresholdLabel, trailing: idleThresholdTrailing),
            notificationRow,
            soundRow
        ])

        let telemetryRow = makeToggleRow(leading: telemetryLabel, toggle: telemetrySwitch, note: telemetryNote)
        self.telemetryRow = telemetryRow
        privacyGroup = makeGroup(rows: [telemetryRow])

        if Settings.devModeEnabled {
            let queueColorTrailing = makeSliderTrailing(slider: queueColorSlider, value: queueColorValue)
            let spinnerRow = makeToggleRow(leading: spinnerLabel, toggle: spinnerSwitch)
            let queueColorOverrideRow = makeToggleRow(leading: queueColorOverrideLabel, toggle: queueColorOverrideSwitch)
            self.spinnerRow = spinnerRow
            self.queueColorOverrideRow = queueColorOverrideRow
            devGroup = makeGroup(rows: [
                spinnerRow,
                queueColorOverrideRow,
                SettingsRowView(leading: queueColorLabel, trailing: queueColorTrailing),
                SettingsRowView(leading: testNotificationLabel, trailing: testNotificationButton),
                SettingsRowView(leading: simulateAgentsLabel, trailing: simulateAgentsButton)
            ])
        }

        buildAccordionSections()

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        sectionsStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerRow)
        view.addSubview(contentContainer)
        contentContainer.addSubview(sectionsStack)

        NSLayoutConstraint.activate([
            headerRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SettingsLayout.horizontalInset),
            headerRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SettingsLayout.horizontalInset),
            headerRow.topAnchor.constraint(equalTo: view.topAnchor, constant: SettingsLayout.topInset),
            contentContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: SettingsLayout.horizontalInset),
            contentContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -SettingsLayout.horizontalInset),
            contentContainer.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: SettingsLayout.sectionSpacing),
            contentContainer.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -SettingsLayout.bottomInset),
            sectionsStack.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            sectionsStack.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            sectionsStack.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            sectionsStack.bottomAnchor.constraint(lessThanOrEqualTo: contentContainer.bottomAnchor)
        ])
    }

    private func buildAccordionSections() {
        sectionsStack.orientation = .vertical
        sectionsStack.spacing = SettingsLayout.sectionSpacing
        sectionsStack.alignment = .leading

        accordionSections = []
        alertsSection = nil
        privacySection = nil
        devSection = nil

        if let alertsGroup {
            let section = SettingsAccordionSection(
                id: .alerts,
                title: "Alerts",
                contentView: alertsGroup,
                isExpanded: false
            )
            section.onToggle = { [weak self] in
                self?.updateCursorTargets()
            }
            alertsSection = section
            accordionSections.append(section)
            addSection(section)
        }

        if let privacyGroup {
            let section = SettingsAccordionSection(
                id: .privacy,
                title: "Privacy",
                contentView: privacyGroup,
                isExpanded: false
            )
            section.onToggle = { [weak self] in
                self?.updateCursorTargets()
            }
            privacySection = section
            accordionSections.append(section)
            addSection(section)
        }

        if let devGroup {
            let section = SettingsAccordionSection(
                id: .developer,
                title: "Developer",
                contentView: devGroup,
                isExpanded: false
            )
            section.onToggle = { [weak self] in
                self?.updateCursorTargets()
            }
            devSection = section
            accordionSections.append(section)
            addSection(section)
        }
    }

    private func addSection(_ section: SettingsAccordionSection) {
        sectionsStack.addArrangedSubview(section.containerView)
        section.containerView.widthAnchor.constraint(equalTo: sectionsStack.widthAnchor).isActive = true
    }

    private func applyDefaultExpansion() {
        for section in accordionSections {
            section.setExpanded(section.id == .alerts, animated: false)
        }
    }

    private func makeGroup(rows: [SettingsRowView]) -> NSView {
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false

        let group = SettingsGroupView()
        group.showsBorder = false
        group.fillColor = SettingsLayout.groupBackgroundColor
        group.translatesAutoresizingMaskIntoConstraints = false
        group.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: group.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: group.trailingAnchor),
            stack.topAnchor.constraint(equalTo: group.topAnchor),
            stack.bottomAnchor.constraint(equalTo: group.bottomAnchor)
        ])

        for row in rows {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        for (index, row) in rows.enumerated() {
            row.setShowsSeparator(index < rows.count - 1)
        }

        return group
    }

    private func makeSliderTrailing(slider: NSSlider, value: NSTextField) -> NSView {
        slider.translatesAutoresizingMaskIntoConstraints = false
        value.alignment = .right
        NSLayoutConstraint.activate([
            slider.widthAnchor.constraint(equalToConstant: SettingsLayout.sliderWidth),
            value.widthAnchor.constraint(equalToConstant: SettingsLayout.sliderValueWidth)
        ])

        let stack = NSStackView(views: [slider, value])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = SettingsLayout.sliderValueSpacing
        return stack
    }

    private func makeToggleRow(
        leading: NSView,
        toggle: NSSwitch,
        note: NSTextField? = nil
    ) -> SettingsRowView {
        SettingsRowView(
            leading: leading,
            trailing: toggle,
            note: note,
            isInteractive: true,
            onClick: { toggle.performClick(nil) }
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
        notificationSwitch.state = Settings.idleAlertNotificationEnabled ? .on : .off
        soundControl.selectedSegment = soundSegmentIndex(for: Settings.idleAlertSoundMode)
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

        applySoundAvailability()
    }

    @objc private func devSpinnerToggled() {
        let enabled = spinnerSwitch.state == .on
        Settings.devForceSpinner = enabled
        Telemetry.trackSettingToggle("dev_force_spinner", enabled: enabled)
    }

    @objc private func idleThresholdChanged() {
        let snapped = applyMagneticSnap(
            idleThresholdSlider.doubleValue,
            snapPoints: idleThresholdSnapPoints,
            threshold: idleThresholdSnapThreshold
        )
        let percent = Settings.quantizePercent(snapped)
        Settings.idleAlertThresholdPercent = percent
        idleThresholdSlider.doubleValue = percent
        idleThresholdValue.stringValue = percentString(percent)
        let rounded = Int(round(percent))
        if lastIdleThresholdReported != rounded {
            lastIdleThresholdReported = rounded
            Telemetry.trackSettingValue("idle_alert_threshold_percent", value: Double(rounded))
        }
    }

    @objc private func idleThresholdDoubleClicked() {
        idleThresholdSlider.doubleValue = Settings.idleAlertDefaultThreshold
        idleThresholdChanged()
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

    @objc private func soundModeChanged() {
        let selectedMode = soundMode(for: soundControl.selectedSegment)
        if selectedMode == .system, currentSystemSoundAvailability() != .available {
            soundControl.selectedSegment = soundSegmentIndex(for: .glass)
            Settings.idleAlertSoundMode = .glass
            Telemetry.track("settings.choice_changed", properties: [
                "setting": "idle_alert_sound_mode",
                "value": Settings.IdleAlertSoundMode.glass.rawValue,
                "reason": "system_unavailable"
            ])
            applySoundAvailability()
            return
        }
        Settings.idleAlertSoundMode = selectedMode
        Telemetry.track("settings.choice_changed", properties: [
            "setting": "idle_alert_sound_mode",
            "value": selectedMode.rawValue
        ])
        applySoundAvailability()
    }

    @objc private func notificationToggled() {
        let enabled = notificationSwitch.state == .on
        Settings.idleAlertNotificationEnabled = enabled
        Telemetry.trackSettingToggle("idle_alert_notifications", enabled: enabled)
        applySoundAvailability()
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
        Telemetry.trackUi("ui.settings_back_clicked")
        onBack?()
    }

    @objc private func testNotificationTapped() {
        Telemetry.trackUi("ui.test_notification_clicked")
        onTestNotification?()
    }

    private func percentString(_ value: Double) -> String {
        "\(Int(round(value)))%"
    }

    private func applyMagneticSnap(
        _ value: Double,
        snapPoints: [Double],
        threshold: Double
    ) -> Double {
        guard threshold > 0 else {
            return value
        }
        var closest = value
        var closestDistance = threshold
        for snap in snapPoints {
            let distance = abs(value - snap)
            if distance <= closestDistance {
                closest = snap
                closestDistance = distance
            }
        }
        return closest
    }

    private var isAppBundle: Bool {
        let bundle = Bundle.main
        guard bundle.bundleURL.pathExtension.lowercased() == "app" else {
            return false
        }
        return (bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String) == "APPL"
    }

    private func refreshNotificationSettings() {
        guard isAppBundle else {
            notificationAuthorizationStatus = .notDetermined
            notificationSoundSetting = .notSupported
            applySoundAvailability()
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.notificationAuthorizationStatus = settings.authorizationStatus
                self?.notificationSoundSetting = settings.soundSetting
                self?.applySoundAvailability()
            }
        }
    }

    private func soundSegmentIndex(for mode: Settings.IdleAlertSoundMode) -> Int {
        switch mode {
        case .off:
            return 0
        case .glass:
            return 1
        case .system:
            return 2
        }
    }

    private func soundMode(for segment: Int) -> Settings.IdleAlertSoundMode {
        switch segment {
        case 0:
            return .off
        case 2:
            return .system
        default:
            return .glass
        }
    }

    private func currentSystemSoundAvailability() -> SystemSoundAvailability {
        guard Settings.idleAlertNotificationEnabled else {
            return .notificationsDisabled
        }
        guard isAppBundle else {
            return .bundleRequired
        }
        switch notificationAuthorizationStatus {
        case .authorized, .provisional:
            break
        case .denied, .notDetermined:
            return .systemNotificationsDisabled
        @unknown default:
            return .systemNotificationsDisabled
        }
        switch notificationSoundSetting {
        case .enabled:
            return .available
        case .disabled:
            return .systemSoundDisabled
        case .notSupported:
            return .systemSoundUnsupported
        @unknown default:
            return .systemSoundDisabled
        }
    }

    private func applySoundAvailability() {
        let availability = currentSystemSoundAvailability()
        let systemSoundAvailable = availability == .available
        soundControl.setEnabled(systemSoundAvailable, forSegment: 2)
        clearSoundNote()
        soundControl.toolTip = nil

        if !systemSoundAvailable, Settings.idleAlertSoundMode == .system {
            Settings.idleAlertSoundMode = .glass
            soundControl.selectedSegment = soundSegmentIndex(for: .glass)
            Telemetry.track("settings.choice_changed", properties: [
                "setting": "idle_alert_sound_mode",
                "value": Settings.IdleAlertSoundMode.glass.rawValue,
                "reason": "system_unavailable"
            ])
        }
    }

    private func clearSoundNote() {
        soundNote.stringValue = ""
        soundRow?.setNoteHidden(true)
    }

    private func showSystemSoundUnavailableNote() {
        let availability = currentSystemSoundAvailability()
        guard availability != .available else {
            return
        }
        soundNote.stringValue = soundNoteMessage(for: availability)
        soundRow?.setNoteHidden(false)
    }

    private func soundNoteMessage(for availability: SystemSoundAvailability) -> String {
        switch availability {
        case .available:
            return ""
        case .notificationsDisabled:
            return "System sound needs notifications.\nGlass still plays."
        case .bundleRequired:
            return "System sound needs the bundled app.\nGlass still plays."
        case .systemNotificationsDisabled:
            return "System notifications are disabled.\nGlass still plays."
        case .systemSoundDisabled:
            return "System sound is off in macOS.\nGlass still plays."
        case .systemSoundUnsupported:
            return "System sound option isn't available yet.\nRe-enable notifications to request it."
        }
    }

    private func updateCursorTargets() {
        var targets: [NSView] = [backButton]
        for section in accordionSections {
            targets.append(section.isExpanded ? section.headerRow : section.containerView)
        }

        if alertsSection?.isExpanded == true {
            if let notificationRow {
                targets.append(notificationRow)
            }
            targets.append(idleThresholdSlider)
            targets.append(soundControl)
        }

        if privacySection?.isExpanded == true {
            if let telemetryRow {
                targets.append(telemetryRow)
            }
        }

        if devSection?.isExpanded == true {
            if let spinnerRow {
                targets.append(spinnerRow)
            }
            if let queueColorOverrideRow {
                targets.append(queueColorOverrideRow)
            }
            targets.append(contentsOf: [queueColorSlider, testNotificationButton, simulateAgentsButton])
        }

        guard let contentView = view as? CursorRectsView else {
            return
        }
        contentView.cursorTargets = targets
        contentView.window?.invalidateCursorRects(for: contentView)
    }
}
