import AppKit

final class PopoverRootController: NSViewController {
    private let mainController: MainPopoverController
    private let settingsController: SettingsPopoverController
    private let infoController: InfoPopoverController
    private var currentController: NSViewController?
    private let transitionDuration: TimeInterval = 0.18

    init(
        mainController: MainPopoverController,
        settingsController: SettingsPopoverController,
        infoController: InfoPopoverController
    ) {
        self.mainController = mainController
        self.settingsController = settingsController
        self.infoController = infoController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let effectView = NSVisualEffectView(
            frame: NSRect(
                x: 0,
                y: 0,
                width: PopoverLayout.width,
                height: PopoverLayout.height
            )
        )
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        view = effectView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        showMain()
    }

    func showMain() {
        switchTo(controller: mainController)
    }

    func showSettings() {
        switchTo(controller: settingsController)
    }

    func showInfo() {
        switchTo(controller: infoController)
    }

    private func switchTo(controller: NSViewController) {
        if currentController === controller {
            return
        }
        guard let outgoing = currentController else {
            addChild(controller)
            controller.view.frame = view.bounds
            controller.view.autoresizingMask = [.width, .height]
            view.addSubview(controller.view)
            currentController = controller
            return
        }

        addChild(controller)
        currentController = controller

        let halfDuration = transitionDuration / 2
        NSAnimationContext.runAnimationGroup { context in
            context.duration = halfDuration
            outgoing.view.animator().alphaValue = 0
        } completionHandler: { [weak self, weak outgoing] in
            guard let self, let outgoing else {
                return
            }
            outgoing.view.removeFromSuperview()
            outgoing.view.alphaValue = 1
            outgoing.removeFromParent()

            let incomingView = controller.view
            incomingView.frame = self.view.bounds
            incomingView.autoresizingMask = [.width, .height]
            incomingView.alphaValue = 0
            self.view.addSubview(incomingView)
            incomingView.layoutSubtreeIfNeeded()
            incomingView.displayIfNeeded()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = halfDuration
                incomingView.animator().alphaValue = 1
            }
        }
    }
}
