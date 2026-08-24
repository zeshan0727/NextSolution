import Foundation
import Combine
import WebKit

enum AppTab: Hashable {
    case accounts
    case browser
}

struct BrowserRequest: Identifiable, Equatable {
    let id = UUID()
    let url: URL
}

final class AppRouter: ObservableObject {
    static let browserHomeURL = URL(string: "https://www.google.com")!

    @Published var selectedTab: AppTab = .accounts
    @Published var addressText = "google.com"
    @Published private(set) var browserRequest: BrowserRequest
    @Published private(set) var isBrowserLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var browserError: String?

    private weak var webView: WKWebView?

    init() {
        browserRequest = BrowserRequest(url: Self.browserHomeURL)
    }

    func attachBrowser(_ webView: WKWebView) {
        self.webView = webView
    }

    func loadAddress() {
        guard let url = webURL(from: addressText) else {
            browserError = "Enter a valid website address"
            return
        }
        load(url)
    }

    func goHome() {
        load(Self.browserHomeURL)
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        guard let webView else {
            browserRequest = BrowserRequest(url: browserRequest.url)
            return
        }

        if webView.url == nil {
            webView.load(URLRequest(url: browserRequest.url))
        } else {
            webView.reload()
        }
    }

    func stopLoading() {
        webView?.stopLoading()
        isBrowserLoading = false
    }

    func browserDidStart(_ webView: WKWebView) {
        browserError = nil
        isBrowserLoading = true
        updateNavigationState(from: webView)
    }

    func browserDidFinish(_ webView: WKWebView) {
        isBrowserLoading = false
        updateNavigationState(from: webView)
    }

    func browserDidFail(_ webView: WKWebView, error: Error) {
        isBrowserLoading = false
        updateNavigationState(from: webView)

        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        browserError = error.localizedDescription
    }

    private func load(_ url: URL) {
        browserError = nil
        addressText = displayAddress(for: url)
        browserRequest = BrowserRequest(url: url)
    }

    private func webURL(from rawValue: String) -> URL? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if value.contains(where: { $0.isWhitespace }) {
            return googleSearchURL(for: value)
        }

        let candidate: String
        if value.lowercased().hasPrefix("https://") || value.lowercased().hasPrefix("http://") {
            candidate = value
        } else {
            candidate = "https://\(value)"
        }

        guard
            let components = URLComponents(string: candidate),
            let scheme = components.scheme?.lowercased(),
            scheme == "https" || scheme == "http",
            components.host?.isEmpty == false,
            let url = components.url
        else {
            return googleSearchURL(for: value)
        }

        return url
    }

    private func googleSearchURL(for query: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }

    private func updateNavigationState(from webView: WKWebView) {
        if canGoBack != webView.canGoBack {
            canGoBack = webView.canGoBack
        }
        if canGoForward != webView.canGoForward {
            canGoForward = webView.canGoForward
        }
        if let url = webView.url {
            let newAddress = displayAddress(for: url)
            if addressText != newAddress {
                addressText = newAddress
            }
        }
    }

    private func displayAddress(for url: URL) -> String {
        if url.host == "www.google.com", url.path.isEmpty || url.path == "/" {
            return "google.com"
        }
        return url.absoluteString
    }
}
