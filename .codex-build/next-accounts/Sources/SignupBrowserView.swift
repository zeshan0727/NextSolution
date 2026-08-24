import SwiftUI
import WebKit

struct BrowserView: View {
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

                VStack(spacing: 0) {
                    BrowserAddressBar()
                    BrowserNavigationBar()

                    if router.isBrowserLoading {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .tint(AppTheme.accent)
                    }

                    BrowserWebView(request: router.browserRequest, router: router)

                    if let error = router.browserError {
                        BrowserErrorView(message: error, retry: router.reload)
                    }
                }
            }
            .navigationTitle("Browser")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct BrowserAddressBar: View {
    @EnvironmentObject private var router: AppRouter
    @FocusState private var isAddressFocused: Bool

    var body: some View {
        HStack(spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)

                TextField("Search or enter website", text: $router.addressText)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .focused($isAddressFocused)
                    .onSubmit(loadAddress)

                if isAddressFocused && !router.addressText.isEmpty {
                    Button {
                        router.addressText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.white.opacity(0.42))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear address")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isAddressFocused ? AppTheme.accent.opacity(0.75) : Color.white.opacity(0.11), lineWidth: 1)
            }

            Button(action: loadAddress) {
                Text("Go")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 40)
                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open address")
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 7)
        .background(.ultraThinMaterial)
    }

    private func loadAddress() {
        isAddressFocused = false
        router.loadAddress()
    }
}

private struct BrowserNavigationBar: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        HStack(spacing: 16) {
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
                systemImage: "house.fill",
                label: "Google home",
                action: router.goHome
            )
            BrowserControlButton(
                systemImage: router.isBrowserLoading ? "xmark" : "arrow.clockwise",
                label: router.isBrowserLoading ? "Stop" : "Reload",
                action: {
                    if router.isBrowserLoading {
                        router.stopLoading()
                    } else {
                        router.reload()
                    }
                }
            )

            Spacer(minLength: 0)

            Text("Google opens by default")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.48))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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

private struct BrowserWebView: UIViewRepresentable {
    let request: BrowserRequest
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
