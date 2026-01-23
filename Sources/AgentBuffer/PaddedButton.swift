import AppKit

enum PaddedButtonStyle {
    case standard
    case medium
    case compact
}

final class PaddedButton: NSButton {
    var contentInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8) {
        didSet {
            invalidateIntrinsicContentSize()
        }
    }

    private let hoverBackgroundColor = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
            return NSColor.white.withAlphaComponent(0.12)
        }
        return NSColor.black.withAlphaComponent(0.08)
    }
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovering = false
    private let hoverLayer = CALayer()

    var titleFont: NSFont? {
        didSet {
            applyTitleAttributes()
        }
    }

    override var title: String {
        didSet {
            applyTitleAttributes()
        }
    }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(
            width: size.width + contentInsets.left + contentInsets.right,
            height: size.height + contentInsets.top + contentInsets.bottom
        )
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayer()
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        super.viewWillMove(toSuperview: newSuperview)
        if newSuperview == nil {
            isHovering = false
            updateHoverAppearance()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            isHovering = false
            updateHoverAppearance()
        }
    }

    override func viewDidHide() {
        super.viewDidHide()
        isHovering = false
        updateHoverAppearance()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        isHovering = false
        updateHoverAppearance()
    }

    override func layout() {
        super.layout()
        updateCornerRadius()
        updateHoverLayerFrame()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        hoverLayer.backgroundColor = hoverBackgroundColor.cgColor
        updateHoverAppearance()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
        let tracking = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(tracking)
        hoverTrackingArea = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        isHovering = true
        updateHoverAppearance()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        isHovering = false
        updateHoverAppearance()
    }

    override var isEnabled: Bool {
        didSet {
            updateHoverAppearance()
        }
    }

    private func configureLayer() {
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        hoverLayer.backgroundColor = hoverBackgroundColor.cgColor
        hoverLayer.cornerCurve = .continuous
        hoverLayer.isHidden = true
        hoverLayer.zPosition = -1
        layer?.addSublayer(hoverLayer)
        updateCornerRadius()
        updateHoverLayerFrame()
    }

    private func updateCornerRadius() {
        layer?.cornerRadius = bounds.height / 2
    }

    private func updateHoverLayerFrame() {
        hoverLayer.frame = bounds
        hoverLayer.cornerRadius = bounds.height / 2
    }

    private func updateHoverAppearance() {
        guard isEnabled else {
            hoverLayer.isHidden = true
            return
        }
        hoverLayer.isHidden = !isHovering
    }

    func applyStyle(_ style: PaddedButtonStyle) {
        bezelStyle = .inline
        isBordered = false
        focusRingType = .none
        if let cell = cell as? NSButtonCell {
            cell.highlightsBy = []
        }
        switch style {
        case .standard:
            controlSize = .regular
            let font = NSFont.systemFont(ofSize: NSFont.systemFontSize + 1, weight: .semibold)
            titleFont = font
            contentInsets = NSEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
        case .medium:
            controlSize = .small
            let font = NSFont.systemFont(ofSize: NSFont.systemFontSize + 1, weight: .semibold)
            titleFont = font
            contentInsets = NSEdgeInsets(top: 3, left: 10, bottom: 3, right: 10)
        case .compact:
            controlSize = .small
            let font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            titleFont = font
            contentInsets = NSEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
        }
    }

    private func applyTitleAttributes() {
        guard let titleFont else {
            return
        }
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: titleFont]
        )
    }
}
