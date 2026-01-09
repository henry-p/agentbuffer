import AppKit

final class PopoverRootController: NSViewController {
    private let mainController: MainPopoverController
    private let settingsController: SettingsPopoverController
    private var currentController: NSViewController?

    init(mainController: MainPopoverController, settingsController: SettingsPopoverController) {
        self.mainController = mainController
        self.settingsController = settingsController
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView(
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
        showMain()
    }

    func showMain() {
        switchTo(controller: mainController)
    }

    func showSettings() {
        switchTo(controller: settingsController)
    }

    private func switchTo(controller: NSViewController) {
        if currentController === controller {
            return
        }
        if let current = currentController {
            current.view.removeFromSuperview()
            current.removeFromParent()
        }
        addChild(controller)
        controller.view.frame = view.bounds
        controller.view.autoresizingMask = [.width, .height]
        view.addSubview(controller.view)
        currentController = controller
    }
}
