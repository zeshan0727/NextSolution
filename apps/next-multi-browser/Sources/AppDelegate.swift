import UIKit

final class MultiBrowserTabBarController: UITabBarController {
    private let profileStore: BrowserProfileStore
    private let browserController: BrowserGridViewController
    private let browserNavigationController: UINavigationController

    init() {
        let profileStore = BrowserProfileStore.shared
        let browserController = BrowserGridViewController(profileStore: profileStore)
        self.profileStore = profileStore
        self.browserController = browserController
        self.browserNavigationController = UINavigationController(rootViewController: browserController)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        browserNavigationController.navigationBar.prefersLargeTitles = false
        browserNavigationController.tabBarItem = UITabBarItem(
            title: "Browsers",
            image: UIImage(systemName: "square.grid.2x2"),
            selectedImage: UIImage(systemName: "square.grid.2x2.fill")
        )

        let profilesController = BrowserProfilesViewController(
            profileStore: profileStore
        ) { [weak self] profileIndex, openGoogleSignIn in
            self?.openProfile(profileIndex, openGoogleSignIn: openGoogleSignIn)
        }
        let profilesNavigationController = UINavigationController(rootViewController: profilesController)
        profilesNavigationController.navigationBar.prefersLargeTitles = false
        profilesNavigationController.tabBarItem = UITabBarItem(
            title: "Profiles",
            image: UIImage(systemName: "person.3"),
            selectedImage: UIImage(systemName: "person.3.fill")
        )

        viewControllers = [browserNavigationController, profilesNavigationController]
    }

    private func openProfile(_ profileIndex: Int, openGoogleSignIn: Bool) {
        selectedIndex = 0
        browserNavigationController.popToRootViewController(animated: false)
        DispatchQueue.main.async { [weak self] in
            self?.browserController.openProfile(profileIndex, openGoogleSignIn: openGoogleSignIn)
        }
    }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = MultiBrowserTabBarController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        var backgroundTask = UIBackgroundTaskIdentifier.invalid
        let finish = {
            guard backgroundTask != .invalid else { return }
            application.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
        backgroundTask = application.beginBackgroundTask(
            withName: "Save Browser Profiles",
            expirationHandler: finish
        )
        BrowserProfileStore.shared.flushAllProfiles(completion: finish)
    }

    func applicationWillTerminate(_ application: UIApplication) {
        BrowserProfileStore.shared.flushAllProfiles()
    }
}
