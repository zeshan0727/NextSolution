import WebKit

extension BrowserPaneView {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let script = #"""
        (function() {
            if (window.__nextMultiBrowserAutoPlayInstalled) {
                if (window.__nextMultiBrowserTryPlayAll) {
                    window.__nextMultiBrowserTryPlayAll();
                }
                return;
            }

            window.__nextMultiBrowserAutoPlayInstalled = true;

            function tryPlay(media) {
                if (!media || typeof media.play !== 'function') return;

                try {
                    media.autoplay = true;
                    media.playsInline = true;
                    media.setAttribute('autoplay', '');
                    media.setAttribute('playsinline', '');
                    media.setAttribute('webkit-playsinline', '');
                } catch (_) {}

                function start() {
                    try {
                        var promise = media.play();
                        if (promise && typeof promise.catch === 'function') {
                            promise.catch(function() {
                                try {
                                    media.muted = true;
                                    media.defaultMuted = true;
                                    media.setAttribute('muted', '');
                                    var mutedPromise = media.play();
                                    if (mutedPromise && typeof mutedPromise.catch === 'function') {
                                        mutedPromise.catch(function() {});
                                    }
                                } catch (_) {}
                            });
                        }
                    } catch (_) {
                        try {
                            media.muted = true;
                            media.defaultMuted = true;
                            media.play();
                        } catch (_) {}
                    }
                }

                if (media.readyState >= 2) {
                    start();
                } else {
                    media.addEventListener('canplay', start, { once: true });
                    media.addEventListener('loadedmetadata', start, { once: true });
                }
            }

            window.__nextMultiBrowserTryPlayAll = function() {
                var items = document.querySelectorAll('video, audio');
                for (var i = 0; i < items.length; i++) {
                    tryPlay(items[i]);
                }
            };

            window.__nextMultiBrowserTryPlayAll();

            var observer = new MutationObserver(function(mutations) {
                for (var i = 0; i < mutations.length; i++) {
                    var nodes = mutations[i].addedNodes || [];
                    for (var j = 0; j < nodes.length; j++) {
                        var node = nodes[j];
                        if (!node || node.nodeType !== 1) continue;
                        if (node.matches && node.matches('video, audio')) {
                            tryPlay(node);
                        }
                        if (node.querySelectorAll) {
                            var nested = node.querySelectorAll('video, audio');
                            for (var k = 0; k < nested.length; k++) {
                                tryPlay(nested[k]);
                            }
                        }
                    }
                }
            });

            if (document.documentElement) {
                observer.observe(document.documentElement, { childList: true, subtree: true });
            }

            document.addEventListener('play', function(event) {
                var media = event.target;
                if (media && (media.tagName === 'VIDEO' || media.tagName === 'AUDIO')) {
                    try {
                        media.playsInline = true;
                        media.setAttribute('playsinline', '');
                    } catch (_) {}
                }
            }, true);
        })();
        """#

        webView.evaluateJavaScript(script, completionHandler: nil)
    }
}
