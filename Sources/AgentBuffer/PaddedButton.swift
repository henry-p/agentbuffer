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

    private let pressedAlpha: CGFloat = 0.65

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

    override func mouseDown(with event: NSEvent) {
        let previousAlpha = alphaValue
        alphaValue = min(previousAlpha, pressedAlpha)
        defer { alphaValue = previousAlpha }
        super.mouseDown(with: event)
    }

    func applyStyle(_ style: PaddedButtonStyle) {
        bezelStyle = .inline
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
