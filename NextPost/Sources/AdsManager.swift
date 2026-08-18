import SwiftUI
import UIKit
import IronSource

@MainActor
final class AdsManager: NSObject, ObservableObject {
    static let shared = AdsManager()

    static let appKey = "27ad6d08d"
    static let bannerAdUnitID = "3enr8l0rqws9op9z"
    static let interstitialAdUnitID = "y23pc99ate029uga"

    // This branch is a diagnostic/test build. Keep production ad objects disabled
    // while the official LevelPlay test suite owns the SDK session.
    static let testSuiteEnabled = true

    @Published private(set) var isInitialized = false
    @Published private(set) var statusText = "Starting LevelPlay…"

    private var interstitialAd: LPMInterstitialAd?
    private var successfulGenerationsSinceLastInterstitial = 0
    private var isInitializing = false
    private var didLaunchTestSuite = false
    private var testSuiteLaunchAttempts = 0

    private override init() {
        super.init()
    }

    func initializeIfNeeded() {
        guard !isInitialized, !isInitializing else { return }
        isInitializing = true
        statusText = "Initializing LevelPlay…"

        if Self.testSuiteEnabled {
            // Unity requires this metadata to be set before initialization.
            LevelPlay.setMetaDataWithKey("is_test_suite", value: "enable")
        }

        let request = LPMInitRequestBuilder(appKey: Self.appKey).build()
        LevelPlay.initWith(request) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                self.isInitializing = false

                if let error {
                    self.isInitialized = false
                    self.statusText = "LevelPlay init failed: \(error.localizedDescription)"
                    print("[NextPost][LevelPlay] init failed: \(error)")
                    return
                }

                self.isInitialized = true
                self.statusText = Self.testSuiteEnabled
                    ? "LevelPlay ready — opening test suite…"
                    : "LevelPlay ready"
                print("[NextPost][LevelPlay] initialized")

                if Self.testSuiteEnabled {
                    self.launchTestSuiteWhenReady()
                } else {
                    self.configureInterstitial()
                }
            }
        }
    }

    func recordSuccessfulGeneration() {
        guard !Self.testSuiteEnabled else { return }
        guard isInitialized else { return }
        successfulGenerationsSinceLastInterstitial += 1

        guard successfulGenerationsSinceLastInterstitial >= 5 else { return }
        guard let interstitialAd, interstitialAd.isAdReady() else { return }
        guard let presenter = Self.topViewController() else { return }

        successfulGenerationsSinceLastInterstitial = 0
        interstitialAd.showAd(viewController: presenter, placementName: nil)
    }

    private func launchTestSuiteWhenReady() {
        guard Self.testSuiteEnabled, isInitialized, !didLaunchTestSuite else { return }

        guard let presenter = Self.topViewController() else {
            testSuiteLaunchAttempts += 1
            guard testSuiteLaunchAttempts <= 20 else {
                statusText = "LevelPlay ready — reopen app to launch test suite"
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.launchTestSuiteWhenReady()
            }
            return
        }

        didLaunchTestSuite = true
        statusText = "LevelPlay test suite opened"
        LevelPlay.launchTestSuite(presenter)
    }

    private func configureInterstitial() {
        let ad = LPMInterstitialAd(adUnitId: Self.interstitialAdUnitID)
        ad.setDelegate(self)
        interstitialAd = ad
        ad.loadAd()
    }

    private static func topViewController() -> UIViewController? {
        let root = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .rootViewController
        return topViewController(from: root)
    }

    private static func topViewController(from root: UIViewController?) -> UIViewController? {
        if let nav = root as? UINavigationController {
            return topViewController(from: nav.visibleViewController)
        }
        if let tab = root as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topViewController(from: presented)
        }
        return root
    }
}

extension AdsManager: @preconcurrency LPMInterstitialAdDelegate {
    func didLoadAd(with adInfo: LPMAdInfo) {
        print("[NextPost][LevelPlay] interstitial loaded")
    }

    func didFailToLoadAd(withAdUnitId adUnitId: String, error: Error) {
        print("[NextPost][LevelPlay] interstitial load failed \(adUnitId): \(error)")
    }

    func didChangeAdInfo(_ adInfo: LPMAdInfo) {}
    func didDisplayAd(with adInfo: LPMAdInfo) {}

    func didFailToDisplayAd(with adInfo: LPMAdInfo, error: Error) {
        print("[NextPost][LevelPlay] interstitial display failed: \(error)")
        interstitialAd?.loadAd()
    }

    func didClickAd(with adInfo: LPMAdInfo) {}

    func didCloseAd(with adInfo: LPMAdInfo) {
        interstitialAd?.loadAd()
    }
}

struct LevelPlayBannerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> LevelPlayBannerHostController {
        LevelPlayBannerHostController()
    }

    func updateUIViewController(_ uiViewController: LevelPlayBannerHostController, context: Context) {
        uiViewController.loadIfReady()
    }
}

@MainActor
final class LevelPlayBannerHostController: UIViewController, @preconcurrency LPMBannerAdViewDelegate {
    private var bannerAd: LPMBannerAdView?
    private var retryWorkItem: DispatchWorkItem?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        loadIfReady()
    }

    func loadIfReady() {
        guard !AdsManager.testSuiteEnabled else { return }
        guard bannerAd == nil else { return }

        guard AdsManager.shared.isInitialized else {
            retryWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                self?.loadIfReady()
            }
            retryWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
            return
        }

        guard let bannerSize = LPMAdSize.createAdaptive() else { return }

        let config = LPMBannerAdViewConfigBuilder()
            .set(adSize: bannerSize)
            .set(placementName: "NextPostBottom")
            .build()

        let banner = LPMBannerAdView(adUnitId: AdsManager.bannerAdUnitID, config: config)
        banner.setDelegate(self)
        banner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(banner)

        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            banner.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            banner.widthAnchor.constraint(equalToConstant: CGFloat(bannerSize.width)),
            banner.heightAnchor.constraint(equalToConstant: CGFloat(bannerSize.height))
        ])

        bannerAd = banner
        banner.loadAd(with: self)
    }

    deinit {
        retryWorkItem?.cancel()
        if let bannerAd {
            Task { @MainActor in
                bannerAd.destroy()
            }
        }
    }

    func didLoadAd(with adInfo: LPMAdInfo) {
        print("[NextPost][LevelPlay] banner loaded")
    }

    func didFailToLoadAd(withAdUnitId adUnitId: String, error: Error) {
        print("[NextPost][LevelPlay] banner load failed \(adUnitId): \(error)")
    }

    func didClickAd(with adInfo: LPMAdInfo) {}
    func didDisplayAd(with adInfo: LPMAdInfo) {}
    func didFailToDisplayAd(with adInfo: LPMAdInfo, error: Error) {
        print("[NextPost][LevelPlay] banner display failed: \(error)")
    }
    func didLeaveApp(with adInfo: LPMAdInfo) {}
    func didExpandAd(with adInfo: LPMAdInfo) {}
    func didCollapseAd(with adInfo: LPMAdInfo) {}
}
