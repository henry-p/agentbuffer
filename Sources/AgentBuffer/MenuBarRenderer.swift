import AppKit

private enum MenuBarMetrics {
    static let queueIconHeightScale: CGFloat = 0.74
    static let queueIconVerticalOffsetScale: CGFloat = 0.05
    static let spinnerFontScale: CGFloat = 0.8
    static let iconSpacerWidthScale: CGFloat = 0.2
    static let iconSpacerHeight: CGFloat = 1
    static let interItemKernScale: CGFloat = 0.0
    static let fractionFontScale: CGFloat = 0.82
    static let fractionUpOffsetScale: CGFloat = 0.35
    static let fractionDownOffsetScale: CGFloat = 0.12
    static let dimmedDarkWhite: CGFloat = 0.9
    static let dimmedLightWhite: CGFloat = 0.1
    static let spinnerNudgeScale: CGFloat = 0.06
    static let spinnerBounceAmplitudeScale: CGFloat = 0.22
    static let spinnerPulseInterval: TimeInterval = 0.12
    static let queueBlinkInterval: TimeInterval = 0.72
    static let shimmerStep: CGFloat = 0.06
    static let pausedIconAlpha: CGFloat = 0.6
}

final class MenuBarRenderer {
    static let spinnerPulseInterval: TimeInterval = MenuBarMetrics.spinnerPulseInterval

    enum QueueIconEffect {
        case none
        case shimmer
        case blink
    }

    private let statusItem: NSStatusItem
    private var queueBaseImage: NSImage?
    private var queueDisplayImage: NSImage?
    private var currentPercent: Double = Settings.percentMin
    private var currentForceWhite = false
    private var spinnerIndex: Int = 0
    private var shimmerPhase: CGFloat = 0
    private var queueEffect: QueueIconEffect = .none
    private var desiredQueueEffect: QueueIconEffect = .none
    private var blinkOn = false
    private var blinkElapsed: TimeInterval = 0
    private var paused = false
    private let spinnerGlyph = "•"
    private let spinnerBouncePhases: [CGFloat] = [
        0.0, 0.4, 0.7, 0.92, 1.0, 0.92, 0.7, 0.4,
        0.0, -0.4, -0.7, -0.92, -1.0, -0.92, -0.7, -0.4
    ]

    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
    }

    func setup(initialPercent: Double) {
        queueBaseImage = loadQueueImage(named: "queue", extension: "svg")
        if let button = statusItem.button {
            button.imagePosition = .noImage
            button.image = nil
            button.imageHugsTitle = true
        }
        updateQueueIcon(percent: initialPercent)
    }

    func updateQueueIcon(percent: Double, forceWhite: Bool = false) {
        guard let button = statusItem.button else {
            return
        }
        if queueBaseImage == nil {
            queueBaseImage = loadQueueImage(named: "queue", extension: "svg")
        }
        guard queueBaseImage != nil else {
            return
        }
        currentPercent = percent
        currentForceWhite = forceWhite
        updateQueueDisplayImage()
        button.image = nil
        button.contentTintColor = nil
    }

    static func pressureColor(for percent: Double, forceWhite: Bool = false) -> NSColor {
        let displayPercent = pressureDisplayPercent(for: percent)
        return forceWhite ? NSColor.white : colorForPercent(displayPercent)
    }

    static func pressureDisplayPercent(for percent: Double) -> Double {
        Settings.devQueueIconOverrideEnabled
            ? (Settings.devQueueIconPercent ?? Settings.percentMin)
            : percent
    }

    func makeStatusTitle(snapshot: StatusSnapshot) -> NSAttributedString {
        let baseFont = NSFont.menuBarFont(ofSize: 0)
        let spinnerFont = NSFont.monospacedSystemFont(
            ofSize: baseFont.pointSize * MenuBarMetrics.spinnerFontScale,
            weight: .regular
        )
        let spinnerActive = !paused && (snapshot.runningCount > 0
            || (Settings.devModeEnabled && Settings.devForceSpinner))
        let bouncePhase = spinnerActive
            ? spinnerBouncePhases[spinnerIndex % spinnerBouncePhases.count]
            : 0.0
        let bounceOffset = baseFont.pointSize * MenuBarMetrics.spinnerBounceAmplitudeScale * bouncePhase
        let result = NSMutableAttributedString()
        if let queueImage = queueDisplayImage {
            let iconAttachment = queueIconAttachment(image: queueImage, baseFont: baseFont)
            result.append(NSAttributedString(attachment: iconAttachment))
            let iconSpacer = NSAttributedString(string: " ", attributes: [
                .font: baseFont,
                .kern: baseFont.pointSize * MenuBarMetrics.iconSpacerWidthScale
            ])
            result.append(iconSpacer)
        }

        let fraction = makeFractionText(
            numerator: snapshot.runningCount,
            denominator: snapshot.totalCount,
            baseFont: baseFont,
            color: NSColor.labelColor
        )
        result.append(fraction)

        let interSpacer = NSAttributedString(string: " ", attributes: [
            .font: baseFont,
            .kern: baseFont.pointSize * MenuBarMetrics.interItemKernScale
        ])
        result.append(interSpacer)

        let spinnerAttachment = spinnerAttachment(
            glyph: spinnerGlyph,
            font: spinnerFont,
            baseFont: baseFont,
            color: dimmedLabelColor(),
            verticalOffset: bounceOffset,
            applyNudge: spinnerActive
        )
        result.append(NSAttributedString(attachment: spinnerAttachment))

        return result
    }

    func advanceSpinnerIndex() {
        guard !paused else {
            return
        }
        spinnerIndex = (spinnerIndex + 1) % spinnerBouncePhases.count
        switch queueEffect {
        case .none:
            return
        case .shimmer:
            shimmerPhase += MenuBarMetrics.shimmerStep
            if shimmerPhase >= 1 {
                shimmerPhase -= 1
            }
            updateQueueDisplayImage()
        case .blink:
            blinkElapsed += MenuBarMetrics.spinnerPulseInterval
            if blinkElapsed >= MenuBarMetrics.queueBlinkInterval {
                blinkElapsed -= MenuBarMetrics.queueBlinkInterval
                blinkOn.toggle()
                updateQueueDisplayImage()
            }
        }
    }

    func setQueueEffect(_ effect: QueueIconEffect) {
        desiredQueueEffect = effect
        guard !paused else { return }
        guard queueEffect != effect else { return }
        queueEffect = effect
        shimmerPhase = 0
        blinkElapsed = 0
        blinkOn = effect == .blink
        updateQueueDisplayImage()
    }

    var queueAnimationActive: Bool {
        !paused && queueEffect != .none
    }

    func setShimmerActive(_ active: Bool) {
        setQueueEffect(active ? .shimmer : .none)
    }

    func setPaused(_ paused: Bool) {
        guard self.paused != paused else { return }
        self.paused = paused
        if paused {
            queueEffect = .none
            shimmerPhase = 0
            blinkElapsed = 0
            blinkOn = false
            spinnerIndex = 0
        } else {
            queueEffect = desiredQueueEffect
            shimmerPhase = 0
            blinkElapsed = 0
            blinkOn = queueEffect == .blink
        }
        updateQueueDisplayImage()
    }

    private func loadQueueImage(named name: String, extension fileExtension: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: fileExtension),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = true
        let targetHeight = NSStatusBar.system.thickness * MenuBarMetrics.queueIconHeightScale
        let aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
        image.size = NSSize(width: targetHeight * aspect, height: targetHeight)
        return image
    }

    private func tintedImage(_ image: NSImage, color: NSColor) -> NSImage {
        let target = NSImage(size: image.size)
        target.lockFocus()
        let rect = NSRect(origin: .zero, size: image.size)
        (color.usingColorSpace(.sRGB) ?? color).set()
        rect.fill()
        image.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
        target.unlockFocus()
        target.isTemplate = false
        return target
    }

    private func updateQueueDisplayImage() {
        guard let baseImage = queueBaseImage else {
            return
        }
        let displayPercent = Settings.devQueueIconOverrideEnabled
            ? (Settings.devQueueIconPercent ?? Settings.percentMin)
            : currentPercent
        let alertColor = currentForceWhite ? NSColor.white : MenuBarRenderer.colorForPercent(displayPercent)
        let baseTint = paused
            ? NSColor.white.withAlphaComponent(MenuBarMetrics.pausedIconAlpha)
            : NSColor.white
        let tinted = tintedImage(baseImage, color: baseTint)
        switch queueEffect {
        case .none:
            queueDisplayImage = tinted
        case .shimmer:
            queueDisplayImage = shimmeredImage(tinted, phase: shimmerPhase, shimmerColor: alertColor)
        case .blink:
            let blinkTint = blinkOn ? alertColor : baseTint
            queueDisplayImage = tintedImage(baseImage, color: blinkTint)
        }
    }

    private func shimmeredImage(_ image: NSImage, phase: CGFloat, shimmerColor: NSColor) -> NSImage {
        let size = image.size
        let target = NSImage(size: size)
        target.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)

        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.setBlendMode(.sourceAtop)
            let highlight = shimmerColor.withAlphaComponent(0.9).cgColor
            let transparent = shimmerColor.withAlphaComponent(0).cgColor
            let colors: [CGColor] = [
                transparent,
                highlight,
                transparent
            ]
            let locations: [CGFloat] = [0, 0.5, 1]
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: locations
            ) {
                let bandWidth = size.width * 1.8
                let travel = size.width + bandWidth
                let offset = -bandWidth + (phase * travel)
                let start = CGPoint(x: offset, y: 0)
                let end = CGPoint(x: offset + bandWidth, y: size.height)
                context.drawLinearGradient(
                    gradient,
                    start: start,
                    end: end,
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            }
            context.restoreGState()
        }

        target.unlockFocus()
        target.isTemplate = false
        return target
    }

    private static func colorForPercent(_ percent: Double) -> NSColor {
        let clamped = Settings.clampPercent(percent)
        let midpoint = Settings.percentMax / 2.0
        if clamped <= midpoint {
            let t = clamped / midpoint
            // 0% -> red, 50% -> yellow
            return NSColor(srgbRed: 1.0, green: CGFloat(t), blue: 0.0, alpha: 1.0)
        }
        // 50% -> yellow, 100% -> white
        let t = (clamped - midpoint) / midpoint
        return NSColor(srgbRed: 1.0, green: 1.0, blue: CGFloat(t), alpha: 1.0)
    }

    private func makeFractionText(numerator: Int, denominator: Int, baseFont: NSFont, color: NSColor) -> NSAttributedString {
        let smallFont = NSFont.menuBarFont(ofSize: baseFont.pointSize * MenuBarMetrics.fractionFontScale)
        let upOffset = baseFont.capHeight * MenuBarMetrics.fractionUpOffsetScale
        let downOffset = -baseFont.capHeight * MenuBarMetrics.fractionDownOffsetScale

        let result = NSMutableAttributedString()
        let num = NSAttributedString(string: "\(numerator)", attributes: [
            .font: smallFont,
            .foregroundColor: color,
            .baselineOffset: upOffset
        ])
        let slash = NSAttributedString(string: "/", attributes: [
            .font: baseFont,
            .foregroundColor: color
        ])
        let den = NSAttributedString(string: "\(denominator)", attributes: [
            .font: smallFont,
            .foregroundColor: color,
            .baselineOffset: downOffset
        ])
        result.append(num)
        result.append(slash)
        result.append(den)
        return result
    }

    private func dimmedLabelColor() -> NSColor {
        let appearance = statusItem.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        if match == .darkAqua {
            return NSColor(white: MenuBarMetrics.dimmedDarkWhite, alpha: 1.0)
        }
        return NSColor(white: MenuBarMetrics.dimmedLightWhite, alpha: 1.0)
    }

    private func spinnerAttachment(
        glyph: String,
        font: NSFont,
        baseFont: NSFont,
        color: NSColor,
        verticalOffset: CGFloat,
        applyNudge: Bool
    ) -> NSTextAttachment {
        var maxSize = CGSize(width: 0, height: 0)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font
        ]
        let size = (glyph as NSString).size(withAttributes: attributes)
        let amplitude = baseFont.pointSize * MenuBarMetrics.spinnerBounceAmplitudeScale
        maxSize.width = max(maxSize.width, size.width)
        maxSize.height = max(maxSize.height, size.height + amplitude * 2)

        let image = NSImage(size: maxSize)
        image.isTemplate = false
        image.lockFocus()
        let drawSize = (glyph as NSString).size(withAttributes: attributes)
        let x = (maxSize.width - drawSize.width) / 2.0
        let y = (maxSize.height - drawSize.height) / 2.0 + verticalOffset
        let drawRect = NSRect(x: x, y: y, width: drawSize.width, height: drawSize.height)
        (glyph as NSString).draw(in: drawRect, withAttributes: [
            .font: font,
            .foregroundColor: color.usingColorSpace(NSColorSpace.sRGB) ?? color
        ])
        image.unlockFocus()

        let attachment = NSTextAttachment()
        attachment.image = image
        let center = (baseFont.ascender + baseFont.descender) / 2.0
        let nudge = applyNudge ? (baseFont.pointSize * MenuBarMetrics.spinnerNudgeScale) : 0
        let attachmentY = center - maxSize.height / 2.0 - nudge
        attachment.bounds = NSRect(x: 0, y: attachmentY, width: maxSize.width, height: maxSize.height)
        return attachment
    }

    private func queueIconAttachment(image: NSImage, baseFont: NSFont) -> NSTextAttachment {
        let attachment = NSTextAttachment()
        attachment.image = image
        let center = (baseFont.ascender + baseFont.descender) / 2.0
        let offset = baseFont.pointSize * MenuBarMetrics.queueIconVerticalOffsetScale
        let attachmentY = center - image.size.height / 2.0 - offset
        attachment.bounds = NSRect(x: 0, y: attachmentY, width: image.size.width, height: image.size.height)
        return attachment
    }
}
