import Foundation
import WebKit

@MainActor
final class BrowserSession: ObservableObject {
    @Published var addressText = ""
    @Published var pageTitle = "Browser"
    @Published var currentURL: URL?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var estimatedProgress = 0.0
    @Published private(set) var detectedMedia: [DetectedMedia] = []
    @Published var promptedMedia: DetectedMedia?

    weak var webView: WKWebView?

    private var lastPromptedKey: String?
    private var lastPromptDate = Date.distantPast
    private let maximumDetections = 80

    func attach(_ webView: WKWebView) {
        self.webView = webView
        refreshNavigationState()
    }

    func loadHome() {
        load(URL(string: UserDefaults.standard.string(forKey: "browserHomeURL") ?? "https://www.youtube.com")!)
    }

    func submitAddress() {
        let text = addressText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        if let direct = normalizedURL(from: text) {
            load(direct)
            return
        }

        var components = URLComponents(string: "https://www.youtube.com/results")!
        components.queryItems = [URLQueryItem(name: "search_query", value: text)]
        if let url = components.url { load(url) }
    }

    func load(_ url: URL) {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        addressText = url.absoluteString
        webView?.load(URLRequest(url: url))
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }

    func reloadOrStop() {
        if isLoading { webView?.stopLoading() }
        else { webView?.reload() }
    }

    func refreshNavigationState() {
        guard let webView else { return }
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        currentURL = webView.url
        pageTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Browser"
        if let url = webView.url { addressText = url.absoluteString }
    }

    func register(_ media: DetectedMedia) {
        let key = detectionKey(for: media.url)
        if let index = detectedMedia.firstIndex(where: { detectionKey(for: $0.url) == key }) {
            var existing = detectedMedia[index]
            existing.title = media.title.nilIfEmpty ?? existing.title
            existing.pageURL = media.pageURL ?? existing.pageURL
            existing.mimeType = media.mimeType ?? existing.mimeType
            existing.width = max(existing.width ?? 0, media.width ?? 0).positiveOrNil
            existing.height = max(existing.height ?? 0, media.height ?? 0).positiveOrNil
            existing.duration = media.duration ?? existing.duration
            existing.wasPlaying = existing.wasPlaying || media.wasPlaying
            existing.detectedAt = Date()
            detectedMedia[index] = existing
            detectedMedia.sort { $0.detectedAt > $1.detectedAt }
            maybePrompt(existing)
            return
        }

        detectedMedia.insert(media, at: 0)
        if detectedMedia.count > maximumDetections {
            detectedMedia.removeLast(detectedMedia.count - maximumDetections)
        }
        maybePrompt(media)
    }

    func remove(_ media: DetectedMedia) {
        detectedMedia.removeAll { $0.id == media.id }
    }

    func clearDetectedMedia() {
        detectedMedia.removeAll()
        promptedMedia = nil
        lastPromptedKey = nil
    }

    func downloadHeaders(for media: DetectedMedia) async -> [String: String] {
        guard let webView else { return [:] }

        async let userAgent = browserUserAgent(webView)
        async let cookies = browserCookies(webView)

        var headers: [String: String] = [
            "Accept": "video/*, audio/*, application/octet-stream;q=0.9, */*;q=0.8",
            "Accept-Language": Locale.preferredLanguages.prefix(3).joined(separator: ",")
        ]

        if let userAgent = await userAgent, !userAgent.isEmpty {
            headers["User-Agent"] = userAgent
        }

        let relevantCookies = (await cookies).filter { cookie in
            guard let host = media.url.host?.lowercased() else { return false }
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let domainMatches = host == domain || host.hasSuffix(".\(domain)")
            let pathMatches = media.url.path.isEmpty || media.url.path.hasPrefix(cookie.path)
            return domainMatches && pathMatches
        }
        if !relevantCookies.isEmpty {
            let fields = HTTPCookie.requestHeaderFields(with: relevantCookies)
            headers.merge(fields) { _, new in new }
        }

        if let pageURL = media.pageURL ?? currentURL {
            headers["Referer"] = pageURL.absoluteString
            if var origin = URLComponents(url: pageURL, resolvingAgainstBaseURL: false) {
                origin.path = ""
                origin.query = nil
                origin.fragment = nil
                if let originString = origin.string {
                    headers["Origin"] = originString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                }
            }
        }

        return headers
    }

    private func maybePrompt(_ media: DetectedMedia) {
        let autoPrompt = UserDefaults.standard.object(forKey: "autoMediaPrompt") as? Bool ?? true
        guard autoPrompt, media.wasPlaying else { return }
        guard media.canDownloadAsFile || media.isPlaylist else { return }

        let key = detectionKey(for: media.url)
        let enoughTimePassed = Date().timeIntervalSince(lastPromptDate) > 3
        guard promptedMedia == nil, key != lastPromptedKey || enoughTimePassed else { return }

        promptedMedia = media
        lastPromptedKey = key
        lastPromptDate = Date()
    }

    private func detectionKey(for url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.string ?? url.absoluteString
    }

    private func normalizedURL(from text: String) -> URL? {
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) {
            return url
        }

        let looksLikeHost = !text.contains(" ") && (text.contains(".") || text.hasPrefix("localhost"))
        guard looksLikeHost else { return nil }
        return URL(string: "https://\(text)")
    }

    private func browserUserAgent(_ webView: WKWebView) async -> String? {
        await withCheckedContinuation { continuation in
            webView.evaluateJavaScript("navigator.userAgent") { result, _ in
                continuation.resume(returning: result as? String)
            }
        }
    }

    private func browserCookies(_ webView: WKWebView) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private extension Int {
    var positiveOrNil: Int? { self > 0 ? self : nil }
}
