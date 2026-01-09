import AppKit

final class CursorRectsView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }

    var cursorTargets: [NSView] = [] {
        didSet {
            window?.invalidateCursorRects(for: self)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.invalidateCursorRects(for: self)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard let window else {
            return
        }
        for target in cursorTargets where target.superview != nil {
            guard target.window == window else {
                continue
            }
            guard target.isDescendant(of: self) else {
                continue
            }
            guard !target.isHidden, target.alphaValue > 0.01 else {
                continue
            }
            if let control = target as? NSControl, !control.isEnabled {
                continue
            }
            let rect = target.convert(target.bounds, to: self)
            guard !rect.isEmpty, rect.intersects(bounds) else {
                continue
            }
            addCursorRect(rect, cursor: .pointingHand)
        }
    }
}
