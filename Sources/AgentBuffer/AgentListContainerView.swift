import AppKit

final class AgentListContainerView: NSView {
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        for card in agentCards() {
            let rect = convert(card.bounds, from: card)
            if rect.contains(point) {
                return self
            }
        }
        return super.hitTest(point)
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        for card in agentCards() {
            let rect = convert(card.bounds, from: card)
            if rect.contains(location) {
                card.onClick?(card.item)
                return
            }
        }
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for card in agentCards() {
            let rect = convert(card.bounds, from: card)
            addCursorRect(rect, cursor: .pointingHand)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func layout() {
        super.layout()
        window?.invalidateCursorRects(for: self)
    }

    private func agentCards() -> [AgentCardView] {
        var cards: [AgentCardView] = []
        collectCards(in: self, into: &cards)
        return cards
    }

    private func collectCards(in view: NSView, into cards: inout [AgentCardView]) {
        for subview in view.subviews {
            if let card = subview as? AgentCardView {
                cards.append(card)
            } else if !subview.subviews.isEmpty {
                collectCards(in: subview, into: &cards)
            }
        }
    }

}
