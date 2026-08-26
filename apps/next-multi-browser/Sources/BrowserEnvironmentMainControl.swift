import UIKit

final class BrowserEnvironmentAutoRandomizeCoordinator {
    static let shared = BrowserEnvironmentAutoRandomizeCoordinator()

    private static let intervalDefaultsKey = "NextMultiBrowser.autoRandomizeEnvironmentSeconds"
    private static let buttonAccessibilityLabel = "Random Environment"

    private weak var browserController: BrowserGridViewController?
    private var timer: Timer?
    private var isApplicationActive = true

    private var interval: TimeInterval? {
        let value = UserDefaults.standard.double(forKey: Self.intervalDefaultsKey)
        return value > 0 ? value : nil
    }

    private init() {}

    func install(on controller: BrowserGridViewController) {
        browserController = controller
        refreshMainButton()
        restartTimer()
    }

    func applicationDidBecomeActive() {
        isApplicationActive = true
        restartTimer()
    }

    func applicationDidEnterBackground() {
        isApplicationActive = false
        timer?.invalidate()
        timer = nil
    }

    private func refreshMainButton() {
        guard let controller = browserController else { return }

        var currentItems = controller.navigationItem.leftBarButtonItems ?? []
        if currentItems.isEmpty, let existing = controller.navigationItem.leftBarButtonItem {
            currentItems = [existing]
        }
        currentItems.removeAll { $0.accessibilityLabel == Self.buttonAccessibilityLabel }

        let environmentItem = UIBarButtonItem(
            image: UIImage(systemName: "shuffle"),
            menu: makeEnvironmentMenu()
        )
        environmentItem.accessibilityLabel = Self.buttonAccessibilityLabel
        environmentItem.accessibilityHint = "Randomize all profile environments now or choose an automatic randomize timer."

        currentItems.append(environmentItem)
        controller.navigationItem.leftBarButtonItems = currentItems
    }

    private func makeEnvironmentMenu() -> UIMenu {
        let randomizeNow = UIAction(
            title: "Randomize All Now",
            image: UIImage(systemName: "shuffle")
        ) { [weak self] _ in
            self?.randomizeAll(showFeedback: true)
        }

        let choices: [(String, TimeInterval?)] = [
            ("Off", nil),
            ("1 minute", 60),
            ("2 minutes", 120),
            ("3 minutes", 180),
            ("5 minutes", 300),
            ("10 minutes", 600)
        ]

        let currentInterval = interval
        let timerActions = choices.map { title, value in
            UIAction(
                title: title,
                state: intervalsMatch(value, currentInterval) ? .on : .off
            ) { [weak self] _ in
                self?.setInterval(value)
            }
        }

        let currentTitle = currentInterval.map(formatMinutes) ?? "Off"
        let timerMenu = UIMenu(
            title: "Auto Randomize • \(currentTitle)",
            image: UIImage(systemName: "timer"),
            children: timerActions
        )

        return UIMenu(
            title: "Random Environment",
            children: [randomizeNow, timerMenu]
        )
    }

    private func setInterval(_ newInterval: TimeInterval?) {
        if let newInterval {
            UserDefaults.standard.set(newInterval, forKey: Self.intervalDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.intervalDefaultsKey)
        }
        restartTimer()
        refreshMainButton()
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = nil

        guard isApplicationActive, let interval else { return }

        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.randomizeAll(showFeedback: false)
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func randomizeAll(showFeedback: Bool) {
        let environments = BrowserProfileStore.shared.randomizeAllEnvironments()
        guard environments.count == BrowserProfileStore.profileCount else {
            if showFeedback {
                showRandomizeError()
            }
            return
        }

        if showFeedback {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func showRandomizeError() {
        guard let controller = browserController,
              controller.presentedViewController == nil else { return }

        let alert = UIAlertController(
            title: "Could Not Randomize",
            message: "The profile environments could not be generated. Please try again.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        controller.present(alert, animated: true)
    }

    private func intervalsMatch(_ lhs: TimeInterval?, _ rhs: TimeInterval?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (a?, b?): return abs(a - b) < 0.5
        default: return false
        }
    }

    private func formatMinutes(_ interval: TimeInterval) -> String {
        "\(Int(interval / 60))m"
    }
}

extension BrowserGridViewController {
    func installMainEnvironmentControls() {
        BrowserEnvironmentAutoRandomizeCoordinator.shared.install(on: self)
    }
}
