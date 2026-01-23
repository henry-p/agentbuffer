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

    private let hoverBackgroundColor = NSColor.black.withAlphaComponent(0.08)
    private var hoverTrackingArea: NSTrackingArea?
    private var isHovering = false

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

    override func layout() {
        super.layout()
        updateCornerRadius()
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
        updateCornerRadius()
    }

    private func updateCornerRadius() {
        layer?.cornerRadius = bounds.height / 2
    }

    private func updateHoverAppearance() {
        guard isEnabled else {
            layer?.backgroundColor = nil
            return
        }
        layer?.backgroundColor = isHovering ? hoverBackgroundColor.cgColor : nil
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
            contentInsets = NSEdgeInsets(top: 1, left: 6, bottom: 1, right: 6)
        case .medium:
            controlSize = .small
            let font = NSFont.systemFont(ofSize: NSFont.systemFontSize + 1, weight: .semibold)
            titleFont = font
            contentInsets = NSEdgeInsets(top: 1, left: 6, bottom: 1, right: 6)
        case .compact:
            controlSize = .small
            let font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            titleFont = font
            contentInsets = NSEdgeInsets(top: 1, left: 5, bottom: 1, right: 5)
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
