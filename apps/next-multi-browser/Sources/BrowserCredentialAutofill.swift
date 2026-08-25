import WebKit

/// Adds standards-based HTML hints that let iOS recognize login, password,
/// account-creation, and verification-code fields inside each WKWebView.
/// The script never reads, stores, or sends field values.
enum BrowserCredentialAutofillPolicy {
    static func configure(_ configuration: WKWebViewConfiguration) {
        install(in: configuration.userContentController)
    }

    static func install(in userContentController: WKUserContentController) {
        userContentController.addUserScript(WKUserScript(
            source: documentStartJavaScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
    }

    static let documentStartJavaScript = #"""
    (function() {
        'use strict';
        if (window.__nextMultiBrowserCredentialAutofillInstalled) return;
        window.__nextMultiBrowserCredentialAutofillInstalled = true;

        const featureMarker = 'NMB_APPLE_PASSWORD_AUTOFILL_116';
        const emailFocusMarker = 'NMB_APPLE_EMAIL_AUTOFILL_FOCUS_REFRESH_117';
        const supportedHints = new Set([
            'username', 'email', 'current-password', 'new-password', 'one-time-code'
        ]);
        const ignoredTypes = new Set([
            'hidden', 'button', 'submit', 'reset', 'checkbox', 'radio',
            'file', 'image', 'range', 'color', 'date', 'datetime-local',
            'month', 'time', 'week'
        ]);
        const oneTimeCodeTokens = [
            'one-time', 'one time', 'onetime', 'otp', 'verification code',
            'security code', 'sms code', 'auth code', 'two-factor',
            'two factor', '2fa', 'passcode'
        ];
        const newPasswordTokens = [
            'new password', 'new-password', 'confirm password',
            'confirm-password', 'password confirmation', 'password-confirmation',
            'create password', 'choose password', 'repeat password',
            'password again', 'passwdagain', 'password2', 'pass2'
        ];
        const registrationTokens = [
            'signup', 'sign-up', 'sign_up', 'register', 'registration',
            'createaccount', 'create-account', 'create_account', 'join'
        ];
        const usernameTokens = [
            'username', 'user name', 'user-name', 'userid', 'user id',
            'login', 'account', 'identifier'
        ];
        const contactEmailTokens = [
            'recovery', 'contact', 'alternate', 'alternative', 'backup',
            'notification', 'receipt', 'billing'
        ];

        function containsAny(value, tokens) {
            return tokens.some(function(token) { return value.indexOf(token) !== -1; });
        }

        function fingerprint(input) {
            return [
                input.getAttribute('id'),
                input.getAttribute('name'),
                input.getAttribute('placeholder'),
                input.getAttribute('aria-label'),
                input.getAttribute('data-testid'),
                input.getAttribute('title')
            ].filter(Boolean).join(' ').toLowerCase();
        }

        function supportedHint(input) {
            const value = (input.getAttribute('autocomplete') || '').toLowerCase();
            return value.split(/\s+/).find(function(token) {
                return supportedHints.has(token);
            }) || null;
        }

        function formContext(input, details) {
            let context = details + ' ' + String(location.pathname || '').toLowerCase();
            try {
                if (input.form) {
                    context += ' ' + [
                        input.form.getAttribute('id'),
                        input.form.getAttribute('name'),
                        input.form.getAttribute('action'),
                        input.form.getAttribute('aria-label')
                    ].filter(Boolean).join(' ').toLowerCase();
                }
            } catch (_) {}
            return context;
        }

        function registrationContext(input, details) {
            return containsAny(formContext(input, details), registrationTokens);
        }

        function isFocusedInput(input) {
            if (!input) return false;
            if (document.activeElement === input) return true;
            try { return input.matches(':focus'); } catch (_) { return false; }
        }

        function refreshFocusedEmailTraits(input) {
            if (!input || input.__nextMultiBrowserEmailTraitsRefreshed) return;
            if (!isFocusedInput(input)) return;
            input.__nextMultiBrowserEmailTraitsRefreshed = emailFocusMarker;

            setTimeout(function() {
                if (!input.isConnected || !isFocusedInput(input)) return;
                const value = input.value;
                const start = input.selectionStart;
                const end = input.selectionEnd;
                const direction = input.selectionDirection;
                const scrollX = window.scrollX;
                const scrollY = window.scrollY;
                try { input.blur(); } catch (_) { return; }
                requestAnimationFrame(function() {
                    if (!input.isConnected) return;
                    try {
                        input.focus({ preventScroll: true });
                    } catch (_) {
                        try { input.focus(); } catch (_) { return; }
                    }
                    try {
                        if (input.value !== value) input.value = value;
                        if (start !== null && end !== null) {
                            input.setSelectionRange(start, end, direction || 'none');
                        }
                    } catch (_) {}
                    try { window.scrollTo(scrollX, scrollY); } catch (_) {}
                });
            }, 0);
        }

        function applyHint(input, hint) {
            if (!hint || supportedHint(input)) return supportedHint(input);
            try {
                input.setAttribute('autocomplete', hint);
                input.autocomplete = hint;
                if (hint === 'username' || hint === 'email') {
                    if (!input.hasAttribute('autocapitalize')) {
                        input.setAttribute('autocapitalize', 'none');
                    }
                    if (!input.hasAttribute('spellcheck')) {
                        input.setAttribute('spellcheck', 'false');
                    }
                    refreshFocusedEmailTraits(input);
                }
            } catch (_) {}
            return hint;
        }

        function annotate(input) {
            if (!input || input.nodeType !== 1 || input.tagName !== 'INPUT') return null;
            const existingHint = supportedHint(input);
            if (existingHint) return existingHint;

            const type = String(input.getAttribute('type') || input.type || 'text').toLowerCase();
            if (ignoredTypes.has(type)) return null;
            const details = fingerprint(input);

            if (containsAny(details, oneTimeCodeTokens)) {
                return applyHint(input, 'one-time-code');
            }

            if (type === 'password') {
                const isNew = containsAny(details, newPasswordTokens)
                    || registrationContext(input, details);
                return applyHint(input, isNew ? 'new-password' : 'current-password');
            }

            if (containsAny(details, usernameTokens)) {
                return applyHint(input, 'username');
            }

            if (type === 'email') {
                const isContactEmail = containsAny(details, contactEmailTokens);
                return applyHint(input, isContactEmail ? 'email' : 'username');
            }

            return null;
        }

        function prepareTree(root) {
            if (!root) return;
            try {
                if (root.nodeType === 1 && root.tagName === 'INPUT') annotate(root);
                if (!root.querySelectorAll) return;
                root.querySelectorAll('input').forEach(annotate);
                root.querySelectorAll('*').forEach(function(element) {
                    if (element.shadowRoot) observeRoot(element.shadowRoot);
                });
            } catch (_) {}
        }

        function observeRoot(root) {
            if (!root || root.__nextMultiBrowserAutofillObserved) return;
            try { root.__nextMultiBrowserAutofillObserved = featureMarker; } catch (_) {}
            prepareTree(root);
            try {
                const observer = new MutationObserver(function(mutations) {
                    mutations.forEach(function(mutation) {
                        if (mutation.type === 'attributes') {
                            annotate(mutation.target);
                        } else {
                            mutation.addedNodes.forEach(prepareTree);
                        }
                    });
                });
                observer.observe(root, {
                    subtree: true,
                    childList: true,
                    attributes: true,
                    attributeFilter: [
                        'type', 'name', 'id', 'placeholder', 'aria-label',
                        'autocomplete', 'data-testid', 'title'
                    ]
                });
            } catch (_) {}
        }

        document.addEventListener('focusin', function(event) {
            const hint = annotate(event.target);
            if (hint === 'username' || hint === 'email') {
                refreshFocusedEmailTraits(event.target);
            }
            try {
                const root = event.target && event.target.getRootNode
                    ? event.target.getRootNode()
                    : null;
                if (root && root !== document) observeRoot(root);
            } catch (_) {}
        }, true);

        observeRoot(document);
        document.addEventListener('DOMContentLoaded', function() {
            observeRoot(document);
            prepareTree(document);
            const active = document.activeElement;
            const hint = annotate(active);
            if (hint === 'username' || hint === 'email') {
                refreshFocusedEmailTraits(active);
            }
        }, { once: true });
    })();
    """#
}
