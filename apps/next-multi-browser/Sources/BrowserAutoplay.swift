import WebKit

extension BrowserPaneView {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(
            BrowserMediaPlaybackPolicy.triggerJavaScript,
            completionHandler: nil
        )
    }
}
