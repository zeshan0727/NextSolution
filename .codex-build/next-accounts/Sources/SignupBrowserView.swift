import SwiftUI
import WebKit

struct SignupBrowserView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [AppTheme.backgroundTop, AppTheme.backgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if let request = router.signupRequest {
                    VStack(spacing: 0) {
                        BrowserControlsView()

                        if router.isBrowserLoading {
                            ProgressView()
                                .progressViewStyle(.linear)
                                .tint(AppTheme.accent)
                        }

                        SignupWebView(request: request, router: router)

                        if let error = router.browserError {
                            BrowserErrorView(message: error, retry: router.reload)
                        }
                    }
                } else {
                    BrowserEmptyView {
                        router.selectedTab = .accounts
                    }
                }
            }
            .navigationTitle(router.signupRequest?.title ?? "Account Browser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        router.selectedTab = .accounts
                    } label: {
                        Label("Accounts", systemImage: "chevron.left")
                    }
                }
            }
        }
    }
}

private struct BrowserControlsView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        HStack(spacing: 12) {
            BrowserControlButton(
                systemImage: "chevron.backward",
                label: "Back",
                isDisabled: !router.canGoBack,
                action: router.goBack
            )
            BrowserControlButton(
                systemImage: "chevron.forward",
                label: "Forward",
                isDisabled: !router.canGoForward,
                action: router.goForward
            )
            BrowserControlButton(
                systemImage: "arrow.clockwise",
                label: "Reload",
                action: router.reload
            )

            Spacer(minLength: 8)

            Button(action: router.loadSignupPage) {
                Label("Signup", systemImage: "person.badge.plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(AppTheme.accent.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
    }
}

private struct BrowserControlButton: View {
    let systemImage: String
    let label: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isDisabled ? Color.white.opacity(0.25) : Color.white.opacity(0.82))
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.07), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(label)
    }
}

private struct BrowserEmptyView: View {
    let showAccounts: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "globe")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
            Text("Account Browser")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text("Press and hold any platform card to open its signup page here.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.62))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button("View Accounts", action: showAccounts)
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
        }
    }
}

private struct BrowserErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(2)
            Spacer(minLength: 4)
            Button("Retry", action: retry)
                .font(.caption.weight(.bold))
        }
        .padding(12)
        .background(Color.black.opacity(0.74))
    }
}

private struct SignupWebView: UIViewRepresentable {
    let request: SignupRequest
    @ObservedObject var router: AppRouter

    func makeCoordinator() -> Coordinator {
        Coordinator(router: router)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.keyboardDismissMode = .interactive
        router.attachBrowser(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        router.attachBrowser(webView)
        guard context.coordinator.loadedRequestID != request.id else { return }
        context.coordinator.loadedRequestID = request.id
        webView.load(URLRequest(url: request.url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let router: AppRouter
        var loadedRequestID: UUID?

        init(router: AppRouter) {
            self.router = router
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation?) {
            router.browserDidStart(webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation?) {
            router.browserDidFinish(webView)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation?,
            withError error: Error
        ) {
            router.browserDidFail(webView, error: error)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation?,
            withError error: Error
        ) {
            router.browserDidFail(webView, error: error)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }
    }
}
