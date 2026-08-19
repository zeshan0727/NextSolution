import SwiftUI
import UIKit
import IronSource

@MainActor
final class AdsManager: NSObject {
    static let shared = AdsManager()

    static let appKey = "27ad6d08d"
    static let bannerAdUnitID = "3enr810rqws9op9z"
    static let interstitialAdUnitID = "y23pc99ate029uga"

    private(set) var isInitialized = false
    private(set) var lastInitError: String?
    private var isInitializing = false
    private var interstitialAd: LPMInterstitialAd?
    private var generationsSinceInterstitial = 0
    private var interstitialRetryWorkItem: DispatchWorkItem?

    private override init() {
        super.init()
    }

    func initializeIfNeeded() {
        guard !isInitialized, !isInitializing else { return }
        isInitializing = true
        lastInitError = nil

        // Next Post is a general-audience utility, not a child-directed app.
        LPMPrivacySettings.setCOPPA(false)

        // Keep adapter diagnostics enabled in this test build so failures can be
        // identified from device logs. Disable before the App Store release.
        LevelPlay.setAdaptersDebug(true)

        let request = LPMInitRequestBuilder(appKey: Self.appKey).build()
        LevelPlay.initWith(request) { [weak self] _, error in
            Task { @MainActor in
                guard let self else { return }
                self.isInitializing = false

                if let error {
                    self.isInitialized = false
                    self.lastInitError = error.localizedDescription
                    print("[NextPost][LevelPlay] init failed: \(error)")
                    self.scheduleInitializationRetry()
                    return
                }

                self.isInitialized = true
                self.lastInitError = nil
                print("[NextPost][LevelPlay] initialized with app key \(Self.appKey)")
                self.configureInterstitial()
            }
        }
    }

    func recordSuccessfulGeneration() {
        guard isInitialized else { return }
        generationsSinceInterstitial += 1

        guard generationsSinceInterstitial >= 5 else { return }
        guard let readyInterstitial = interstitialAd, readyInterstitial.isAdReady() else {
            if interstitialAd == nil {
                configureInterstitial()
            } else {
                interstitialAd?.loadAd()
            }
            return
        }
        guard let presenter = Self.topViewController() else { return }

        generationsSinceInterstitial = 0
        readyInterstitial.showAd(viewController: presenter, placementName: nil)
    }

    private func configureInterstitial() {
        guard isInitialized else { return }
        interstitialRetryWorkItem?.cancel()

        if interstitialAd == nil {
            let ad = LPMInterstitialAd(adUnitId: Self.interstitialAdUnitID)
            ad.setDelegate(self)
            interstitialAd = ad
        }

        interstitialAd?.loadAd()
    }

    private func scheduleInitializationRetry() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.initializeIfNeeded()
        }
    }

    private func scheduleInterstitialRetry() {
        interstitialRetryWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.interstitialAd?.loadAd()
        }
        interstitialRetryWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: item)
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
        scheduleInterstitialRetry()
    }

    func didChangeAdInfo(_ adInfo: LPMAdInfo) {}

    func didDisplayAd(with adInfo: LPMAdInfo) {
        print("[NextPost][LevelPlay] interstitial displayed")
    }

    func didFailToDisplayAd(with adInfo: LPMAdInfo, error: Error) {
        print("[NextPost][LevelPlay] interstitial display failed: \(error)")
        scheduleInterstitialRetry()
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
    private var retryCount = 0

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.text = "Ad loading…"
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        loadIfReady()
    }

    func loadIfReady() {
        guard bannerAd == nil else { return }

        AdsManager.shared.initializeIfNeeded()
        guard AdsManager.shared.isInitialized else {
            statusLabel.text = AdsManager.shared.lastInitError.map { "Ad SDK error: \($0)" } ?? "Initializing ad SDK…"
            scheduleRetry(after: 1)
            return
        }

        guard let bannerSize = LPMAdSize.createAdaptive() else {
            statusLabel.text = "Could not create banner size"
            return
        }

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
        statusLabel.text = "Requesting LevelPlay banner…"
        banner.loadAd(with: self)
    }

    private func scheduleRetry(after seconds: TimeInterval) {
        retryWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.loadIfReady()
        }
        retryWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
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
        retryCount = 0
        statusLabel.isHidden = true
        print("[NextPost][LevelPlay] banner loaded")
    }

    func didFailToLoadAd(withAdUnitId adUnitId: String, error: Error) {
        statusLabel.isHidden = false
        statusLabel.text = "Banner unavailable: \(error.localizedDescription)"
        print("[NextPost][LevelPlay] banner load failed \(adUnitId): \(error)")

        guard retryCount < 2 else { return }
        retryCount += 1
        bannerAd?.destroy()
        bannerAd = nil
        scheduleRetry(after: 30)
    }

    func didClickAd(with adInfo: LPMAdInfo) {}

    func didDisplayAd(with adInfo: LPMAdInfo) {
        statusLabel.isHidden = true
        print("[NextPost][LevelPlay] banner displayed")
    }

    func didFailToDisplayAd(with adInfo: LPMAdInfo, error: Error) {
        statusLabel.isHidden = false
        statusLabel.text = "Banner display failed: \(error.localizedDescription)"
        print("[NextPost][LevelPlay] banner display failed: \(error)")
    }

    func didLeaveApp(with adInfo: LPMAdInfo) {}
    func didExpandAd(with adInfo: LPMAdInfo) {}
    func didCollapseAd(with adInfo: LPMAdInfo) {}
}
