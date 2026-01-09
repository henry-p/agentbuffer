import AppKit

final class CursorRectsView: NSView {
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
        for target in cursorTargets where target.superview != nil {
            let rect = convert(target.bounds, from: target)
            addCursorRect(rect, cursor: .pointingHand)
        }
    }
}
