import Foundation
import UIKit
import WebKit

enum BrowserProfileIcon: String, CaseIterable, Codable {
    case person
    case globe
    case testTube
    case briefcase
    case video
    case shopping
    case code
    case shield

    var title: String {
        switch self {
        case .person: return "Person"
        case .globe: return "Globe"
        case .testTube: return "Testing"
        case .briefcase: return "Work"
        case .video: return "Video"
        case .shopping: return "Shopping"
        case .code: return "Development"
        case .shield: return "Private"
        }
    }

    var symbolName: String {
        switch self {
        case .person: return "person.crop.circle.fill"
        case .globe: return "globe.americas.fill"
        case .testTube: return "testtube.2"
        case .briefcase: return "briefcase.fill"
        case .video: return "play.rectangle.fill"
        case .shopping: return "bag.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .shield: return "checkmark.shield.fill"
        }
    }
}

enum BrowserProfileColor: String, CaseIterable, Codable {
    case blue
    case green
    case indigo
    case purple
    case pink
    case orange
    case teal
    case gray

    var title: String { rawValue.capitalized }

    var uiColor: UIColor {
        switch self {
        case .blue: return .systemBlue
        case .green: return .systemGreen
        case .indigo: return .systemIndigo
        case .purple: return .systemPurple
        case .pink: return .systemPink
        case .orange: return .systemOrange
        case .teal: return .systemTeal
        case .gray: return .systemGray
        }
    }
}

enum BrowserUserAgentPreset: String, CaseIterable, Codable {
    case automatic
    case iPhoneSafari
    case iPadSafari
    case desktopSafari
    case desktopChrome

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .iPhoneSafari: return "Safari — iPhone"
        case .iPadSafari: return "Safari — iPad"
        case .desktopSafari: return "Safari — Desktop"
        case .desktopChrome: return "Chrome — Windows"
        }
    }

    var userAgent: String? {
        switch self {
        case .automatic:
            return nil
        case .iPhoneSafari:
            return "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        case .iPadSafari:
            return "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        case .desktopSafari:
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
        case .desktopChrome:
            return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
        }
    }

    var prefersDesktopContent: Bool {
        self == .desktopSafari || self == .desktopChrome
    }
}

enum BrowserLanguagePreset: String, CaseIterable, Codable {
    case automatic
    case english
    case arabic
    case urdu
    case french
    case german
    case japanese

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .english: return "English"
        case .arabic: return "Arabic"
        case .urdu: return "Urdu"
        case .french: return "French"
        case .german: return "German"
        case .japanese: return "Japanese"
        }
    }

    var languageCode: String? {
        switch self {
        case .automatic: return nil
        case .english: return "en"
        case .arabic: return "ar"
        case .urdu: return "ur"
        case .french: return "fr"
        case .german: return "de"
        case .japanese: return "ja"
        }
    }
}

enum BrowserRegionPreset: String, CaseIterable, Codable {
    case automatic
    case unitedStates
    case qatar
    case pakistan
    case unitedKingdom
    case germany
    case japan

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .unitedStates: return "United States"
        case .qatar: return "Qatar"
        case .pakistan: return "Pakistan"
        case .unitedKingdom: return "United Kingdom"
        case .germany: return "Germany"
        case .japan: return "Japan"
        }
    }

    var regionCode: String? {
        switch self {
        case .automatic: return nil
        case .unitedStates: return "US"
        case .qatar: return "QA"
        case .pakistan: return "PK"
        case .unitedKingdom: return "GB"
        case .germany: return "DE"
        case .japan: return "JP"
        }
    }
}

enum BrowserTimezonePreset: String, CaseIterable, Codable {
    case automatic
    case doha
    case newYork
    case london
    case karachi
    case berlin
    case tokyo

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .doha: return "Doha"
        case .newYork: return "New York"
        case .london: return "London"
        case .karachi: return "Karachi"
        case .berlin: return "Berlin"
        case .tokyo: return "Tokyo"
        }
    }

    var identifier: String? {
        switch self {
        case .automatic: return nil
        case .doha: return "Asia/Qatar"
        case .newYork: return "America/New_York"
        case .london: return "Europe/London"
        case .karachi: return "Asia/Karachi"
        case .berlin: return "Europe/Berlin"
        case .tokyo: return "Asia/Tokyo"
        }
    }
}

enum BrowserViewportPreset: String, CaseIterable, Codable {
    case automatic
    case iPhoneSE
    case iPhonePro
    case iPhoneProMax
    case iPadPro
    case desktop

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .iPhoneSE: return "iPhone SE"
        case .iPhonePro: return "iPhone Pro"
        case .iPhoneProMax: return "iPhone Pro Max"
        case .iPadPro: return "iPad Pro 13-inch"
        case .desktop: return "Desktop"
        }
    }

    var viewportDescription: String {
        guard let size else { return "App window"
        }
        return "\(Int(size.width)) × \(Int(size.height)) CSS px"
    }

    var size: CGSize? {
        switch self {
        case .automatic: return nil
        case .iPhoneSE: return CGSize(width: 375, height: 667)
        case .iPhonePro: return CGSize(width: 393, height: 852)
        case .iPhoneProMax: return CGSize(width: 430, height: 932)
        case .iPadPro: return CGSize(width: 1024, height: 1366)
        case .desktop: return CGSize(width: 1440, height: 900)
        }
    }

    var prefersDesktopContent: Bool { self == .desktop }
}

struct BrowserProfileEnvironment: Codable, Equatable {
    var userAgent: BrowserUserAgentPreset = .automatic
    var language: BrowserLanguagePreset = .automatic
    var region: BrowserRegionPreset = .automatic
    var timezone: BrowserTimezonePreset = .automatic
    var viewport: BrowserViewportPreset = .automatic

    static let `default` = BrowserProfileEnvironment()

    var localeIdentifier: String {
        let preferred = Locale.preferredLanguages.first ?? Locale.current.identifier
        let systemLanguage = preferred
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .first
            .map(String.init) ?? "en"
        let systemRegion = Locale.current.regionCode ?? "US"
        let languageCode = language.languageCode ?? systemLanguage
        let regionCode = region.regionCode ?? systemRegion
        return "\(languageCode)-\(regionCode)"
    }

    var acceptLanguageHeader: String {
        let languageCode = localeIdentifier.split(separator: "-").first.map(String.init) ?? "en"
        return "\(localeIdentifier),\(languageCode);q=0.9"
    }

    var summary: String {
        "\(viewport.title) • \(localeIdentifier) • \(timezone.title)"
    }
}

enum BrowserEnvironmentWebKit {
    static func configure(_ environment: BrowserProfileEnvironment, configuration: WKWebViewConfiguration) {
        configuration.defaultWebpagePreferences.preferredContentMode = preferredContentMode(for: environment)
        configuration.userContentController.addUserScript(environmentScript(for: environment))
    }

    static func apply(_ environment: BrowserProfileEnvironment, to webView: WKWebView) {
        webView.customUserAgent = environment.userAgent.userAgent
        webView.configuration.defaultWebpagePreferences.preferredContentMode = preferredContentMode(for: environment)
        webView.configuration.userContentController.removeAllUserScripts()
        webView.configuration.userContentController.addUserScript(environmentScript(for: environment))
    }

    static func request(for url: URL, environment: BrowserProfileEnvironment) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30)
        request.setValue(environment.acceptLanguageHeader, forHTTPHeaderField: "Accept-Language")
        return request
    }

    private static func preferredContentMode(for environment: BrowserProfileEnvironment) -> WKWebpagePreferences.ContentMode {
        if environment.viewport.prefersDesktopContent || environment.userAgent.prefersDesktopContent {
            return .desktop
        }
        if environment.viewport == .automatic && environment.userAgent == .automatic {
            return .recommended
        }
        return .mobile
    }

    private static func environmentScript(for environment: BrowserProfileEnvironment) -> WKUserScript {
        var payload: [String: Any] = [
            "locale": environment.localeIdentifier,
            "language": environment.localeIdentifier.split(separator: "-").first.map(String.init) ?? "en",
            "region": environment.region.regionCode ?? Locale.current.regionCode ?? "US",
            "devicePreset": environment.viewport.title
        ]
        if let timezone = environment.timezone.identifier {
            payload["timezone"] = timezone
        }
        if let viewport = environment.viewport.size {
            payload["viewportWidth"] = viewport.width
            payload["viewportHeight"] = viewport.height
        }
        let data = try? JSONSerialization.data(withJSONObject: payload)
        let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let source = #"""
        (function() {
            const environment = \#(json);
            try {
                Object.defineProperty(window, '__nextMultiBrowserEnvironment', {
                    value: Object.freeze(environment), configurable: false
                });
            } catch (_) {}

            if (environment.locale) {
                try {
                    Object.defineProperty(Navigator.prototype, 'language', {
                        get: function() { return environment.locale; }, configurable: true
                    });
                    Object.defineProperty(Navigator.prototype, 'languages', {
                        get: function() { return [environment.locale, environment.language]; }, configurable: true
                    });
                } catch (_) {}
            }

            if (environment.timezone && window.Intl && Intl.DateTimeFormat) {
                try {
                    const NativeDateTimeFormat = Intl.DateTimeFormat;
                    const ProfileDateTimeFormat = function(locales, options) {
                        const selectedLocales = locales || environment.locale;
                        const selectedOptions = Object.assign({}, options || {});
                        if (!selectedOptions.timeZone) selectedOptions.timeZone = environment.timezone;
                        return new NativeDateTimeFormat(selectedLocales, selectedOptions);
                    };
                    ProfileDateTimeFormat.prototype = NativeDateTimeFormat.prototype;
                    Object.setPrototypeOf(ProfileDateTimeFormat, NativeDateTimeFormat);
                    ProfileDateTimeFormat.supportedLocalesOf = NativeDateTimeFormat.supportedLocalesOf.bind(NativeDateTimeFormat);
                    Intl.DateTimeFormat = ProfileDateTimeFormat;
                } catch (_) {}
            }

            if (environment.viewportWidth) {
                const applyViewport = function() {
                    if (!document.head) return;
                    let viewport = document.querySelector('meta[name="viewport"]');
                    if (!viewport) {
                        viewport = document.createElement('meta');
                        viewport.name = 'viewport';
                        document.head.appendChild(viewport);
                    }
                    viewport.content = 'width=' + environment.viewportWidth + ', initial-scale=1.0, maximum-scale=5.0, viewport-fit=cover';
                    document.documentElement.setAttribute('data-next-multibrowser-viewport', environment.devicePreset || 'Custom');
                };
                applyViewport();
                document.addEventListener('DOMContentLoaded', applyViewport, { once: true });
            }
        })();
        """#
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }
}
