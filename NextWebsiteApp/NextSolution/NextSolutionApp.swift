import SwiftUI
import WebKit
import UIKit

@main
struct NextSolutionApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

enum WebsiteTab: String, CaseIterable, Identifiable {
    case home
    case videos
    case tutorials
    case downloads
    case uploads
    case faq

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .videos: return "Videos"
        case .tutorials: return "Tutorials"
        case .downloads: return "Downloads"
        case .uploads: return "Uploads"
        case .faq: return "FAQ"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .videos: return "play.rectangle.fill"
        case .tutorials: return "book.fill"
        case .downloads: return "arrow.down.circle.fill"
        case .uploads: return "icloud.and.arrow.up.fill"
        case .faq: return "questionmark.circle.fill"
        }
    }

    var startURL: URL {
        switch self {
        case .home:
            return URL(string: "https://nextsolution.cc/")!
        case .videos:
            return URL(string: "https://nextsolution.cc/videos.html")!
        case .tutorials:
            return URL(string: "https://nextsolution.cc/#tutorials")!
        case .downloads:
            return URL(string: "https://nextsolution.cc/downloads.html")!
        case .uploads:
            return URL(string: "https://nextsolution.cc/Mega.html")!
        case .faq:
            return URL(string: "https://nextsolution.cc/#faq")!
        }
    }

    var fallbackURL: URL? {
        switch self {
        case .videos:
            return URL(string: "https://nextsolution.cc/videos")
        case .downloads:
            return URL(string: "https://nextsolution.cc/downloads")
        case .uploads:
            return URL(string: "https://nextsolution.cc/Mega")
        default:
            return nil
        }
    }
}

struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

@MainActor
final class BrowserStore: ObservableObject {
    private var models: [WebsiteTab: BrowserModel] = [:]

    init() {
        for tab in WebsiteTab.allCases {
            models[tab] = BrowserModel(startURL: tab.startURL, fallbackURL: tab.fallbackURL)
        }
    }

    func model(for tab: WebsiteTab) -> BrowserModel {
        guard let model = models[tab] else {
            fatalError("Missing browser model for \(tab.rawValue)")
        }
        return model
    }
}

struct ContentView: View {
    @StateObject private var store = BrowserStore()
    @State private var selectedTab: WebsiteTab = .home

    var body: some View {
        BrowserScreen(tab: selectedTab, model: store.model(for: selectedTab))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomBar
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(WebsiteTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 17, weight: .semibold))
                        Text(tab.title)
                            .font(.system(size: 9, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .foregroundStyle(selectedTab == tab ? Color(red: 0.36, green: 0.18, blue: 0.86) : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(.horizontal, 4)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

struct BrowserScreen: View {
    let tab: WebsiteTab
    @ObservedObject var model: BrowserModel

    var body: some View {
        VStack(spacing: 0) {
            header

            if model.isLoading {
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)
                    .tint(Color(red: 0.18, green: 0.48, blue: 1.0))
            }

            ZStack {
                WebsiteWebView(model: model)
                    .background(Color(uiColor: .systemBackground))

                if let errorMessage = model.errorMessage {
                    errorView(message: errorMessage)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(item: $model.sharePayload) { payload in
            ActivityView(items: payload.items)
        }
        .alert("Next Solution", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { isPresented in
                if !isPresented { model.alertMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) {
                model.alertMessage = nil
            }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Next Solution")
                        .font(.headline.weight(.bold))
                    Text(model.pageTitle.isEmpty ? tab.title : model.pageTitle)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.white.opacity(0.82))
                }

                Spacer(minLength: 8)

                Button(action: model.shareCurrentPage) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share page")

                Button(action: model.openExternally) {
                    Image(systemName: "safari")
                }
                .accessibilityLabel("Open in Safari")
            }

            HStack(spacing: 22) {
                Button(action: model.goBack) {
                    Image(systemName: "chevron.backward")
                }
                .disabled(!model.canGoBack)
                .accessibilityLabel("Back")

                Button(action: model.goForward) {
                    Image(systemName: "chevron.forward")
                }
                .disabled(!model.canGoForward)
                .accessibilityLabel("Forward")

                Button(action: model.reload) {
                    Image(systemName: model.isLoading ? "xmark" : "arrow.clockwise")
                }
                .accessibilityLabel(model.isLoading ? "Stop loading" : "Reload")

                Button(action: model.goToStartPage) {
                    Image(systemName: "house")
                }
                .accessibilityLabel("Open tab start page")

                Spacer()

                if model.isDownloading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .tint(.white)
                        Text("Downloading")
                            .font(.caption2.weight(.semibold))
                    }
                } else {
                    Text(model.connectionLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .font(.system(size: 17, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 9)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.42, green: 0.07, blue: 0.80),
                    Color(red: 0.13, green: 0.46, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Page could not load")
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button("Try Again", action: model.retry)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(24)
    }
}

struct WebsiteWebView: UIViewRepresentable {
    @ObservedObject var model: BrowserModel

    func makeUIView(context: Context) -> WKWebView {
        model.loadIfNeeded()
        return model.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

@MainActor
final class BrowserModel: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    let webView: WKWebView

    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var isDownloading = false
    @Published var progress = 0.0
    @Published var pageTitle = ""
    @Published var currentURL: URL?
    @Published var errorMessage: String?
    @Published var alertMessage: String?
    @Published var sharePayload: SharePayload?

    private let startURL: URL
    private let fallbackURL: URL?
    private var didLoad = false
    private var triedFallback = false
    private var observations: [NSKeyValueObservation] = []
    private var downloadDestination: URL?

    var connectionLabel: String {
        guard let host = currentURL?.host else { return "Ready" }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    init(startURL: URL, fallbackURL: URL?) {
        self.startURL = startURL
        self.fallbackURL = fallbackURL

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let preferences = WKPreferences()
        preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.preferences = preferences

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.scrollView.keyboardDismissMode = .interactive
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic

        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshTriggered), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl

        beginObserving()
    }

    deinit {
        observations.forEach { $0.invalidate() }
    }

    func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        load(url: startURL)
    }

    func goBack() {
        guard webView.canGoBack else { return }
        webView.goBack()
    }

    func goForward() {
        guard webView.canGoForward else { return }
        webView.goForward()
    }

    func reload() {
        errorMessage = nil
        if webView.isLoading {
            webView.stopLoading()
        } else if webView.url != nil {
            webView.reload()
        } else {
            load(url: startURL)
        }
    }

    func retry() {
        errorMessage = nil
        if let url = webView.url ?? currentURL {
            load(url: url)
        } else {
            load(url: startURL)
        }
    }

    func goToStartPage() {
        errorMessage = nil
        load(url: startURL)
    }

    func shareCurrentPage() {
        sharePayload = SharePayload(items: [currentURL ?? startURL])
    }

    func openExternally() {
        UIApplication.shared.open(currentURL ?? startURL)
    }

    @objc private func refreshTriggered() {
        errorMessage = nil
        webView.reload()
    }

    private func load(url: URL) {
        var request = URLRequest(url: url)
        request.cachePolicy = .useProtocolCachePolicy
        request.timeoutInterval = 45
        webView.load(request)
    }

    private func beginObserving() {
        observations = [
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in self?.canGoBack = webView.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in self?.canGoForward = webView.canGoForward }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in
                    self?.isLoading = webView.isLoading
                    if !webView.isLoading {
                        webView.scrollView.refreshControl?.endRefreshing()
                    }
                }
            },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
                Task { @MainActor in self?.progress = webView.estimatedProgress }
            },
            webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
                Task { @MainActor in self?.pageTitle = webView.title ?? "" }
            },
            webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
                Task { @MainActor in self?.currentURL = webView.url }
            }
        ]
    }

    private func shouldOpenExternally(_ url: URL, navigationType: WKNavigationType) -> Bool {
        guard navigationType == .linkActivated else { return false }
        guard let host = url.host?.lowercased() else { return false }
        let externalHosts = [
            "youtube.com", "youtu.be", "x.com", "twitter.com",
            "instagram.com", "mega.nz", "github.com", "t.me"
        ]
        return externalHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
    }

    private func isSpecialScheme(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return !["http", "https", "about", "blob", "data"].contains(scheme)
    }

    private func hasDownloadExtension(_ url: URL) -> Bool {
        let extensions = [
            "ipa", "tipa", "deb", "zip", "rar", "7z", "dmg", "pkg",
            "pdf", "mobileconfig", "plist", "tar", "gz", "xz"
        ]
        return extensions.contains(url.pathExtension.lowercased())
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        if navigationAction.shouldPerformDownload || hasDownloadExtension(url) {
            decisionHandler(.download)
            return
        }

        if isSpecialScheme(url) {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        if shouldOpenExternally(url, navigationType: navigationAction.navigationType) {
            UIApplication.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        errorMessage = nil
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if let response = navigationResponse.response as? HTTPURLResponse,
           response.statusCode >= 400,
           let responseURL = response.url,
           responseURL == startURL,
           let fallbackURL,
           !triedFallback {
            triedFallback = true
            decisionHandler(.cancel)
            load(url: fallbackURL)
            return
        }

        let httpResponse = navigationResponse.response as? HTTPURLResponse
        let contentDisposition = httpResponse?.value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        let shouldDownload = !navigationResponse.canShowMIMEType ||
            contentDisposition.contains("attachment") ||
            (navigationResponse.response.url.map(hasDownloadExtension) ?? false)

        decisionHandler(shouldDownload ? .download : .allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        errorMessage = nil
        webView.scrollView.refreshControl?.endRefreshing()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleNavigationError(error)
    }

    private func handleNavigationError(_ error: Error) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        webView.scrollView.refreshControl?.endRefreshing()
        errorMessage = nsError.localizedDescription
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard navigationAction.targetFrame == nil,
              let url = navigationAction.request.url else { return nil }

        if isSpecialScheme(url) || shouldOpenExternally(url, navigationType: .linkActivated) {
            UIApplication.shared.open(url)
        } else {
            load(url: url)
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        guard let presenter = Self.topViewController() else {
            completionHandler()
            return
        }
        let alert = UIAlertController(title: "Next Solution", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        presenter.present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        guard let presenter = Self.topViewController() else {
            completionHandler(false)
            return
        }
        let alert = UIAlertController(title: "Next Solution", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        presenter.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        begin(download: download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        begin(download: download)
    }

    private func begin(download: WKDownload) {
        isDownloading = true
        download.delegate = self
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("NextSolutionDownloads", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let safeName = suggestedFilename
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            let destination = directory.appendingPathComponent(safeName)
            try? FileManager.default.removeItem(at: destination)
            downloadDestination = destination
            completionHandler(destination)
        } catch {
            isDownloading = false
            alertMessage = "The download folder could not be prepared: \(error.localizedDescription)"
            completionHandler(nil)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        isDownloading = false
        guard let destination = downloadDestination else {
            alertMessage = "The download finished, but the saved file could not be located."
            return
        }
        sharePayload = SharePayload(items: [destination])
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        isDownloading = false
        alertMessage = "Download failed: \(error.localizedDescription)"
    }

    private static func topViewController(
        base: UIViewController? = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?
            .rootViewController
    ) -> UIViewController? {
        if let navigation = base as? UINavigationController {
            return topViewController(base: navigation.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
