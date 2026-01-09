import AppKit
import CoreImage

private enum InfoLayout {
    static let horizontalInset: CGFloat = PopoverLayout.horizontalInset
    static let topInset: CGFloat = PopoverLayout.topInset
    static let bottomInset: CGFloat = PopoverLayout.bottomInset
    static let headerSpacing: CGFloat = 8
    static let contentSpacing: CGFloat = 16
    static let thumbHeight: CGFloat = 96
}

final class InfoPopoverController: NSViewController {
    var onBack: (() -> Void)?

    private let headerTitle = NSTextField(labelWithString: "Efficiency")
    private let backButton = PaddedButton(title: "Back", target: nil, action: nil)
    private let headerRow = NSStackView()
    private let thumbImageView = NSImageView()
    private let messageLabel = NSTextField(labelWithString: "—")
    private let contentStack = NSStackView()

    private var pressureColor = NSColor.labelColor
    private var pressurePercent: Double = Settings.percentMin
    private var thumbBaseImage: NSImage?
    private lazy var thumbCiContext = CIContext(options: nil)

    override func loadView() {
        view = CursorRectsView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: PopoverLayout.width,
                height: PopoverLayout.height
            )
        )
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupContent()
        syncContent()
        updateCursorTargets()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateCursorTargets()
    }

    func update(pressureColor: NSColor, pressurePercent: Double) {
        let normalizedColor = pressureColor.usingColorSpace(.sRGB) ?? pressureColor
        let normalizedPercent = Settings.clampPercent(pressurePercent)
        let changed = !self.pressureColor.isEqual(normalizedColor)
            || abs(self.pressurePercent - normalizedPercent) > 0.001
        self.pressureColor = normalizedColor
        self.pressurePercent = normalizedPercent
        if isViewLoaded && changed {
            syncContent()
        }
    }

    private func setupContent() {
        backButton.applyStyle(.standard)
        backButton.target = self
        backButton.action = #selector(backTapped)
        if let chevron = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            backButton.image = chevron.withSymbolConfiguration(config)
            backButton.imagePosition = .imageLeading
            backButton.imageHugsTitle = true
        }

        headerTitle.font = .systemFont(ofSize: NSFont.systemFontSize + 2, weight: .semibold)
        headerTitle.textColor = .labelColor
        headerTitle.alignment = .left

        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = InfoLayout.headerSpacing
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addArrangedSubview(backButton)
        headerRow.addArrangedSubview(headerSpacer)
        headerRow.addArrangedSubview(headerTitle)

        thumbImageView.translatesAutoresizingMaskIntoConstraints = false
        thumbImageView.imageScaling = .scaleProportionallyUpOrDown

        messageLabel.font = .systemFont(ofSize: NSFont.systemFontSize + 1, weight: .medium)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.alignment = .center
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 0
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        contentStack.orientation = .vertical
        contentStack.alignment = .centerX
        contentStack.spacing = InfoLayout.contentSpacing
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(thumbImageView)
        contentStack.addArrangedSubview(messageLabel)

        view.addSubview(headerRow)
        view.addSubview(contentStack)

        NSLayoutConstraint.activate([
            headerRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: InfoLayout.horizontalInset),
            headerRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -InfoLayout.horizontalInset),
            headerRow.topAnchor.constraint(equalTo: view.topAnchor, constant: InfoLayout.topInset),

            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: InfoLayout.horizontalInset),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -InfoLayout.horizontalInset),
            contentStack.topAnchor.constraint(equalTo: headerRow.bottomAnchor, constant: InfoLayout.contentSpacing),
            contentStack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -InfoLayout.bottomInset),

            thumbImageView.heightAnchor.constraint(equalToConstant: InfoLayout.thumbHeight)
        ])
    }

    private func syncContent() {
        updateThumbImage()
        messageLabel.stringValue = messageText(for: pressurePercent)
    }

    private func updateThumbImage() {
        guard let baseImage = loadThumbBaseImage() else {
            thumbImageView.image = nil
            return
        }
        let targetHeight = InfoLayout.thumbHeight
        let aspect = baseImage.size.height > 0 ? baseImage.size.width / baseImage.size.height : 1
        let targetSize = NSSize(width: targetHeight * aspect, height: targetHeight)
        let sized = NSImage(size: targetSize)
        sized.lockFocus()
        baseImage.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .sourceOver, fraction: 1.0)
        sized.unlockFocus()
        let colored = colorizedThumbImage(sized, fillColor: pressureColor)
        let rotation = rotationDegrees(for: pressurePercent)
        let rotated = rotatedImage(colored, degrees: rotation)
        thumbImageView.image = rotated
    }

    private func messageText(for percent: Double) -> String {
        if percent >= 99.5 {
            return "All agents running. You're absolutely crushing it."
        }
        if percent >= 60 {
            return "Not bad, but you could do better. Feed those idle agents."
        }
        return "Oof. Efficiency is hurting. You should really do something about it."
    }

    private func rotationDegrees(for percent: Double) -> CGFloat {
        let clamped = Settings.clampPercent(percent)
        let t = 1.0 - (clamped / Settings.percentMax)
        return -CGFloat(t * 180.0)
    }

    private func colorizedThumbImage(_ image: NSImage, fillColor: NSColor) -> NSImage {
        guard let data = image.tiffRepresentation,
              let ciImage = CIImage(data: data) else {
            return image
        }
        let filter = CIFilter(name: "CIFalseColor")
        let normalized = fillColor.usingColorSpace(.sRGB) ?? fillColor
        filter?.setValue(ciImage, forKey: kCIInputImageKey)
        filter?.setValue(CIColor(color: NSColor.black), forKey: "inputColor0")
        filter?.setValue(CIColor(color: normalized), forKey: "inputColor1")
        guard let output = filter?.outputImage,
              let cgImage = thumbCiContext.createCGImage(output, from: output.extent) else {
            return image
        }
        let result = NSImage(cgImage: cgImage, size: image.size)
        result.isTemplate = false
        return result
    }

    private func rotatedImage(_ image: NSImage, degrees: CGFloat) -> NSImage {
        let radians = Double(degrees) * Double.pi / 180.0
        let width = image.size.width
        let height = image.size.height
        let cosValue = abs(cos(radians))
        let sinValue = abs(sin(radians))
        let newSize = NSSize(
            width: width * CGFloat(cosValue) + height * CGFloat(sinValue),
            height: width * CGFloat(sinValue) + height * CGFloat(cosValue)
        )
        let rotated = NSImage(size: newSize)
        rotated.lockFocus()
        guard let context = NSGraphicsContext.current?.cgContext else {
            image.draw(
                in: NSRect(
                    x: (newSize.width - width) / 2.0,
                    y: (newSize.height - height) / 2.0,
                    width: width,
                    height: height
                ),
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0
            )
            rotated.unlockFocus()
            return rotated
        }
        context.translateBy(x: newSize.width / 2.0, y: newSize.height / 2.0)
        context.rotate(by: CGFloat(radians))
        let drawRect = CGRect(x: -width / 2.0, y: -height / 2.0, width: width, height: height)
        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        rotated.unlockFocus()
        rotated.isTemplate = false
        return rotated
    }

    private func loadThumbBaseImage() -> NSImage? {
        if let cached = thumbBaseImage {
            return cached
        }
        guard let url = Bundle.module.url(forResource: "thumb", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = false
        thumbBaseImage = image
        return image
    }

    private func updateCursorTargets() {
        guard let contentView = view as? CursorRectsView else {
            return
        }
        contentView.cursorTargets = [backButton]
        contentView.window?.invalidateCursorRects(for: contentView)
    }

    @objc private func backTapped() {
        Telemetry.trackUi("ui.info_back_clicked")
        onBack?()
    }
}
