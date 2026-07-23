import SwiftUI
import WebKit

struct BrowserWebView: UIViewRepresentable {
    @ObservedObject var session: BrowserSession

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "mediaDetected")
        controller.add(context.coordinator, name: "pageState")
        controller.addUserScript(WKUserScript(
            source: MediaDetectionScript.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.applicationNameForUserAgent = "NextMedia/1.1"

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.keyboardDismissMode = .interactive
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        context.coordinator.observe(webView)
        session.attach(webView)
        DispatchQueue.main.async { session.loadHome() }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if session.webView !== webView { session.attach(webView) }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObserving()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "mediaDetected")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "pageState")
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private weak var session: BrowserSession?
        private var progressObservation: NSKeyValueObservation?
        private var titleObservation: NSKeyValueObservation?
        private var urlObservation: NSKeyValueObservation?

        init(session: BrowserSession) {
            self.session = session
        }

        func observe(_ webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
                Task { @MainActor in
                    self?.session?.estimatedProgress = webView.estimatedProgress
                }
            }
            titleObservation = webView.observe(\.title, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.session?.refreshNavigationState() }
            }
            urlObservation = webView.observe(\.url, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.session?.refreshNavigationState() }
            }
        }

        func stopObserving() {
            progressObservation?.invalidate()
            titleObservation?.invalidate()
            urlObservation?.invalidate()
            progressObservation = nil
            titleObservation = nil
            urlObservation = nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                session?.isLoading = true
                session?.refreshNavigationState()
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                session?.isLoading = false
                session?.estimatedProgress = 1
                session?.refreshNavigationState()
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                session?.isLoading = false
                session?.refreshNavigationState()
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                session?.isLoading = false
                session?.refreshNavigationState()
            }
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

            if navigationAction.targetFrame == nil, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }

            if Self.looksLikeDirectMedia(url) {
                registerURL(
                    url,
                    pageURL: webView.url,
                    title: webView.title ?? url.deletingPathExtension().lastPathComponent,
                    mimeType: nil,
                    source: "navigation",
                    wasPlaying: false
                )
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            if let url = navigationResponse.response.url,
               let mime = navigationResponse.response.mimeType,
               Self.isMediaMIME(mime) {
                registerURL(
                    url,
                    pageURL: webView.url,
                    title: navigationResponse.response.suggestedFilename ?? webView.title ?? "Detected media",
                    mimeType: mime,
                    source: "response",
                    wasPlaying: false
                )
            }
            decisionHandler(.allow)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
            return nil
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "pageState" {
                Task { @MainActor in self.session?.refreshNavigationState() }
                return
            }

            guard message.name == "mediaDetected",
                  let body = message.body as? [String: Any],
                  let urlString = body["url"] as? String,
                  let url = URL(string: urlString),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }

            let title = (body["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let pageURL = (body["pageURL"] as? String).flatMap(URL.init(string:))
            let mime = body["mimeType"] as? String
            let source = body["source"] as? String ?? "page"
            let wasPlaying = body["wasPlaying"] as? Bool ?? false
            let width = Self.integer(body["width"])
            let height = Self.integer(body["height"])
            let duration = Self.double(body["duration"])
            let kind = Self.mediaKind(url: url, mime: mime, hint: body["kind"] as? String)

            let media = DetectedMedia(
                url: url,
                title: title?.isEmpty == false ? title! : url.deletingPathExtension().lastPathComponent,
                pageURL: pageURL,
                mimeType: mime,
                kind: kind,
                width: width,
                height: height,
                duration: duration,
                detectionSource: source,
                wasPlaying: wasPlaying
            )
            Task { @MainActor in self.session?.register(media) }
        }

        private func registerURL(
            _ url: URL,
            pageURL: URL?,
            title: String,
            mimeType: String?,
            source: String,
            wasPlaying: Bool
        ) {
            let media = DetectedMedia(
                url: url,
                title: title,
                pageURL: pageURL,
                mimeType: mimeType,
                kind: Self.mediaKind(url: url, mime: mimeType, hint: nil),
                detectionSource: source,
                wasPlaying: wasPlaying
            )
            Task { @MainActor in self.session?.register(media) }
        }

        private static func mediaKind(url: URL, mime: String?, hint: String?) -> DetectedMedia.Kind {
            let lower = url.absoluteString.lowercased()
            let lowerMime = mime?.lowercased() ?? ""
            let lowerHint = hint?.lowercased() ?? ""
            if lower.contains(".m3u8") || lower.contains(".mpd") || lowerMime.contains("mpegurl") || lowerMime.contains("dash+xml") {
                return .playlist
            }
            if lowerMime.hasPrefix("video/") || lowerHint == "video" { return .video }
            if lowerMime.hasPrefix("audio/") || lowerHint == "audio" { return .audio }
            let ext = url.pathExtension.lowercased()
            if ["mp4", "m4v", "mov", "webm", "mkv", "avi", "3gp"].contains(ext) { return .video }
            if ["mp3", "m4a", "aac", "wav", "flac", "ogg", "opus"].contains(ext) { return .audio }
            return .unknown
        }

        private static func looksLikeDirectMedia(_ url: URL) -> Bool {
            let ext = url.pathExtension.lowercased()
            return ["mp4", "m4v", "mov", "webm", "mkv", "avi", "3gp", "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus", "m3u8", "mpd"].contains(ext)
        }

        private static func isMediaMIME(_ mime: String) -> Bool {
            let lower = mime.lowercased()
            return lower.hasPrefix("video/") || lower.hasPrefix("audio/") || lower.contains("mpegurl") || lower.contains("dash+xml")
        }

        private static func integer(_ value: Any?) -> Int? {
            if let number = value as? NSNumber { return number.intValue > 0 ? number.intValue : nil }
            if let string = value as? String, let number = Int(string), number > 0 { return number }
            return nil
        }

        private static func double(_ value: Any?) -> Double? {
            if let number = value as? NSNumber { return number.doubleValue.isFinite ? number.doubleValue : nil }
            if let string = value as? String, let number = Double(string), number.isFinite { return number }
            return nil
        }
    }
}

private enum MediaDetectionScript {
    static let source = #"""
    (() => {
      if (window.__nextMediaDetectorInstalled) return;
      window.__nextMediaDetectorInstalled = true;

      const seen = new Map();
      const mediaExtensions = /\.(mp4|m4v|mov|webm|mkv|avi|3gp|mp3|m4a|aac|wav|flac|ogg|opus|m3u8|mpd)(?:$|[?#])/i;
      const segmentExtensions = /\.(m4s|cmfv|cmfa|ts)(?:$|[?#])/i;

      function playingNow() {
        try {
          return Array.from(document.querySelectorAll('video,audio')).some(el => !el.paused && !el.ended && el.readyState > 1);
        } catch (_) { return false; }
      }

      function mediaHintFromURL(raw) {
        try {
          const parsed = new URL(raw, document.baseURI);
          const values = ['mime', 'type', 'content_type', 'contentType', 'format'].map(key => parsed.searchParams.get(key) || '').join(' ').toLowerCase();
          if (values.includes('video/')) return 'video';
          if (values.includes('audio/')) return 'audio';
          if (values.includes('mpegurl') || values.includes('dash+xml')) return 'playlist';
          if (/\.(m3u8|mpd)(?:$|[?#])/i.test(parsed.href)) return 'playlist';
          if (/\.(mp4|m4v|mov|webm|mkv|avi|3gp)(?:$|[?#])/i.test(parsed.href)) return 'video';
          if (/\.(mp3|m4a|aac|wav|flac|ogg|opus)(?:$|[?#])/i.test(parsed.href)) return 'audio';
        } catch (_) {}
        return 'unknown';
      }

      function shouldInspect(raw, initiator) {
        if (!raw || typeof raw !== 'string') return false;
        if (raw.startsWith('blob:') || raw.startsWith('data:') || raw.startsWith('javascript:')) return false;
        if (segmentExtensions.test(raw)) return false;
        if (mediaExtensions.test(raw)) return true;
        if (initiator === 'video' || initiator === 'audio') return true;
        try {
          const parsed = new URL(raw, document.baseURI);
          const hint = ['mime', 'type', 'content_type', 'contentType', 'format']
            .map(key => decodeURIComponent(parsed.searchParams.get(key) || ''))
            .join(' ')
            .toLowerCase();
          return hint.includes('video/') || hint.includes('audio/') || hint.includes('mpegurl') || hint.includes('dash+xml');
        } catch (_) { return false; }
      }

      function post(raw, meta = {}) {
        if (!shouldInspect(raw, meta.initiator || '')) return;
        let absolute;
        try { absolute = new URL(raw, document.baseURI).href; } catch (_) { return; }
        if (!/^https?:/i.test(absolute)) return;

        const now = Date.now();
        const previous = seen.get(absolute) || 0;
        if (now - previous < 1800) return;
        seen.set(absolute, now);

        const payload = {
          url: absolute,
          title: meta.title || document.title || 'Detected media',
          pageURL: location.href,
          mimeType: meta.mimeType || '',
          kind: meta.kind || mediaHintFromURL(absolute),
          width: Number(meta.width || 0),
          height: Number(meta.height || 0),
          duration: Number.isFinite(Number(meta.duration)) ? Number(meta.duration) : 0,
          source: meta.source || 'page',
          wasPlaying: Boolean(meta.wasPlaying || playingNow())
        };
        try { window.webkit.messageHandlers.mediaDetected.postMessage(payload); } catch (_) {}
      }

      function scanElement(element, source) {
        if (!element) return;
        const tag = String(element.tagName || '').toLowerCase();
        if (tag === 'source') {
          post(element.src || element.getAttribute('src'), {
            title: document.title,
            mimeType: element.type || '',
            kind: (element.type || '').startsWith('audio/') ? 'audio' : 'video',
            source,
            wasPlaying: playingNow()
          });
          return;
        }
        if (tag !== 'video' && tag !== 'audio') return;
        post(element.currentSrc || element.src || element.getAttribute('src'), {
          title: element.getAttribute('title') || element.getAttribute('aria-label') || document.title,
          mimeType: element.getAttribute('type') || '',
          kind: tag,
          width: element.videoWidth || element.clientWidth || 0,
          height: element.videoHeight || element.clientHeight || 0,
          duration: element.duration || 0,
          source,
          wasPlaying: !element.paused && !element.ended
        });
        element.querySelectorAll('source').forEach(node => scanElement(node, source));
      }

      function scanDocument(source) {
        try { document.querySelectorAll('video,audio,source').forEach(node => scanElement(node, source)); } catch (_) {}
      }

      document.addEventListener('play', event => {
        scanElement(event.target, 'play');
        setTimeout(() => scanDocument('playback-scan'), 500);
        setTimeout(() => scanPerformance('playback-resources'), 900);
      }, true);
      document.addEventListener('loadedmetadata', event => scanElement(event.target, 'metadata'), true);
      document.addEventListener('canplay', event => scanElement(event.target, 'canplay'), true);

      const observer = new MutationObserver(mutations => {
        for (const mutation of mutations) {
          for (const node of mutation.addedNodes || []) {
            if (!(node instanceof Element)) continue;
            scanElement(node, 'mutation');
            node.querySelectorAll?.('video,audio,source').forEach(child => scanElement(child, 'mutation'));
          }
          if (mutation.type === 'attributes') scanElement(mutation.target, 'attribute');
        }
      });

      function scanPerformance(source = 'resource') {
        try {
          performance.getEntriesByType('resource').forEach(entry => {
            post(entry.name, {
              initiator: entry.initiatorType || '',
              kind: entry.initiatorType === 'audio' ? 'audio' : (entry.initiatorType === 'video' ? 'video' : ''),
              source,
              wasPlaying: playingNow()
            });
          });
        } catch (_) {}
      }

      try {
        const performanceObserver = new PerformanceObserver(list => {
          list.getEntries().forEach(entry => {
            post(entry.name, {
              initiator: entry.initiatorType || '',
              kind: entry.initiatorType === 'audio' ? 'audio' : (entry.initiatorType === 'video' ? 'video' : ''),
              source: 'performance',
              wasPlaying: playingNow()
            });
          });
        });
        performanceObserver.observe({ type: 'resource', buffered: true });
      } catch (_) {}

      try {
        const originalFetch = window.fetch;
        window.fetch = function(input, init) {
          const raw = typeof input === 'string' ? input : input?.url;
          post(raw, { source: 'fetch', initiator: 'fetch', wasPlaying: playingNow() });
          return originalFetch.apply(this, arguments);
        };
      } catch (_) {}

      try {
        const originalOpen = XMLHttpRequest.prototype.open;
        XMLHttpRequest.prototype.open = function(method, url) {
          post(url, { source: 'xhr', initiator: 'xmlhttprequest', wasPlaying: playingNow() });
          return originalOpen.apply(this, arguments);
        };
      } catch (_) {}

      function start() {
        try { observer.observe(document.documentElement || document, { childList: true, subtree: true, attributes: true, attributeFilter: ['src', 'type'] }); } catch (_) {}
        scanDocument('initial');
        scanPerformance('initial-resources');
        try { window.webkit.messageHandlers.pageState.postMessage({ ready: true }); } catch (_) {}
      }

      if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start, { once: true });
      else start();
      setInterval(() => { scanDocument('timer'); if (playingNow()) scanPerformance('playing-timer'); }, 2500);
    })();
    """#
}
