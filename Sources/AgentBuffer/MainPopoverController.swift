import AppKit

private final class IconButtonView: NSImageView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

final class MainPopoverController: NSViewController {
    var onSettings: (() -> Void)?
    var onMetrics: (() -> Void)?
    var onQuit: (() -> Void)?
    var onLoadMore: (() -> Void)?
    var onSelectAgent: ((AgentListItem) -> Void)?
    var onTogglePause: ((Bool) -> Void)?
    var onInfo: (() -> Void)?

    private let summaryLabel = NSTextField(labelWithString: "—")
    private let titleLabel = NSTextField(labelWithString: "AgentBuffer")
    private let titleRow = NSStackView()
    private let pauseButton = NSButton(title: "", target: nil, action: nil)
    private let summaryRow = NSStackView()
    private let infoIconView = IconButtonView()
    private let agentScrollView = NSScrollView()
    private let agentListContainer = AgentListContainerView()
    private let agentListStack = NSStackView()
    private let separator = NSBox()
    private let loadMoreButton = NSButton(title: "Load more", target: nil, action: nil)
    private let metricsButton = PaddedButton(title: "Metrics", target: nil, action: nil)
    private let settingsButton = PaddedButton(title: "Settings", target: nil, action: nil)
    private let quitButton = PaddedButton(title: "Quit", target: nil, action: nil)

    private var summaryText = "—"
    private var runningAgents: [AgentListItem] = []
    private var idleAgents: [AgentListItem] = []
    private var recentAgents: [AgentListItem] = []
    private var canLoadMore = false
    private var isPaused = false
    private var pauseImage: NSImage?
    private var playImage: NSImage?

    override func loadView() {
        view = CursorRectsView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: PopoverLayout.width,
                height: PopoverLayout.height
            )
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupContent()
        syncLabels()
        syncAgentCards()
        updateCursorTargets()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateCursorTargets()
    }

    func update(
        summary: String,
        runningAgents: [AgentListItem],
        idleAgents: [AgentListItem],
        recentAgents: [AgentListItem],
        canLoadMore: Bool,
        isPaused: Bool
    ) {
        let labelsChanged = summaryText != summary
        let listChanged = self.runningAgents != runningAgents
            || self.idleAgents != idleAgents
            || self.recentAgents != recentAgents
            || self.canLoadMore != canLoadMore
        let pauseChanged = self.isPaused != isPaused

        summaryText = summary
        self.runningAgents = runningAgents
        self.idleAgents = idleAgents
        self.recentAgents = recentAgents
        self.canLoadMore = canLoadMore
        self.isPaused = isPaused

        if isViewLoaded {
            if labelsChanged {
                syncLabels()
            }
            if listChanged {
                syncAgentCards()
            }
            if pauseChanged {
                syncPauseState()
            }
            syncRuntimeIndicators()
        }
    }

    private func setupContent() {
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize + 2, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .left
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1

        configurePauseButton()
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 6
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        titleRow.addArrangedSubview(titleLabel)
        titleRow.addArrangedSubview(pauseButton)
        titleRow.setContentHuggingPriority(.required, for: .horizontal)
        titleRow.setContentCompressionResistancePriority(.required, for: .horizontal)

        configureInfoIcon()

        summaryLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        summaryLabel.textColor = .labelColor
        summaryLabel.lineBreakMode = .byWordWrapping
        summaryLabel.maximumNumberOfLines = 0

        summaryRow.orientation = .horizontal
        summaryRow.spacing = 6
        summaryRow.alignment = .centerY
        summaryRow.translatesAutoresizingMaskIntoConstraints = false
        summaryRow.addArrangedSubview(summaryLabel)
        summaryRow.addArrangedSubview(infoIconView)

        agentListContainer.translatesAutoresizingMaskIntoConstraints = false

        agentListStack.orientation = .vertical
        agentListStack.spacing = 8
        agentListStack.alignment = .leading
        agentListStack.translatesAutoresizingMaskIntoConstraints = false
        agentListContainer.addSubview(agentListStack)

        agentScrollView.translatesAutoresizingMaskIntoConstraints = false
        agentScrollView.hasVerticalScroller = true
        agentScrollView.autohidesScrollers = true
        agentScrollView.drawsBackground = false
        agentScrollView.scrollerStyle = .overlay
        agentScrollView.documentView = agentListContainer
        agentScrollView.setContentHuggingPriority(.defaultLow, for: .vertical)
        agentScrollView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        configureButton(metricsButton, action: #selector(metricsTapped))
        configureButton(settingsButton, action: #selector(settingsTapped))
        configureButton(quitButton, action: #selector(quitTapped))

        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        loadMoreButton.target = self
        loadMoreButton.action = #selector(loadMoreTapped)
        loadMoreButton.bezelStyle = .rounded
        loadMoreButton.controlSize = .small

        let footerStretch = NSView()
        footerStretch.setContentHuggingPriority(.defaultLow, for: .horizontal)
        footerStretch.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let footerRow = NSStackView(views: [metricsButton, settingsButton, footerStretch, quitButton])
        footerRow.orientation = .horizontal
        footerRow.distribution = .fill
        footerRow.alignment = .centerY
        footerRow.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleRow)
        view.addSubview(summaryRow)
        view.addSubview(agentScrollView)
        view.addSubview(separator)
        view.addSubview(footerRow)

        let contentView = agentScrollView.contentView
        NSLayoutConstraint.activate([
            titleRow.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleRow.topAnchor.constraint(equalTo: view.topAnchor, constant: PopoverLayout.topInset),
            titleRow.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: PopoverLayout.horizontalInset),
            titleRow.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -PopoverLayout.horizontalInset),

            summaryRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PopoverLayout.horizontalInset),
            summaryRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PopoverLayout.horizontalInset),
            summaryRow.topAnchor.constraint(equalTo: titleRow.bottomAnchor, constant: PopoverLayout.stackSpacing),

            agentScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PopoverLayout.horizontalInset),
            agentScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PopoverLayout.horizontalInset),
            agentScrollView.topAnchor.constraint(equalTo: summaryRow.bottomAnchor, constant: PopoverLayout.stackSpacing),
            agentScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: PopoverLayout.minListHeight),

            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PopoverLayout.horizontalInset),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PopoverLayout.horizontalInset),
            separator.topAnchor.constraint(equalTo: agentScrollView.bottomAnchor, constant: PopoverLayout.stackSpacing),

            footerRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: PopoverLayout.horizontalInset),
            footerRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -PopoverLayout.horizontalInset),
            footerRow.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: PopoverLayout.stackSpacing),
            footerRow.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -PopoverLayout.bottomInset),

            agentListContainer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            agentListContainer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            agentListContainer.topAnchor.constraint(equalTo: contentView.topAnchor),
            agentListContainer.widthAnchor.constraint(equalTo: contentView.widthAnchor),

            agentListStack.leadingAnchor.constraint(equalTo: agentListContainer.leadingAnchor),
            agentListStack.trailingAnchor.constraint(equalTo: agentListContainer.trailingAnchor),
            agentListStack.topAnchor.constraint(equalTo: agentListContainer.topAnchor),
            agentListStack.bottomAnchor.constraint(equalTo: agentListContainer.bottomAnchor)
        ])
    }

    private func configureButton(_ button: PaddedButton, action: Selector) {
        button.target = self
        button.action = action
        button.applyStyle(.medium)
    }

    private func configurePauseButton() {
        pauseButton.target = self
        pauseButton.action = #selector(pauseTapped)
        pauseButton.isBordered = false
        pauseButton.imagePosition = .imageOnly
        pauseButton.bezelStyle = .inline
        pauseButton.contentTintColor = .secondaryLabelColor
        pauseButton.setContentHuggingPriority(.required, for: .horizontal)
        pauseButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        if let pause = NSImage(systemSymbolName: "pause.fill", accessibilityDescription: "Pause") {
            pauseImage = pause.withSymbolConfiguration(config)
        }
        if let play = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Resume") {
            playImage = play.withSymbolConfiguration(config)
        }
        syncPauseState()
    }

    private func configureInfoIcon() {
        infoIconView.onClick = { [weak self] in
            self?.infoTapped()
        }
        infoIconView.isEditable = false
        infoIconView.imageScaling = .scaleProportionallyUpOrDown
        infoIconView.contentTintColor = .tertiaryLabelColor
        infoIconView.toolTip = "Efficiency info"
        let iconSize = (summaryLabel.font ?? .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)).pointSize
        if let image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Info") {
            let config = NSImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)
            infoIconView.image = image.withSymbolConfiguration(config)
        }
        infoIconView.setContentHuggingPriority(.required, for: .horizontal)
        infoIconView.setContentCompressionResistancePriority(.required, for: .horizontal)
        infoIconView.translatesAutoresizingMaskIntoConstraints = false
        infoIconView.widthAnchor.constraint(equalToConstant: iconSize).isActive = true
        infoIconView.heightAnchor.constraint(equalToConstant: iconSize).isActive = true
    }

    private func syncLabels() {
        summaryLabel.stringValue = summaryText
    }

    private func syncPauseState() {
        pauseButton.image = isPaused ? playImage : pauseImage
        pauseButton.toolTip = isPaused ? "Resume animations" : "Pause animations"
    }

    private func syncAgentCards() {
        agentListStack.arrangedSubviews.forEach { subview in
            agentListStack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        let hasRunning = !runningAgents.isEmpty
        let hasIdle = !idleAgents.isEmpty
        let idleIds = Set(idleAgents.map { $0.id })
        let filteredRecent = recentAgents.filter { !idleIds.contains($0.id) }
        let visibleRecent = canLoadMore ? Array(filteredRecent.prefix(5)) : filteredRecent
        let hasRecent = !visibleRecent.isEmpty || canLoadMore
        agentScrollView.isHidden = !(hasRunning || hasIdle || hasRecent)
        guard hasRunning || hasIdle || hasRecent else {
            return
        }
        if hasIdle {
            addSectionHeader(title: "Idle")
            addAgentCards(idleAgents, section: "idle", badgeStyle: .logo)
        }
        if hasRunning {
            addSectionHeader(title: "Running")
            addAgentCards(
                runningAgents,
                section: "running",
                dimmed: false,
                runtimeRatios: runtimeRatios(),
                runtimeSeconds: runtimeSecondsById(),
                showsRuntime: true,
                badgeStyle: .logo
            )
        }
        if hasRecent {
            addSectionHeader(title: "History")
            addAgentCards(visibleRecent, section: "history", dimmed: true, badgeStyle: .logo)
            if canLoadMore {
                let spacer = NSView()
                spacer.translatesAutoresizingMaskIntoConstraints = false
                spacer.heightAnchor.constraint(equalToConstant: 4).isActive = true
                agentListStack.addArrangedSubview(spacer)
                loadMoreButton.translatesAutoresizingMaskIntoConstraints = false
                agentListStack.addArrangedSubview(loadMoreButton)
                loadMoreButton.widthAnchor.constraint(equalTo: agentListStack.widthAnchor).isActive = true
            }
        }
        agentListContainer.window?.invalidateCursorRects(for: agentListContainer)
        updateCursorTargets()
    }

    private func addSectionHeader(title: String) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.systemFontSize - 1, weight: .semibold)
        label.textColor = .tertiaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        agentListStack.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: agentListStack.widthAnchor).isActive = true
        agentListStack.setCustomSpacing(4, after: label)
    }

    private func addAgentCards(
        _ agents: [AgentListItem],
        section: String,
        dimmed: Bool = false,
        runtimeRatios: [String: Double] = [:],
        runtimeSeconds: [String: TimeInterval] = [:],
        showsRuntime: Bool = false,
        badgeStyle: AgentBadgeStyle = .text
    ) {
        for agent in agents {
            let ratio = runtimeRatios[agent.id]
            let seconds = runtimeSeconds[agent.id]
            let card = AgentCardView(
                item: agent,
                dimmed: dimmed,
                runtimeRatio: ratio,
                runtimeSeconds: seconds,
                showsRuntime: showsRuntime,
                badgeStyle: badgeStyle
            )
            card.onClick = { [weak self] item in
                Telemetry.trackUi("ui.agent_clicked", properties: [
                    "section": section,
                    "agent_type": item.type.rawValue
                ])
                self?.onSelectAgent?(item)
            }
            agentListStack.addArrangedSubview(card)
            card.widthAnchor.constraint(equalTo: agentListStack.widthAnchor).isActive = true
        }
    }

    private func runtimeRatios() -> [String: Double] {
        var ratios: [String: Double] = [:]
        guard !runningAgents.isEmpty else {
            return ratios
        }
        let maxRuntime = runningAgents.compactMap { $0.runtimeSeconds }.max() ?? 0
        guard maxRuntime > 0 else {
            for agent in runningAgents {
                ratios[agent.id] = 0
            }
            return ratios
        }
        for agent in runningAgents {
            let runtime = agent.runtimeSeconds ?? 0
            ratios[agent.id] = runtime / maxRuntime
        }
        return ratios
    }

    private func runtimeSecondsById() -> [String: TimeInterval] {
        var seconds: [String: TimeInterval] = [:]
        for agent in runningAgents {
            seconds[agent.id] = agent.runtimeSeconds ?? 0
        }
        return seconds
    }

    private func syncRuntimeIndicators() {
        let ratios = runtimeRatios()
        let seconds = runtimeSecondsById()
        for subview in agentListStack.arrangedSubviews {
            guard let card = subview as? AgentCardView else {
                continue
            }
            let ratio = ratios[card.item.id]
            card.updateRuntime(seconds: seconds[card.item.id], ratio: ratio)
        }
    }

    private func updateCursorTargets() {
        guard let contentView = view as? CursorRectsView else {
            return
        }
        var targets: [NSView] = [metricsButton, settingsButton, quitButton, infoIconView, pauseButton]
        if canLoadMore, loadMoreButton.superview != nil {
            targets.append(loadMoreButton)
        }
        contentView.cursorTargets = targets
        contentView.window?.invalidateCursorRects(for: contentView)
    }

    @objc private func metricsTapped() {
        Telemetry.trackUi("ui.metrics_button_clicked")
        onMetrics?()
    }

    @objc private func settingsTapped() {
        Telemetry.trackUi("ui.settings_button_clicked")
        onSettings?()
    }

    @objc private func pauseTapped() {
        let next = !isPaused
        isPaused = next
        syncPauseState()
        Telemetry.trackUi("ui.pause_toggled", properties: [
            "paused": next
        ])
        onTogglePause?(next)
    }

    @objc private func quitTapped() {
        Telemetry.trackUi("ui.quit_clicked")
        onQuit?()
    }

    @objc private func infoTapped() {
        Telemetry.trackUi("ui.info_clicked")
        onInfo?()
    }

    @objc private func loadMoreTapped() {
        Telemetry.trackUi("ui.load_more_clicked")
        onLoadMore?()
    }
}
