import AppKit

enum AgentBadgeStyle {
    case text
    case logo
}

final class AgentCardView: NSView {
    let item: AgentListItem
    var onClick: ((AgentListItem) -> Void)?

    private var baseBorderColor: NSColor { NSColor.quaternaryLabelColor }
    private var hoverBorderColor: NSColor { NSColor.controlAccentColor.withAlphaComponent(0.8) }
    private var trackingAreaRef: NSTrackingArea?
    private var isHovering = false
    private let accent: NSColor
    private let badgeStyle: AgentBadgeStyle
    private let iconContainer = NSView()
    private let runtimeTrackLayer = CALayer()
    private let runtimeFillLayer = CALayer()
    private var runtimeRatio: Double?
    private let showsRuntime: Bool
    private let runtimeRow = NSStackView()
    private let runtimeLabel = NSTextField(labelWithString: "Runtime")
    private let runtimeValue = NSTextField(labelWithString: "—")
    private var logoView: NSImageView?

    private static let logoBadgeSize = CGSize(width: 28, height: 28)
    private static let logoSymbolSize: CGFloat = 20
    private var cardBackgroundColor: NSColor {
        NSColor.windowBackgroundColor.withAlphaComponent(0.85)
    }
    
    init(
        item: AgentListItem,
        dimmed: Bool = false,
        runtimeRatio: Double? = nil,
        runtimeSeconds: TimeInterval? = nil,
        showsRuntime: Bool = false,
        badgeStyle: AgentBadgeStyle = .text
    ) {
        self.item = item
        self.accent = AgentCardView.accentColor(for: item.type)
        self.runtimeRatio = runtimeRatio
        self.showsRuntime = showsRuntime
        let logoImage = badgeStyle == .logo ? AgentCardView.logoImage(for: item.type) : nil
        self.badgeStyle = (badgeStyle == .logo && logoImage != nil) ? .logo : .text
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = cardBackgroundColor.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = baseBorderColor.cgColor
        if dimmed {
            alphaValue = 0.55
        }
        setupRuntimeLayers()

        let badgeLines = badgeLines(for: item.type)
        let badgeFont = NSFont.monospacedSystemFont(ofSize: 9, weight: .semibold)
        let badgeSize = AgentCardView.badgeSize(
            style: self.badgeStyle,
            badgeLines: badgeLines,
            font: badgeFont
        )

        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.wantsLayer = true
        iconContainer.layer?.cornerRadius = 6
        iconContainer.setContentHuggingPriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: badgeSize.width),
            iconContainer.heightAnchor.constraint(equalToConstant: badgeSize.height)
        ])

        if self.badgeStyle == .logo, let logoImage {
            let logoView = NSImageView(image: logoImage)
            logoView.translatesAutoresizingMaskIntoConstraints = false
            logoView.imageScaling = .scaleProportionallyUpOrDown
            logoView.contentTintColor = .labelColor
            iconContainer.addSubview(logoView)
            NSLayoutConstraint.activate([
                logoView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
                logoView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
                logoView.widthAnchor.constraint(equalToConstant: AgentCardView.logoSymbolSize),
                logoView.heightAnchor.constraint(equalToConstant: AgentCardView.logoSymbolSize)
            ])
            self.logoView = logoView
        } else {
            let contentContainer = NSView()
            contentContainer.translatesAutoresizingMaskIntoConstraints = false
            iconContainer.addSubview(contentContainer)

            let badgeStack = NSStackView()
            badgeStack.orientation = .vertical
            badgeStack.alignment = .leading
            badgeStack.spacing = 0
            badgeStack.translatesAutoresizingMaskIntoConstraints = false
            contentContainer.addSubview(badgeStack)

            for line in badgeLines {
                let iconLabel = NSTextField(labelWithString: line)
                iconLabel.font = badgeFont
                iconLabel.textColor = accent
                iconLabel.alignment = .left
                iconLabel.lineBreakMode = .byTruncatingTail
                iconLabel.maximumNumberOfLines = 1
                iconLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
                badgeStack.addArrangedSubview(iconLabel)
            }

            NSLayoutConstraint.activate([
                contentContainer.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
                contentContainer.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
                contentContainer.leadingAnchor.constraint(greaterThanOrEqualTo: iconContainer.leadingAnchor, constant: 4),
                contentContainer.trailingAnchor.constraint(lessThanOrEqualTo: iconContainer.trailingAnchor, constant: -4),
                badgeStack.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
                badgeStack.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
                badgeStack.topAnchor.constraint(equalTo: contentContainer.topAnchor),
                badgeStack.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor)
            ])
        }

        let titleLabel = NSTextField(labelWithString: item.title)
        titleLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [iconContainer, titleLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        runtimeLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize - 1)
        runtimeLabel.textColor = .secondaryLabelColor
        runtimeValue.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize - 1, weight: .regular)
        runtimeValue.textColor = .secondaryLabelColor
        let runtimeSpacer = NSView()
        runtimeSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        runtimeRow.orientation = .horizontal
        runtimeRow.alignment = .centerY
        runtimeRow.distribution = .fill
        runtimeRow.spacing = 6
        runtimeRow.translatesAutoresizingMaskIntoConstraints = false
        runtimeRow.addArrangedSubview(runtimeLabel)
        runtimeRow.addArrangedSubview(runtimeSpacer)
        runtimeRow.addArrangedSubview(runtimeValue)

        let contentStack = NSStackView(views: [row, runtimeRow])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 6
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            contentStack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            contentStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])

        applyColors()
        updateRuntime(seconds: runtimeSeconds, ratio: runtimeRatio)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef {
            removeTrackingArea(trackingAreaRef)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect, .cursorUpdate]
        let tracking = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(tracking)
        trackingAreaRef = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        guard !isHovering else { return }
        isHovering = true
        setHovering(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        guard isHovering else { return }
        isHovering = false
        setHovering(false)
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        if bounds.contains(location) {
            onClick?(item)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        trackingAreaRef = nil
        updateTrackingAreas()
        window?.invalidateCursorRects(for: self)
    }

    override func layout() {
        super.layout()
        updateTrackingAreas()
        window?.invalidateCursorRects(for: self)
        layoutRuntimeBar()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {
        applyColors()
    }

    private func setHovering(_ hovering: Bool) {
        layer?.borderColor = (hovering ? hoverBorderColor : baseBorderColor).cgColor
    }

    private func applyColors() {
        layer?.backgroundColor = cardBackgroundColor.cgColor
        layer?.borderColor = (isHovering ? hoverBorderColor : baseBorderColor).cgColor
        iconContainer.layer?.backgroundColor = badgeBackgroundColor().cgColor
        iconContainer.layer?.borderColor = badgeBorderColor().cgColor
        iconContainer.layer?.borderWidth = badgeBorderWidth()
        logoView?.contentTintColor = .labelColor
        runtimeTrackLayer.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.4).cgColor
        runtimeFillLayer.backgroundColor = accent.withAlphaComponent(0.55).cgColor
        runtimeTrackLayer.isHidden = !showsRuntime || runtimeRow.isHidden
    }

    func updateRuntime(seconds: TimeInterval?, ratio: Double?) {
        guard showsRuntime else {
            runtimeRatio = nil
            runtimeRow.isHidden = true
            runtimeValue.stringValue = "—"
            runtimeTrackLayer.isHidden = true
            needsLayout = true
            return
        }
        runtimeRatio = ratio
        if let seconds {
            runtimeRow.isHidden = false
            runtimeValue.stringValue = formatRuntime(seconds)
        } else {
            runtimeRow.isHidden = true
            runtimeValue.stringValue = "—"
        }
        runtimeTrackLayer.isHidden = runtimeRow.isHidden
        needsLayout = true
    }

    private func setupRuntimeLayers() {
        guard let layer = layer else {
            return
        }
        runtimeTrackLayer.cornerRadius = 1
        runtimeTrackLayer.masksToBounds = true
        runtimeFillLayer.cornerRadius = 1
        runtimeTrackLayer.addSublayer(runtimeFillLayer)
        layer.addSublayer(runtimeTrackLayer)
        applyColors()
    }

    private func layoutRuntimeBar() {
        guard showsRuntime, let ratio = runtimeRatio, !runtimeRow.isHidden else {
            runtimeTrackLayer.isHidden = true
            return
        }
        let inset: CGFloat = 12
        let height: CGFloat = 2
        let desiredY = runtimeRow.frame.minY - 4
        let y = max(4, desiredY)
        let width = max(0, bounds.width - inset * 2)
        let trackFrame = CGRect(x: inset, y: y, width: width, height: height)
        runtimeTrackLayer.frame = trackFrame
        let fillWidth = width * CGFloat(min(1, max(0, ratio)))
        runtimeFillLayer.frame = CGRect(x: 0, y: 0, width: fillWidth, height: height)
        runtimeTrackLayer.isHidden = false
    }

    private func formatRuntime(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        }
        let minutes = totalSeconds / 60
        let remainder = totalSeconds % 60
        if minutes < 60 {
            return String(format: "%dm %02ds", minutes, remainder)
        }
        let hours = minutes / 60
        let minutesRemainder = minutes % 60
        return String(format: "%dh %02dm", hours, minutesRemainder)
    }

    private func badgeBackgroundColor() -> NSColor {
        switch badgeStyle {
        case .logo:
            return NSColor.clear
        case .text:
            return accent.withAlphaComponent(0.18)
        }
    }

    private func badgeBorderColor() -> NSColor {
        switch badgeStyle {
        case .logo:
            return NSColor(white: 0.88, alpha: 1.0)
        case .text:
            return NSColor.clear
        }
    }

    private func badgeBorderWidth() -> CGFloat {
        switch badgeStyle {
        case .logo:
            return 2
        case .text:
            return 0
        }
    }

    private static func accentColor(for type: AgentType) -> NSColor {
        switch type {
        case .codex:
            return NSColor.systemBlue
        case .claude:
            return NSColor.systemOrange
        case .unknown:
            return NSColor.systemGray
        }
    }

    private func badgeLines(for type: AgentType) -> [String] {
        let name: String
        switch type {
        case .codex:
            name = "codex"
        case .claude:
            name = "claude"
        case .unknown:
            name = "agent"
        }
        return wrapBadgeLines(name)
    }

    private static func badgeSize(style: AgentBadgeStyle, badgeLines: [String], font: NSFont) -> CGSize {
        switch style {
        case .logo:
            return logoBadgeSize
        case .text:
            let maxLineWidth = badgeLines
                .map { $0 as NSString }
                .map { $0.size(withAttributes: [.font: font]).width }
                .max() ?? 0
            let badgeWidth = max(28, ceil(maxLineWidth) + 12)
            let lineHeight = font.boundingRectForFont.height
            let badgeHeight = ceil(lineHeight * CGFloat(max(1, badgeLines.count))) + 6
            return CGSize(width: badgeWidth, height: badgeHeight)
        }
    }

    private static func logoImage(for type: AgentType) -> NSImage? {
        switch type {
        case .codex:
            return loadLogo(named: "openai_symbol")
        case .claude:
            return loadLogo(named: "anthropic_symbol")
        case .unknown:
            return nil
        }
    }

    private static func loadLogo(named name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        return image
    }

    private func wrapBadgeLines(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 3 else {
            return [trimmed]
        }
        let midpoint = Int(ceil(Double(trimmed.count) / 2.0))
        let index = trimmed.index(trimmed.startIndex, offsetBy: midpoint)
        return [
            String(trimmed[..<index]),
            String(trimmed[index...])
        ]
    }
}
