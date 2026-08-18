import SwiftUI
import UIKit
import IronSource

@MainActor
final class AdsManager: NSObject, ObservableObject {
    static let shared = AdsManager()

    static let appKey = "27ad6d08d"
    static let bannerAdUnitID = "3enr8l0rqws9op9z"
    static let interstitialAdUnitID = "y23pc99ate029uga"

    @Published private(set) var isInitialized = false

    private var interstitialAd: LPMInterstitialAd?
    private var successfulGenerationsSinceLastInterstitial = 0
    private var isInitializing = false

    private override init() {
        super.init()
    }

    func initializeIfNeeded() {
        guard !isInitialized, !isInitializing else { return }
        isInitializing = true

        let request = LPMInitRequestBuilder(appKey: Self.appKey).build()
        LevelPlay.initWith(request) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                self.isInitializing = false

                guard error == nil else {
                    self.isInitialized = false
                    return
                }

                self.isInitialized = true
                self.configureInterstitial()
            }
        }
    }

    func recordSuccessfulGeneration() {
        guard isInitialized else { return }
        successfulGenerationsSinceLastInterstitial += 1

        // Keep full-screen ads infrequent and tied to a natural completed action.
        guard successfulGenerationsSinceLastInterstitial >= 5 else { return }
        guard let interstitialAd, interstitialAd.isAdReady() else { return }
        guard let presenter = Self.topViewController() else { return }

        successfulGenerationsSinceLastInterstitial = 0
        interstitialAd.showAd(viewController: presenter, placementName: nil)
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
    func didLoadAd(with adInfo: LPMAdInfo) {}
    func didFailToLoadAd(withAdUnitId adUnitId: String, error: Error) {}
    func didChangeAdInfo(_ adInfo: LPMAdInfo) {}
    func didDisplayAd(with adInfo: LPMAdInfo) {}

    func didFailToDisplayAd(with adInfo: LPMAdInfo, error: Error) {
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
        bannerAd?.destroy()
    }

    func didLoadAd(with adInfo: LPMAdInfo) {}
    func didFailToLoadAd(withAdUnitId adUnitId: String, error: Error) {}
    func didClickAd(with adInfo: LPMAdInfo) {}
    func didDisplayAd(with adInfo: LPMAdInfo) {}
    func didFailToDisplayAd(with adInfo: LPMAdInfo, error: Error) {}
    func didLeaveApp(with adInfo: LPMAdInfo) {}
    func didExpandAd(with adInfo: LPMAdInfo) {}
    func didCollapseAd(with adInfo: LPMAdInfo) {}
}
