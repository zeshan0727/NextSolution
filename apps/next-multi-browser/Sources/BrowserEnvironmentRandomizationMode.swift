import Foundation

enum BrowserEnvironmentRandomizationMode: String, CaseIterable {
    case iOS
    case android
    case desktop
    case mixed

    var title: String {
        switch self {
        case .iOS: return "iOS Mode"
        case .android: return "Android Mode"
        case .desktop: return "PC / Mac Mode"
        case .mixed: return "Mixed Mode"
        }
    }

    var subtitle: String {
        switch self {
        case .iOS: return "Random iPhone devices"
        case .android: return "Random Android phones"
        case .desktop: return "Random Windows Chrome or macOS Safari"
        case .mixed: return "Random iOS, Android, Windows, and macOS"
        }
    }

    var symbolName: String {
        switch self {
        case .iOS: return "iphone"
        case .android: return "rectangle.portrait"
        case .desktop: return "desktopcomputer"
        case .mixed: return "square.grid.2x2"
        }
    }

    func randomizedBatch(
        count: Int,
        excluding environments: [BrowserProfileEnvironment] = []
    ) -> [BrowserProfileEnvironment] {
        guard count > 0 else { return [] }
        let excluded = Set(environments)
        var candidates = candidateEnvironments.filter { !excluded.contains($0) }
        candidates.shuffle()

        if candidates.count >= count {
            return Array(candidates.prefix(count))
        }

        var result = candidates
        let fallback = candidateEnvironments.shuffled()
        while result.count < count, !fallback.isEmpty {
            result.append(fallback[result.count % fallback.count])
        }
        return result
    }

    private var candidateEnvironments: [BrowserProfileEnvironment] {
        viewports.flatMap { viewport in
            BrowserEnvironmentLocationPreset.all.flatMap { location in
                compatibleUserAgents(for: viewport).map { userAgent in
                    BrowserProfileEnvironment(
                        userAgent: userAgent,
                        language: location.language,
                        region: location.region,
                        timezone: location.timezone,
                        viewport: viewport
                    )
                }
            }
        }
    }

    private var viewports: [BrowserViewportPreset] {
        switch self {
        case .iOS:
            return [
                .iPhoneSE,
                .iPhone8Plus,
                .iPhone13Mini,
                .iPhone11,
                .iPhone14,
                .iPhonePro,
                .iPhoneProMax,
                .iPhone16Pro,
                .iPhone16ProMax
            ]
        case .android:
            return [
                .pixel9Pro,
                .pixel9ProXL,
                .galaxyS25,
                .galaxyS25Ultra,
                .onePlus13,
                .xiaomi15Ultra
            ]
        case .desktop:
            return [.desktop]
        case .mixed:
            return BrowserEnvironmentRandomizationMode.iOS.viewports
                + BrowserEnvironmentRandomizationMode.android.viewports
                + BrowserEnvironmentRandomizationMode.desktop.viewports
        }
    }

    private func compatibleUserAgents(for viewport: BrowserViewportPreset) -> [BrowserUserAgentPreset] {
        switch self {
        case .desktop:
            return [.desktopSafari, .desktopChrome]
        case .mixed where viewport == .desktop:
            return [.desktopSafari, .desktopChrome]
        default:
            return viewport.compatibleUserAgents
        }
    }
}
