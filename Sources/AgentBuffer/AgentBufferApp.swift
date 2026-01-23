import AppKit
import UserNotifications

private enum RefreshDefaults {
    static let pollingInterval: TimeInterval = 1.0
}

@main
final class AgentBufferApp: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    deinit {
        if let devObserver {
            NotificationCenter.default.removeObserver(devObserver)
        }
    }

    static func main() {
        guard let lock = SingleInstanceLock(name: "agentbuffer") else {
            return
        }
        let app = NSApplication.shared
        let delegate = AgentBufferApp()
        delegate.instanceLock = lock
        app.delegate = delegate
        app.run()
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private lazy var menuBarRenderer = MenuBarRenderer(statusItem: statusItem)
    private let terminalNavigator = TerminalNavigator()

    private let reader = StatusReader()
    private var fileWatchers: [FileWatcher] = []
    private var timer: Timer?
    private var popoverCoordinator: PopoverCoordinator?
    private var instanceLock: SingleInstanceLock?
    private var lastSnapshot: StatusSnapshot = .empty
    private var recentAgents: [AgentListItem] = []
    private var simulateAgentsEnabled = false
    private var simulateShowAllHistory = false
    private var pulseTimer: Timer?
    private var devObserver: NSObjectProtocol?
    private var lastPidSignature: String = ""
    private var lastTrackedCounts: (running: Int, idle: Int, total: Int)?
    private let refreshQueue = DispatchQueue(label: "AgentBuffer.Refresh", qos: .utility)
    private var refreshInFlight = false
    private var includesExtensionHostedCodex = false
    private var idleAlertInitialized = false
    private var idleAlertActive = false
    private var idleAlertPrimed = false
    private var lastIdlePercent: Double?
    private var notificationsAuthorized = false
    private var notificationAuthorizationStatus: UNAuthorizationStatus = .notDetermined
    private var notificationSoundSetting: UNNotificationSetting = .notSupported
    private var notificationPromptWindow: NSWindow?
    private var animationsPaused = false
    private let metricsServer = MetricsWebServer()

    private var isAppBundle: Bool {
        let bundle = Bundle.main
        guard bundle.bundleURL.pathExtension.lowercased() == "app" else {
            return false
        }
        return (bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String) == "APPL"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Telemetry.configure()
        setupPopoverCoordinator()
        setupStatusItemIcon()
        configureNotifications()
        setupFileWatcher()
        metricsServer.start()
        refresh()
        startTimer()
        devObserver = NotificationCenter.default.addObserver(
            forName: .settingsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        popoverCoordinator?.hide()
    }

    private func configureNotifications() {
        guard isAppBundle else {
            return
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.refreshNotificationSettings { status in
                if status == .notDetermined {
                    self?.requestAuthorizationWithPrompt()
                }
            }
        }
    }

    private func refreshNotificationSettings(completion: ((UNAuthorizationStatus) -> Void)? = nil) {
        guard isAppBundle else {
            completion?(.notDetermined)
            return
        }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            let status = settings.authorizationStatus
            let authorized = status == .authorized || status == .provisional
            DispatchQueue.main.async {
                self?.notificationsAuthorized = authorized
                self?.notificationAuthorizationStatus = status
                self?.notificationSoundSetting = settings.soundSetting
                completion?(status)
            }
        }
    }

    private func requestAuthorizationWithPrompt(completion: ((Bool) -> Void)? = nil) {
        guard isAppBundle else {
            completion?(false)
            return
        }
        let center = UNUserNotificationCenter.current()
        let previousPolicy = NSApp.activationPolicy()
        DispatchQueue.main.async {
            NSApp.setActivationPolicy(.regular)
            self.showNotificationPromptWindow()
            NSApp.activate(ignoringOtherApps: true)
            center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
                center.getNotificationSettings { settings in
                    let status = settings.authorizationStatus
                    let authorized = status == .authorized || status == .provisional
                    DispatchQueue.main.async {
                        self?.notificationsAuthorized = authorized
                        self?.notificationAuthorizationStatus = status
                        self?.notificationSoundSetting = settings.soundSetting
                        self?.hideNotificationPromptWindow()
                        NSApp.setActivationPolicy(previousPolicy)
                        completion?(authorized)
                    }
                }
            }
        }
    }

    private func showNotificationPromptWindow(message: String = "Requesting notification permission…") {
        if let existing = notificationPromptWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let size = NSSize(width: 320, height: 120)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "AgentBuffer"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effectView.autoresizingMask = [.width, .height]
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active

        let label = NSTextField(labelWithString: message)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.alignment = .center
        effectView.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: effectView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: effectView.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: effectView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: effectView.trailingAnchor, constant: -16)
        ])
        window.contentView = effectView
        window.center()
        window.makeKeyAndOrderFront(nil)
        notificationPromptWindow = window
    }

    private func showNotificationInfoWindow(message: String, autoHideAfter delay: TimeInterval = 2.0) {
        showNotificationPromptWindow(message: message)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.hideNotificationPromptWindow()
        }
    }

    private func hideNotificationPromptWindow() {
        notificationPromptWindow?.orderOut(nil)
        notificationPromptWindow = nil
    }

    func applicationWillTerminate(_ notification: Notification) {
        metricsServer.stop()
        instanceLock?.release()
    }

    private func setupStatusItemIcon() {
        menuBarRenderer.setup(initialPercent: Settings.percentMin)
    }

    private func setupPopoverCoordinator() {
        popoverCoordinator = PopoverCoordinator(
            statusItem: statusItem,
            onQuit: { [weak self] in
                self?.quit()
            },
            onTestNotification: { [weak self] in
                self?.testNotification()
            },
            onMetrics: { [weak self] in
                self?.openMetricsDashboard()
            },
            onLoadMore: { [weak self] in
                self?.simulateShowAllHistory = true
                self?.refresh()
            },
            onSelectAgent: { [weak self] item in
                self?.focusAgent(item)
            },
            onTogglePause: { [weak self] paused in
                self?.setAnimationsPaused(paused)
            }
        )
    }

    private func focusAgent(_ item: AgentListItem) {
        guard let pid = item.pid else {
            return
        }
        focusAgent(pid: pid)
    }

    private func focusAgent(pid: Int) {
        let success = terminalNavigator.focus(pid: pid)
        Telemetry.trackUi("ui.agent_focus_attempted", properties: [
            "success": success
        ])
        if !success, Settings.devModeEnabled {
            NSLog("[AgentBuffer] Unable to focus terminal for pid=%d", pid)
        }
    }

    private func openMetricsDashboard() {
        guard let url = metricsServer.metricsURL() else {
            if Settings.devModeEnabled {
                NSLog("[AgentBuffer] Metrics dashboard unavailable")
            }
            showNotificationInfoWindow(message: "Metrics dashboard not ready yet.")
            return
        }
        Telemetry.trackUi("ui.metrics_opened")
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func testNotification() {
        guard isAppBundle else {
            showNotificationInfoWindow(
                message: "Notifications require the bundled app. Run ./scripts/dev.sh --bundle."
            )
            return
        }
        refreshNotificationSettings { [weak self] status in
            guard let self else { return }
            switch status {
            case .denied:
                self.showNotificationInfoWindow(
                    message: "Enable AgentBuffer notifications in System Settings."
                )
                self.openNotificationSettings()
            case .notDetermined:
                self.requestAuthorizationWithPrompt { [weak self] granted in
                    guard let self else { return }
                    if granted {
                        self.postTestNotification()
                    } else {
                        self.showNotificationInfoWindow(
                            message: "Notification permission not granted."
                        )
                    }
                }
            default:
                self.postTestNotification()
            }
        }
    }

    @objc private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else {
            return
        }
        Telemetry.trackUi("ui.notification_settings_opened")
        NSWorkspace.shared.open(url)
    }

    private func refresh() {
        fileWatchers.forEach { $0.start() }
        if refreshInFlight {
            return
        }
        refreshInFlight = true
        refreshQueue.async { [weak self] in
            guard let self else {
                return
            }
            let pids = self.reader.currentPids().sorted()
            let pidSignature = self.pidSignature(for: pids)
            let includesExtensionHosted = self.containsExtensionHostedCodexSession(pids: pids)
            let snapshot = self.reader.readSnapshot()
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                self.lastPidSignature = pidSignature
                self.includesExtensionHostedCodex = includesExtensionHosted
                self.refreshInFlight = false
                self.update(snapshot: snapshot)
            }
        }
    }

    private func update(snapshot: StatusSnapshot) {
        menuBarRenderer.setPaused(animationsPaused)
        let simulate = Settings.devModeEnabled && Settings.devSimulateAgents
        let wasSimulating = simulateAgentsEnabled
        simulateAgentsEnabled = simulate

        let displaySnapshot: StatusSnapshot
        var canLoadMore = false
        if simulate {
            if !wasSimulating {
                simulateShowAllHistory = false
            }
            let simulated = makeSimulatedSnapshot(showAllHistory: simulateShowAllHistory)
            displaySnapshot = simulated.snapshot
            recentAgents = simulated.recentAgents
            canLoadMore = simulated.canLoadMore
        } else {
            if wasSimulating {
                recentAgents.removeAll()
                simulateShowAllHistory = false
            } else {
                updateRecentAgents(previous: lastSnapshot.runningAgents, current: snapshot.runningAgents)
            }
            displaySnapshot = snapshot
        }

        let previousSnapshot = lastSnapshot
        let changed = displaySnapshot != previousSnapshot
        lastSnapshot = displaySnapshot
        let idlePercent = idlePercent(for: displaySnapshot)
        let shouldBlink = displaySnapshot.totalCount == 0
            || idlePercent >= Settings.idleAlertThresholdPercent
        let queueEffect: MenuBarRenderer.QueueIconEffect = shouldBlink
            ? .blink
            : (displaySnapshot.runningCount > 0 ? .shimmer : .none)
        menuBarRenderer.setQueueEffect(queueEffect)
        let forceWhite = displaySnapshot.totalCount == 0 && queueEffect != .blink
        menuBarRenderer.updateQueueIcon(percent: displaySnapshot.progressPercent, forceWhite: forceWhite)
        let pressurePercent = MenuBarRenderer.pressureDisplayPercent(for: displaySnapshot.progressPercent)
        let pressureColor = MenuBarRenderer.pressureColor(
            for: displaySnapshot.progressPercent,
            forceWhite: forceWhite
        )
        if let button = statusItem.button {
            // Force a full redraw of the status item text.
            button.attributedTitle = NSAttributedString(string: "")
            button.title = ""
            button.attributedTitle = menuBarRenderer.makeStatusTitle(snapshot: displaySnapshot)
            button.toolTip = displaySnapshot.toolTip
            button.invalidateIntrinsicContentSize()
            button.needsLayout = true
            button.needsDisplay = true
        }
        updateSpinnerState(for: displaySnapshot)
        trackCountsIfNeeded(previous: previousSnapshot, current: displaySnapshot, isSimulating: simulate)
        handleIdleAlert(snapshot: displaySnapshot)

        let summary = summaryText(
            running: displaySnapshot.runningCount,
            total: displaySnapshot.totalCount,
            includeExtensionNote: includesExtensionHostedCodex && !simulate
        )
        popoverCoordinator?.updateMain(
            summary: summary,
            runningAgents: displaySnapshot.runningAgents,
            idleAgents: displaySnapshot.idleAgents,
            recentAgents: recentAgents,
            canLoadMore: canLoadMore,
            isPaused: animationsPaused
        )
        popoverCoordinator?.updateInfo(
            pressureColor: pressureColor,
            pressurePercent: pressurePercent
        )

        if Settings.devModeEnabled, changed {
            let percent = Int(round(displaySnapshot.progressPercent))
            NSLog("[AgentBuffer] running=%d total=%d percent=%d", displaySnapshot.runningCount, displaySnapshot.totalCount, percent)
        }
    }

    private func updateRecentAgents(previous: [AgentListItem], current: [AgentListItem]) {
        guard !previous.isEmpty else {
            return
        }
        let currentIds = Set(current.map { $0.id })
        let finished = previous.filter { !currentIds.contains($0.id) }
        guard !finished.isEmpty else {
            return
        }
        let merged = finished + recentAgents
        recentAgents = Array(merged.prefix(5))
    }

    private func summaryText(running: Int, total: Int, includeExtensionNote: Bool) -> String {
        if includeExtensionNote {
            return "\(running) out of \(total) agents running (includes extension-hosted sessions)."
        }
        return "\(running) out of \(total) agents running."
    }

    private func trackCountsIfNeeded(
        previous: StatusSnapshot,
        current: StatusSnapshot,
        isSimulating: Bool
    ) {
        guard !isSimulating else {
            return
        }
        let counts = (running: current.runningCount, idle: current.finishedCount, total: current.totalCount)
        if let lastTrackedCounts,
           lastTrackedCounts.running == counts.running,
           lastTrackedCounts.idle == counts.idle,
           lastTrackedCounts.total == counts.total {
            return
        }
        let idlePercent = idlePercent(for: current)
        Telemetry.trackState("state.agent_counts_changed", properties: [
            "running": counts.running,
            "idle": counts.idle,
            "total": counts.total,
            "idle_percent": Int(round(idlePercent))
        ])
        lastTrackedCounts = counts
    }

    private func makeSimulatedSnapshot(showAllHistory: Bool) -> (snapshot: StatusSnapshot, recentAgents: [AgentListItem], canLoadMore: Bool) {
        let running: [AgentListItem] = [
            AgentListItem(id: "sim-codex-1", type: .codex, title: "Refactor popover layout + scroll view"),
            AgentListItem(id: "sim-codex-2", type: .codex, title: "Investigate idle alert edge cases"),
            AgentListItem(id: "sim-codex-3", type: .codex, title: "Fix compact event handling in log parser"),
            AgentListItem(id: "sim-codex-4", type: .codex, title: "Polish menu bar icon gradient"),
            AgentListItem(id: "sim-codex-5", type: .codex, title: "Add simulated agents toggle to dev panel"),
            AgentListItem(id: "sim-claude-1", type: .claude, title: "Summarize test failures from CI log"),
            AgentListItem(id: "sim-claude-2", type: .claude, title: "Draft release notes for v0.2"),
            AgentListItem(id: "sim-codex-6", type: .codex, title: "Tune idle alert threshold logic"),
            AgentListItem(id: "sim-codex-7", type: .codex, title: "Verify notification authorization flow"),
            AgentListItem(id: "sim-codex-8", type: .codex, title: "Clean up dev logging output")
        ]
        let idle: [AgentListItem] = [
            AgentListItem(id: "sim-idle-1", type: .codex, title: "Triage idle sessions from overnight"),
            AgentListItem(id: "sim-idle-2", type: .claude, title: "Summarize backlog cleanup tasks")
        ]
        let historyAll: [AgentListItem] = [
            AgentListItem(id: "sim-recent-1", type: .codex, title: "Fix menu bar popover positioning"),
            AgentListItem(id: "sim-recent-2", type: .codex, title: "Tweak queue icon gradient for 0/0"),
            AgentListItem(id: "sim-recent-3", type: .claude, title: "Audit session log parsing for compact events"),
            AgentListItem(id: "sim-recent-4", type: .codex, title: "Improve status item redraw stability"),
            AgentListItem(id: "sim-recent-5", type: .codex, title: "Polish popover spacing for cards"),
            AgentListItem(id: "sim-recent-6", type: .claude, title: "Investigate agent idle notification edge cases"),
            AgentListItem(id: "sim-recent-7", type: .codex, title: "Fix notification permission prompt timing"),
            AgentListItem(id: "sim-recent-8", type: .codex, title: "Tune scroll view layout constraints"),
            AgentListItem(id: "sim-recent-9", type: .codex, title: "Refine settings popover layout"),
            AgentListItem(id: "sim-recent-10", type: .codex, title: "Update beads context with UI changes")
        ]
        let recent = showAllHistory ? historyAll : Array(historyAll.prefix(5))
        let canLoadMore = !showAllHistory && historyAll.count > recent.count
        let total = running.count + idle.count
        let progressPercent: Double = total == 0
            ? 0
            : (Double(running.count) / Double(total)) * Settings.percentMax
        let snapshot = StatusSnapshot(
            runningCount: running.count,
            finishedCount: idle.count,
            totalCount: total,
            progressPercent: progressPercent,
            runningAgents: running,
            idleAgents: idle,
            mostRecentFinishedPid: nil
        )
        return (snapshot, recent, canLoadMore)
    }


    private func pidSignature(for pids: [Int]) -> String {
        pids.map(String.init).joined(separator: ",")
    }

    private func containsExtensionHostedCodexSession(pids: [Int]) -> Bool {
        guard !pids.isEmpty else {
            return false
        }
        for pid in pids {
            guard let command = AgentBufferApp.runCommand(
                "/bin/ps",
                arguments: ["-o", "command=", "-p", String(pid)]
            )?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else {
                continue
            }
            let executable = command.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? command
            guard !executable.isEmpty else {
                continue
            }
            if isExtensionHostedCodex(executable: executable) {
                return true
            }
        }
        return false
    }

    private func isExtensionHostedCodex(executable: String) -> Bool {
        if executable == "codex" {
            return false
        }
        if executable.contains("/extensions/") || executable.contains("/extension/") {
            return true
        }
        if executable.contains("/.cursor/") || executable.contains("/.vscode/") {
            return true
        }
        return false
    }

    private static func runCommand(_ path: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    private func setupFileWatcher() {
        fileWatchers.forEach { $0.stop() }
        fileWatchers = reader.sessionRoots.map { root in
            FileWatcher(url: root) { [weak self] in
                DispatchQueue.main.async {
                    self?.refresh()
                }
            }
        }
        fileWatchers.forEach { $0.start() }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: RefreshDefaults.pollingInterval, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }
            self.refresh()
        }
    }

    private func startPulseTimer() {
        pulseTimer?.invalidate()
        pulseTimer = Timer.scheduledTimer(withTimeInterval: MenuBarRenderer.spinnerPulseInterval, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }
            self.menuBarRenderer.advanceSpinnerIndex()
            if let button = self.statusItem.button {
                button.attributedTitle = self.menuBarRenderer.makeStatusTitle(snapshot: self.lastSnapshot)
                button.needsDisplay = true
            }
        }
    }

    private func updateSpinnerState(for snapshot: StatusSnapshot) {
        if animationsPaused {
            pulseTimer?.invalidate()
            pulseTimer = nil
            return
        }
        let shouldSpin = snapshot.runningCount > 0
            || (Settings.devModeEnabled && Settings.devForceSpinner)
            || menuBarRenderer.queueAnimationActive
        if shouldSpin {
            if pulseTimer == nil {
                startPulseTimer()
            }
        } else {
            pulseTimer?.invalidate()
            pulseTimer = nil
        }
    }

    private func setAnimationsPaused(_ paused: Bool) {
        animationsPaused = paused
        menuBarRenderer.setPaused(paused)
        if paused {
            idleAlertInitialized = false
            idleAlertActive = false
            idleAlertPrimed = false
            lastIdlePercent = nil
        }
        updateSpinnerState(for: lastSnapshot)
        update(snapshot: lastSnapshot)
    }

    private func handleIdleAlert(snapshot: StatusSnapshot) {
        guard !animationsPaused else {
            return
        }
        let total = snapshot.totalCount
        let idlePercent = idlePercent(for: snapshot)
        let threshold = Settings.idleAlertThresholdPercent
        let shouldAlert = total > 0 && idlePercent >= threshold
        if !idleAlertInitialized {
            idleAlertInitialized = true
            idleAlertActive = shouldAlert
            if !shouldAlert {
                idleAlertPrimed = true
            }
            lastIdlePercent = idlePercent
            return
        }
        var shouldTrigger = false
        if shouldAlert && !idleAlertActive && idleAlertPrimed {
            shouldTrigger = true
        } else if shouldAlert && !idleAlertPrimed,
                  let lastIdlePercent,
                  idlePercent > lastIdlePercent {
            shouldTrigger = true
            idleAlertPrimed = true
        }
        if !shouldAlert {
            idleAlertPrimed = true
        }
        if shouldTrigger {
            let triggerSnapshot = snapshot
            refreshNotificationSettings { [weak self] _ in
                self?.performIdleAlert(
                    snapshot: triggerSnapshot,
                    idlePercent: idlePercent,
                    threshold: threshold
                )
            }
        }
        idleAlertActive = shouldAlert
        lastIdlePercent = idlePercent
    }

    private func idlePercent(for snapshot: StatusSnapshot) -> Double {
        let total = snapshot.totalCount
        guard total > 0 else {
            return 0
        }
        return (Double(snapshot.finishedCount) / Double(total)) * Settings.percentMax
    }

    private func performIdleAlert(
        snapshot: StatusSnapshot,
        idlePercent: Double,
        threshold: Double
    ) {
        let requestedSoundMode = Settings.idleAlertSoundMode
        let systemSoundAvailable = isSystemNotificationSoundAvailable()
        let effectiveSoundMode = resolvedSoundMode(
            requestedSoundMode,
            systemSoundAvailable: systemSoundAvailable
        )
        Telemetry.trackState("alert.idle_triggered", properties: [
            "idle_percent": Int(round(idlePercent)),
            "threshold_percent": Int(round(threshold)),
            "idle_count": snapshot.finishedCount,
            "total_count": snapshot.totalCount,
            "notifications_enabled": Settings.idleAlertNotificationEnabled,
            "sound_mode": effectiveSoundMode.rawValue,
            "sound_mode_requested": requestedSoundMode.rawValue,
            "system_sound_available": systemSoundAvailable
        ])
        if effectiveSoundMode == .glass {
            playCustomIdleSound()
        }
        postIdleNotification(
            idlePercent: idlePercent,
            snapshot: snapshot,
            playSound: effectiveSoundMode == .system && systemSoundAvailable
        )
    }

    private func isSystemNotificationSoundAvailable() -> Bool {
        guard isAppBundle else {
            return false
        }
        guard Settings.idleAlertNotificationEnabled else {
            return false
        }
        guard notificationsAuthorized else {
            return false
        }
        return notificationSoundSetting == .enabled
    }

    private func resolvedSoundMode(
        _ requested: Settings.IdleAlertSoundMode,
        systemSoundAvailable: Bool
    ) -> Settings.IdleAlertSoundMode {
        if requested == .system && !systemSoundAvailable {
            return .glass
        }
        return requested
    }

    private func playCustomIdleSound() {
        if let sound = NSSound(named: NSSound.Name("Glass")) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }

    private func postIdleNotification(
        idlePercent: Double,
        snapshot: StatusSnapshot,
        force: Bool = false,
        source: String = "idle",
        playSound: Bool = false
    ) {
        guard force || Settings.idleAlertNotificationEnabled else {
            return
        }
        let sendNotification = {
            let percent = Int(round(idlePercent))
            let threshold = Int(round(Settings.idleAlertThresholdPercent))
            let content = UNMutableNotificationContent()
            content.title = "AgentBuffer"
            content.body = "Idle agents: \(snapshot.finishedCount)/\(snapshot.totalCount) (\(percent)%). Threshold: \(threshold)%."
            if playSound {
                content.sound = .default
            }
            if let pid = snapshot.mostRecentFinishedPid {
                content.userInfo = ["pid": pid]
            }
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    NSLog("[AgentBuffer] Failed to post notification: %@", error.localizedDescription)
                }
            }
            Telemetry.trackState("notification.sent", properties: [
                "source": source,
                "idle_percent": percent,
                "threshold_percent": threshold,
                "idle_count": snapshot.finishedCount,
                "total_count": snapshot.totalCount,
                "sound_mode": Settings.idleAlertSoundMode.rawValue,
                "sound_enabled": playSound
            ])
        }
        if notificationsAuthorized {
            sendNotification()
            return
        }
        if notificationAuthorizationStatus == .notDetermined {
            requestAuthorizationWithPrompt { granted in
                if granted {
                    sendNotification()
                }
            }
        }
    }

    private func postTestNotification() {
        let playSound = Settings.idleAlertSoundMode == .system && isSystemNotificationSoundAvailable()
        postTestNotification(playSound: playSound)
    }

    private func postTestNotification(playSound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "AgentBuffer"
        content.body = "Test notification."
        if playSound {
            content.sound = .default
        }
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error {
                NSLog("[AgentBuffer] Failed to post test notification: %@", error.localizedDescription)
                DispatchQueue.main.async {
                    self?.showNotificationInfoWindow(
                        message: "Test notification failed. Check notification permissions."
                    )
                }
            }
        }
        Telemetry.trackState("notification.sent", properties: [
            "source": "test",
            "sound_mode": Settings.idleAlertSoundMode.rawValue,
            "sound_enabled": playSound
        ])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        var options: UNNotificationPresentationOptions = [.banner, .list]
        if notification.request.content.sound != nil {
            options.insert(.sound)
        }
        return options
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        let userInfo = response.notification.request.content.userInfo
        let pidValue = userInfo["pid"]
        let pid = (pidValue as? NSNumber)?.intValue ?? (pidValue as? Int)
        if let pid {
            DispatchQueue.main.async { [weak self] in
                self?.focusAgent(pid: pid)
            }
        }
    }
}
