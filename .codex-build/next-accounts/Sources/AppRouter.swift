import Foundation
import Combine
import WebKit

enum AppTab: Hashable {
    case accounts
    case browser
}

struct SignupRequest: Identifiable, Equatable {
    let id = UUID()
    let platform: AccountPlatform

    var url: URL { platform.signupURL }
    var title: String { "\(platform.title) Signup" }
}

final class AppRouter: ObservableObject {
    @Published var selectedTab: AppTab = .accounts
    @Published private(set) var signupRequest: SignupRequest?
    @Published private(set) var isBrowserLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var browserError: String?

    private weak var webView: WKWebView?

    func openSignup(for platform: AccountPlatform) {
        browserError = nil
        signupRequest = SignupRequest(platform: platform)
        selectedTab = .browser
    }

    func attachBrowser(_ webView: WKWebView) {
        self.webView = webView
        updateNavigationState(from: webView)
    }

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        guard let webView else { return }
        if webView.url == nil, let request = signupRequest {
            webView.load(URLRequest(url: request.url))
        } else {
            webView.reload()
        }
    }

    func loadSignupPage() {
        guard let request = signupRequest else { return }
        webView?.load(URLRequest(url: request.url))
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

    private func updateNavigationState(from webView: WKWebView) {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }
}
