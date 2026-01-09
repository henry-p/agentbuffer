import AppKit

final class PopoverCoordinator: NSObject {
    private let statusItem: NSStatusItem
    private let panel: PopoverPanel
    private let rootController: PopoverRootController
    private let settingsController: SettingsPopoverController
    private let infoController: InfoPopoverController
    private var isShowingSettings = false
    private var isShowingInfo = false
    private lazy var eventMonitor: EventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
        self?.handlePopoverEvent()
    }
    private let mainController: MainPopoverController

    init(
        statusItem: NSStatusItem,
        onQuit: @escaping () -> Void,
        onTestNotification: @escaping () -> Void,
        onMetrics: @escaping () -> Void,
        onLoadMore: @escaping () -> Void,
        onSelectAgent: @escaping (AgentListItem) -> Void,
        onTogglePause: @escaping (Bool) -> Void
    ) {
        self.statusItem = statusItem
        self.mainController = MainPopoverController()
        self.settingsController = SettingsPopoverController()
        self.infoController = InfoPopoverController()
        self.rootController = PopoverRootController(
            mainController: mainController,
            settingsController: settingsController,
            infoController: infoController
        )
        self.panel = PopoverPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: PopoverLayout.width,
                height: PopoverLayout.height
            ),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        mainController.onSettings = { [weak self] in
            self?.showSettings()
        }
        mainController.onMetrics = onMetrics
        mainController.onQuit = onQuit
        mainController.onSelectAgent = onSelectAgent
        mainController.onTogglePause = onTogglePause
        mainController.onInfo = { [weak self] in
            self?.showInfo()
        }
        settingsController.onBack = { [weak self] in
            self?.showMain()
        }
        infoController.onBack = { [weak self] in
            self?.showMain()
        }
        settingsController.onTestNotification = onTestNotification
        mainController.onLoadMore = onLoadMore

        configurePanel()
        attachStatusItemButton()
    }

    func hide() {
        hidePopoverWindow()
    }

    func updateMain(
        summary: String,
        runningAgents: [AgentListItem],
        idleAgents: [AgentListItem],
        recentAgents: [AgentListItem],
        canLoadMore: Bool,
        isPaused: Bool
    ) {
        mainController.update(
            summary: summary,
            runningAgents: runningAgents,
            idleAgents: idleAgents,
            recentAgents: recentAgents,
            canLoadMore: canLoadMore,
            isPaused: isPaused
        )
    }

    func updateInfo(pressureColor: NSColor, pressurePercent: Double) {
        infoController.update(pressureColor: pressureColor, pressurePercent: pressurePercent)
    }

    @objc private func togglePopover() {
        if panel.isVisible {
            hidePopoverWindow()
            return
        }
        showMain()
        showPopoverWindow()
    }

    private func configurePanel() {
        panel.contentViewController = rootController
        panel.setContentSize(NSSize(width: PopoverLayout.width, height: PopoverLayout.height))
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.level = .statusBar
        panel.collectionBehavior = [.moveToActiveSpace]
        panel.hidesOnDeactivate = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
    }

    private func attachStatusItemButton() {
        guard let button = statusItem.button else {
            return
        }
        button.target = self
        button.action = #selector(togglePopover)
    }

    private func showMain() {
        rootController.showMain()
        if isShowingSettings {
            isShowingSettings = false
            Telemetry.trackUi("ui.settings_closed")
        }
        if isShowingInfo {
            isShowingInfo = false
            Telemetry.trackUi("ui.info_closed")
        }
    }

    private func showSettings() {
        settingsController.resetAccordionState()
        rootController.showSettings()
        if !isShowingSettings {
            isShowingSettings = true
            Telemetry.trackUi("ui.settings_opened")
        }
    }

    private func showInfo() {
        rootController.showInfo()
        if !isShowingInfo {
            isShowingInfo = true
            Telemetry.trackUi("ui.info_opened")
        }
    }

    private func showPopoverWindow() {
        positionPopoverWindow()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak self] in
            self?.panel.makeFirstResponder(nil)
        }
        eventMonitor.start()
        Telemetry.trackUi("ui.popover_opened")
    }

    private func hidePopoverWindow() {
        eventMonitor.stop()
        panel.orderOut(nil)
        Telemetry.trackUi("ui.popover_closed")
    }

    private func handlePopoverEvent() {
        guard panel.isVisible else {
            return
        }
        let location = NSEvent.mouseLocation
        if panel.frame.contains(location) {
            return
        }
        if let buttonFrame = statusButtonScreenFrame(), buttonFrame.contains(location) {
            return
        }
        hidePopoverWindow()
    }

    private func statusButtonScreenFrame() -> NSRect? {
        guard let button = statusItem.button, let window = button.window else {
            return nil
        }
        let buttonRect = button.convert(button.bounds, to: nil)
        return window.convertToScreen(buttonRect)
    }

    private func positionPopoverWindow() {
        guard let buttonFrame = statusButtonScreenFrame() else {
            return
        }
        let screenFrame = statusItem.button?.window?.screen?.visibleFrame ?? buttonFrame
        let panelSize = panel.frame.size
        let gap: CGFloat = 6
        var origin = NSPoint(
            x: buttonFrame.midX - panelSize.width / 2,
            y: buttonFrame.minY - panelSize.height - gap
        )
        let horizontalInset: CGFloat = 8
        if origin.x < screenFrame.minX + horizontalInset {
            origin.x = screenFrame.minX + horizontalInset
        }
        if origin.x + panelSize.width > screenFrame.maxX - horizontalInset {
            origin.x = screenFrame.maxX - panelSize.width - horizontalInset
        }
        if origin.y < screenFrame.minY + gap {
            origin.y = buttonFrame.maxY + gap
        }
        panel.setFrameOrigin(origin)
    }
}
