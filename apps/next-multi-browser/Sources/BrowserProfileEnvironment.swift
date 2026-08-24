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
    case iPodSafari
    case iPadSafari
    case pixelChrome
    case galaxyChrome
    case desktopSafari
    case desktopChrome

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .iPhoneSafari: return "Safari — iPhone"
        case .iPodSafari: return "Safari — iPod touch"
        case .iPadSafari: return "Safari — iPad"
        case .pixelChrome: return "Chrome — Google Pixel"
        case .galaxyChrome: return "Chrome — Samsung Galaxy"
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
        case .iPodSafari:
            return "Mozilla/5.0 (iPod touch; CPU iPhone OS 15_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1"
        case .iPadSafari:
            return "Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        case .pixelChrome:
            return "Mozilla/5.0 (Linux; Android 15; Pixel 9 Pro) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36"
        case .galaxyChrome:
            return "Mozilla/5.0 (Linux; Android 15; SM-S938B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36"
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
    case spanish
    case italian
    case portuguese
    case hindi
    case turkish
    case russian
    case chineseSimplified
    case korean
    case indonesian
    case dutch

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .english: return "English"
        case .arabic: return "Arabic"
        case .urdu: return "Urdu"
        case .french: return "French"
        case .german: return "German"
        case .japanese: return "Japanese"
        case .spanish: return "Spanish"
        case .italian: return "Italian"
        case .portuguese: return "Portuguese"
        case .hindi: return "Hindi"
        case .turkish: return "Turkish"
        case .russian: return "Russian"
        case .chineseSimplified: return "Chinese — Simplified"
        case .korean: return "Korean"
        case .indonesian: return "Indonesian"
        case .dutch: return "Dutch"
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
        case .spanish: return "es"
        case .italian: return "it"
        case .portuguese: return "pt"
        case .hindi: return "hi"
        case .turkish: return "tr"
        case .russian: return "ru"
        case .chineseSimplified: return "zh"
        case .korean: return "ko"
        case .indonesian: return "id"
        case .dutch: return "nl"
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
    case canada
    case australia
    case unitedArabEmirates
    case saudiArabia
    case india
    case france
    case spain
    case italy
    case netherlands
    case brazil
    case mexico
    case singapore
    case southKorea
    case china
    case turkey
    case indonesia
    case russia

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .unitedStates: return "United States"
        case .qatar: return "Qatar"
        case .pakistan: return "Pakistan"
        case .unitedKingdom: return "United Kingdom"
        case .germany: return "Germany"
        case .japan: return "Japan"
        case .canada: return "Canada"
        case .australia: return "Australia"
        case .unitedArabEmirates: return "United Arab Emirates"
        case .saudiArabia: return "Saudi Arabia"
        case .india: return "India"
        case .france: return "France"
        case .spain: return "Spain"
        case .italy: return "Italy"
        case .netherlands: return "Netherlands"
        case .brazil: return "Brazil"
        case .mexico: return "Mexico"
        case .singapore: return "Singapore"
        case .southKorea: return "South Korea"
        case .china: return "China"
        case .turkey: return "Turkey"
        case .indonesia: return "Indonesia"
        case .russia: return "Russia"
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
        case .canada: return "CA"
        case .australia: return "AU"
        case .unitedArabEmirates: return "AE"
        case .saudiArabia: return "SA"
        case .india: return "IN"
        case .france: return "FR"
        case .spain: return "ES"
        case .italy: return "IT"
        case .netherlands: return "NL"
        case .brazil: return "BR"
        case .mexico: return "MX"
        case .singapore: return "SG"
        case .southKorea: return "KR"
        case .china: return "CN"
        case .turkey: return "TR"
        case .indonesia: return "ID"
        case .russia: return "RU"
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
    case losAngeles
    case chicago
    case toronto
    case vancouver
    case sydney
    case dubai
    case riyadh
    case kolkata
    case paris
    case madrid
    case rome
    case amsterdam
    case saoPaulo
    case mexicoCity
    case singapore
    case seoul
    case shanghai
    case istanbul
    case jakarta
    case moscow

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .doha: return "Doha"
        case .newYork: return "New York"
        case .london: return "London"
        case .karachi: return "Karachi"
        case .berlin: return "Berlin"
        case .tokyo: return "Tokyo"
        case .losAngeles: return "Los Angeles"
        case .chicago: return "Chicago"
        case .toronto: return "Toronto"
        case .vancouver: return "Vancouver"
        case .sydney: return "Sydney"
        case .dubai: return "Dubai"
        case .riyadh: return "Riyadh"
        case .kolkata: return "Kolkata"
        case .paris: return "Paris"
        case .madrid: return "Madrid"
        case .rome: return "Rome"
        case .amsterdam: return "Amsterdam"
        case .saoPaulo: return "São Paulo"
        case .mexicoCity: return "Mexico City"
        case .singapore: return "Singapore"
        case .seoul: return "Seoul"
        case .shanghai: return "Shanghai"
        case .istanbul: return "Istanbul"
        case .jakarta: return "Jakarta"
        case .moscow: return "Moscow"
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
        case .losAngeles: return "America/Los_Angeles"
        case .chicago: return "America/Chicago"
        case .toronto: return "America/Toronto"
        case .vancouver: return "America/Vancouver"
        case .sydney: return "Australia/Sydney"
        case .dubai: return "Asia/Dubai"
        case .riyadh: return "Asia/Riyadh"
        case .kolkata: return "Asia/Kolkata"
        case .paris: return "Europe/Paris"
        case .madrid: return "Europe/Madrid"
        case .rome: return "Europe/Rome"
        case .amsterdam: return "Europe/Amsterdam"
        case .saoPaulo: return "America/Sao_Paulo"
        case .mexicoCity: return "America/Mexico_City"
        case .singapore: return "Asia/Singapore"
        case .seoul: return "Asia/Seoul"
        case .shanghai: return "Asia/Shanghai"
        case .istanbul: return "Europe/Istanbul"
        case .jakarta: return "Asia/Jakarta"
        case .moscow: return "Europe/Moscow"
        }
    }
}

enum BrowserViewportPreset: String, CaseIterable, Codable {
    case automatic
    case iPhoneSE
    case iPhone8Plus
    case iPhone13Mini
    case iPhone11
    case iPhone14
    case iPhonePro
    case iPhoneProMax
    case iPhone16Pro
    case iPhone16ProMax
    case iPodTouch
    case iPadMini
    case iPadAir
    case iPadPro11
    case iPadPro
    case pixel9Pro
    case galaxyS25Ultra
    case laptop
    case desktop

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .iPhoneSE: return "iPhone SE"
        case .iPhone8Plus: return "iPhone 8 Plus"
        case .iPhone13Mini: return "iPhone 13 mini"
        case .iPhone11: return "iPhone 11"
        case .iPhone14: return "iPhone 14"
        case .iPhonePro: return "iPhone 15 Pro"
        case .iPhoneProMax: return "iPhone 15 Pro Max"
        case .iPhone16Pro: return "iPhone 16 Pro"
        case .iPhone16ProMax: return "iPhone 16 Pro Max"
        case .iPodTouch: return "iPod touch 7"
        case .iPadMini: return "iPad mini"
        case .iPadAir: return "iPad Air 11-inch"
        case .iPadPro11: return "iPad Pro 11-inch"
        case .iPadPro: return "iPad Pro 13-inch"
        case .pixel9Pro: return "Google Pixel 9 Pro"
        case .galaxyS25Ultra: return "Samsung Galaxy S25 Ultra"
        case .laptop: return "Laptop"
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
        case .iPhone8Plus: return CGSize(width: 414, height: 736)
        case .iPhone13Mini: return CGSize(width: 375, height: 812)
        case .iPhone11: return CGSize(width: 414, height: 896)
        case .iPhone14: return CGSize(width: 390, height: 844)
        case .iPhonePro: return CGSize(width: 393, height: 852)
        case .iPhoneProMax: return CGSize(width: 430, height: 932)
        case .iPhone16Pro: return CGSize(width: 402, height: 874)
        case .iPhone16ProMax: return CGSize(width: 440, height: 956)
        case .iPodTouch: return CGSize(width: 320, height: 568)
        case .iPadMini: return CGSize(width: 744, height: 1133)
        case .iPadAir: return CGSize(width: 820, height: 1180)
        case .iPadPro11: return CGSize(width: 834, height: 1194)
        case .iPadPro: return CGSize(width: 1024, height: 1366)
        case .pixel9Pro: return CGSize(width: 412, height: 915)
        case .galaxyS25Ultra: return CGSize(width: 384, height: 854)
        case .laptop: return CGSize(width: 1366, height: 768)
        case .desktop: return CGSize(width: 1440, height: 900)
        }
    }

    var prefersDesktopContent: Bool { self == .laptop || self == .desktop }

    var compatibleUserAgents: [BrowserUserAgentPreset] {
        switch self {
        case .automatic:
            return [.automatic]
        case .iPhoneSE, .iPhone8Plus, .iPhone13Mini, .iPhone11, .iPhone14,
             .iPhonePro, .iPhoneProMax, .iPhone16Pro, .iPhone16ProMax:
            return [.iPhoneSafari]
        case .iPodTouch:
            return [.iPodSafari]
        case .iPadMini, .iPadAir, .iPadPro11, .iPadPro:
            return [.iPadSafari]
        case .pixel9Pro:
            return [.pixelChrome]
        case .galaxyS25Ultra:
            return [.galaxyChrome]
        case .laptop, .desktop:
            return [.desktopSafari, .desktopChrome]
        }
    }

    static var randomizableCases: [BrowserViewportPreset] {
        allCases.filter { $0 != .automatic }
    }
}

struct BrowserEnvironmentLocationPreset: Equatable {
    let language: BrowserLanguagePreset
    let region: BrowserRegionPreset
    let timezone: BrowserTimezonePreset

    static let all: [BrowserEnvironmentLocationPreset] = [
        .init(language: .english, region: .unitedStates, timezone: .newYork),
        .init(language: .english, region: .unitedStates, timezone: .losAngeles),
        .init(language: .english, region: .unitedStates, timezone: .chicago),
        .init(language: .english, region: .canada, timezone: .toronto),
        .init(language: .english, region: .canada, timezone: .vancouver),
        .init(language: .english, region: .unitedKingdom, timezone: .london),
        .init(language: .arabic, region: .qatar, timezone: .doha),
        .init(language: .arabic, region: .unitedArabEmirates, timezone: .dubai),
        .init(language: .arabic, region: .saudiArabia, timezone: .riyadh),
        .init(language: .urdu, region: .pakistan, timezone: .karachi),
        .init(language: .hindi, region: .india, timezone: .kolkata),
        .init(language: .german, region: .germany, timezone: .berlin),
        .init(language: .french, region: .france, timezone: .paris),
        .init(language: .spanish, region: .spain, timezone: .madrid),
        .init(language: .italian, region: .italy, timezone: .rome),
        .init(language: .dutch, region: .netherlands, timezone: .amsterdam),
        .init(language: .japanese, region: .japan, timezone: .tokyo),
        .init(language: .korean, region: .southKorea, timezone: .seoul),
        .init(language: .chineseSimplified, region: .china, timezone: .shanghai),
        .init(language: .english, region: .singapore, timezone: .singapore),
        .init(language: .english, region: .australia, timezone: .sydney),
        .init(language: .portuguese, region: .brazil, timezone: .saoPaulo),
        .init(language: .spanish, region: .mexico, timezone: .mexicoCity),
        .init(language: .turkish, region: .turkey, timezone: .istanbul),
        .init(language: .indonesian, region: .indonesia, timezone: .jakarta),
        .init(language: .russian, region: .russia, timezone: .moscow)
    ]
}

struct BrowserProfileEnvironment: Codable, Equatable {
    var userAgent: BrowserUserAgentPreset = .automatic
    var language: BrowserLanguagePreset = .automatic
    var region: BrowserRegionPreset = .automatic
    var timezone: BrowserTimezonePreset = .automatic
    var viewport: BrowserViewportPreset = .automatic

    static let `default` = BrowserProfileEnvironment()

    static func randomized(excluding current: BrowserProfileEnvironment? = nil) -> BrowserProfileEnvironment {
        let candidates = BrowserViewportPreset.randomizableCases.flatMap { viewport in
            BrowserEnvironmentLocationPreset.all.flatMap { location in
                viewport.compatibleUserAgents.map { userAgent in
                    BrowserProfileEnvironment(
                        userAgent: userAgent,
                        language: location.language,
                        region: location.region,
                        timezone: location.timezone,
                        viewport: viewport
                    )
                }
            }
        }.filter { candidate in
            current.map { candidate != $0 } ?? true
        }

        return candidates.randomElement() ?? .default
    }

    var usesCoherentRandomPreset: Bool {
        guard viewport != .automatic,
              viewport.compatibleUserAgents.contains(userAgent) else {
            return false
        }
        return BrowserEnvironmentLocationPreset.all.contains {
            $0.language == language && $0.region == region && $0.timezone == timezone
        }
    }

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
