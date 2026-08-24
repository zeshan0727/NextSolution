import WebKit

enum BrowserMediaPlaybackPolicy {
    static func configure(_ configuration: WKWebViewConfiguration) {
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsPictureInPictureMediaPlayback = false
        install(in: configuration.userContentController)
    }

    static func install(in userContentController: WKUserContentController) {
        userContentController.addUserScript(WKUserScript(
            source: documentStartJavaScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
    }

    static let triggerJavaScript = "window.__nextMultiBrowserTryPlayAll && window.__nextMultiBrowserTryPlayAll();"

    private static let documentStartJavaScript = #"""
    (function() {
        if (window.__nextMultiBrowserMediaPolicyInstalled) return;
        window.__nextMultiBrowserMediaPolicyInstalled = true;

        function isMedia(element) {
            return !!element && (element.tagName === 'VIDEO' || element.tagName === 'AUDIO');
        }

        function hasActiveUserGesture() {
            try {
                return !!(navigator.userActivation && navigator.userActivation.isActive);
            } catch (_) {
                return false;
            }
        }

        function stopAutomaticFullscreen(media) {
            if (!isMedia(media) || hasActiveUserGesture()) return;
            var attemptedAt = Number(media.__nextMultiBrowserAutoPlayAttempt || 0);
            if (Date.now() - attemptedAt < 3000 && typeof media.webkitExitFullscreen === 'function') {
                setTimeout(function() {
                    try { media.webkitExitFullscreen(); } catch (_) {}
                }, 0);
            }
        }

        function forceInline(media) {
            if (!isMedia(media)) return;
            try {
                media.autoplay = true;
                media.playsInline = true;
                media.setAttribute('autoplay', '');
                media.setAttribute('playsinline', '');
                media.setAttribute('webkit-playsinline', '');
                if ('disablePictureInPicture' in media) media.disablePictureInPicture = true;
            } catch (_) {}
            try {
                if (!media.__nextMultiBrowserInlineListenerInstalled) {
                    media.addEventListener('webkitbeginfullscreen', function() {
                        stopAutomaticFullscreen(media);
                    }, true);
                    media.__nextMultiBrowserInlineListenerInstalled = true;
                }
            } catch (_) {}
        }

        function attemptPlay(media) {
            if (!isMedia(media) || typeof media.play !== 'function') return;
            forceInline(media);
            try { media.__nextMultiBrowserAutoPlayAttempt = Date.now(); } catch (_) {}

            function mutedRetry() {
                try {
                    media.muted = true;
                    media.defaultMuted = true;
                    media.setAttribute('muted', '');
                    var mutedPromise = media.play();
                    if (mutedPromise && typeof mutedPromise.catch === 'function') {
                        mutedPromise.catch(function() {});
                    }
                } catch (_) {}
            }

            function start() {
                forceInline(media);
                try {
                    var promise = media.play();
                    if (promise && typeof promise.catch === 'function') {
                        promise.catch(mutedRetry);
                    }
                } catch (_) {
                    mutedRetry();
                }
            }

            if (media.readyState >= 2) {
                start();
            } else {
                media.addEventListener('loadedmetadata', start, { once: true });
                media.addEventListener('canplay', start, { once: true });
            }
        }

        function prepareTree(root, shouldPlay) {
            if (!root) return;
            if (isMedia(root)) {
                forceInline(root);
                if (shouldPlay) attemptPlay(root);
            }
            if (!root.querySelectorAll) return;
            var media = root.querySelectorAll('video, audio');
            for (var index = 0; index < media.length; index++) {
                forceInline(media[index]);
                if (shouldPlay) attemptPlay(media[index]);
            }
        }

        try {
            var nativeCreateElement = Document.prototype.createElement;
            Document.prototype.createElement = function(tagName, options) {
                var element = nativeCreateElement.call(this, tagName, options);
                if (typeof tagName === 'string' && /^(video|audio)$/i.test(tagName)) {
                    forceInline(element);
                }
                return element;
            };
        } catch (_) {}

        try {
            var nativePlay = HTMLMediaElement.prototype.play;
            HTMLMediaElement.prototype.play = function() {
                forceInline(this);
                return nativePlay.apply(this, arguments);
            };
        } catch (_) {}

        function guardFullscreenMethod(methodName) {
            try {
                var nativeMethod = HTMLVideoElement.prototype[methodName];
                if (typeof nativeMethod !== 'function') return;
                HTMLVideoElement.prototype[methodName] = function() {
                    var attemptedAt = Number(this.__nextMultiBrowserAutoPlayAttempt || 0);
                    if (!hasActiveUserGesture() && Date.now() - attemptedAt < 3000) {
                        forceInline(this);
                        return;
                    }
                    return nativeMethod.apply(this, arguments);
                };
            } catch (_) {}
        }
        guardFullscreenMethod('webkitEnterFullscreen');
        guardFullscreenMethod('webkitEnterFullScreen');

        window.__nextMultiBrowserTryPlayAll = function() {
            prepareTree(document, true);
        };

        function installObserver() {
            if (!document.documentElement || window.__nextMultiBrowserMediaObserver) return;
            prepareTree(document, false);
            var observer = new MutationObserver(function(mutations) {
                for (var index = 0; index < mutations.length; index++) {
                    var nodes = mutations[index].addedNodes || [];
                    for (var nodeIndex = 0; nodeIndex < nodes.length; nodeIndex++) {
                        if (nodes[nodeIndex] && nodes[nodeIndex].nodeType === 1) {
                            prepareTree(nodes[nodeIndex], true);
                        }
                    }
                }
            });
            observer.observe(document.documentElement, { childList: true, subtree: true });
            window.__nextMultiBrowserMediaObserver = observer;
        }

        document.addEventListener('DOMContentLoaded', function() {
            installObserver();
            window.__nextMultiBrowserTryPlayAll();
        }, { once: true });

        document.addEventListener('loadedmetadata', function(event) {
            if (isMedia(event.target)) attemptPlay(event.target);
        }, true);

        document.addEventListener('play', function(event) {
            if (isMedia(event.target)) forceInline(event.target);
        }, true);

        document.addEventListener('webkitbeginfullscreen', function(event) {
            var media = event.target;
            if (!isMedia(media)) return;
            forceInline(media);
            stopAutomaticFullscreen(media);
        }, true);

        installObserver();
        setTimeout(window.__nextMultiBrowserTryPlayAll, 0);
    })();
    """#
}
