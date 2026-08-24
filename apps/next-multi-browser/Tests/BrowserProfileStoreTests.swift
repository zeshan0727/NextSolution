import XCTest
import WebKit

@available(iOS 17.0, *)
@MainActor
final class BrowserProfileStoreTests: XCTestCase {
    func testTwentyProfilesRemainIsolatedPersistentAndDeleteSafely() async throws {
        let suiteName = "com.nextsolution.multibrowser.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create isolated test defaults")
            return
        }
        defaults.removePersistentDomain(forName: suiteName)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NextMultiBrowserTests-\(UUID().uuidString)", isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }

        let firstStore = BrowserProfileStore(
            defaults: defaults,
            profilesRootDirectory: root,
            usesNamedDataStoreWhenAvailable: true
        )

        let identifiers = (1...BrowserProfileStore.profileCount).map {
            firstStore.persistentIdentifier(for: $0)
        }
        XCTAssertEqual(
            Set(identifiers).count,
            BrowserProfileStore.profileCount,
            "All 20 profiles must have unique persistent identifiers"
        )

        var sessions = (1...BrowserProfileStore.profileCount).map {
            firstStore.session(for: $0)
        }
        for session in sessions {
            await waitUntilReady(session)
            XCTAssertTrue(session.dataStore.isPersistent)
        }
        XCTAssertEqual(
            Set(sessions.map { ObjectIdentifier($0.dataStore) }).count,
            BrowserProfileStore.profileCount,
            "All 20 profiles must use separate WKWebsiteDataStore objects"
        )

        let profileOneCookie = makeCookie(name: "NMB_PROFILE", value: "profile-one")
        let profileTwoCookie = makeCookie(name: "NMB_PROFILE", value: "profile-two")
        await setCookie(profileOneCookie, in: sessions[0].dataStore.httpCookieStore)
        await setCookie(profileTwoCookie, in: sessions[1].dataStore.httpCookieStore)

        let firstCookieValue = await cookieValue(
            named: "NMB_PROFILE",
            in: sessions[0].dataStore.httpCookieStore
        )
        let secondCookieValue = await cookieValue(
            named: "NMB_PROFILE",
            in: sessions[1].dataStore.httpCookieStore
        )
        XCTAssertEqual(firstCookieValue, "profile-one")
        XCTAssertEqual(secondCookieValue, "profile-two")

        var profileOneEnvironment = BrowserProfileEnvironment.default
        profileOneEnvironment.viewport = .iPhonePro
        profileOneEnvironment.language = .english
        profileOneEnvironment.region = .unitedStates
        firstStore.setDisplayName("Google Test 01", for: 1)
        firstStore.setEnvironment(profileOneEnvironment, for: 1)

        var profileTwoEnvironment = BrowserProfileEnvironment.default
        profileTwoEnvironment.viewport = .pixel9Pro
        profileTwoEnvironment.userAgent = .pixelChrome
        profileTwoEnvironment.language = .arabic
        profileTwoEnvironment.region = .qatar
        firstStore.setDisplayName("Google Test 02", for: 2)
        firstStore.setEnvironment(profileTwoEnvironment, for: 2)

        let randomizedEnvironment = BrowserProfileEnvironment.randomized(
            excluding: profileOneEnvironment
        )
        XCTAssertNotEqual(randomizedEnvironment, profileOneEnvironment)
        XCTAssertTrue(
            randomizedEnvironment.usesCoherentRandomPreset,
            "Randomization must select a compatible device, user agent, language, region, and timezone"
        )
        XCTAssertNotEqual(randomizedEnvironment.viewport, .automatic)
        XCTAssertNotEqual(randomizedEnvironment.userAgent, .automatic)
        XCTAssertNotEqual(randomizedEnvironment.language, .automatic)
        XCTAssertNotEqual(randomizedEnvironment.region, .automatic)
        XCTAssertNotEqual(randomizedEnvironment.timezone, .automatic)
        XCTAssertEqual(BrowserViewportPreset.selectablePhoneCases.count, 16)
        XCTAssertFalse(BrowserViewportPreset.selectablePhoneCases.contains(.iPodTouch))
        XCTAssertFalse(BrowserViewportPreset.selectablePhoneCases.contains(.iPadPro))
        XCTAssertFalse(BrowserViewportPreset.selectablePhoneCases.contains(.desktop))
        XCTAssertTrue(BrowserViewportPreset.selectablePhoneCases.contains(.pixel9ProXL))
        XCTAssertTrue(BrowserViewportPreset.selectablePhoneCases.contains(.galaxyS25))
        XCTAssertTrue(BrowserViewportPreset.selectablePhoneCases.contains(.onePlus13))
        XCTAssertTrue(BrowserViewportPreset.selectablePhoneCases.contains(.xiaomi15Ultra))
        XCTAssertEqual(BrowserUserAgentPreset.selectablePhoneCases.count, 8)
        XCTAssertFalse(BrowserUserAgentPreset.selectablePhoneCases.contains(.iPadSafari))
        XCTAssertFalse(BrowserUserAgentPreset.selectablePhoneCases.contains(.desktopSafari))
        XCTAssertGreaterThanOrEqual(BrowserLanguagePreset.allCases.count, 17)
        XCTAssertGreaterThanOrEqual(BrowserRegionPreset.allCases.count, 24)
        XCTAssertGreaterThanOrEqual(BrowserTimezonePreset.allCases.count, 27)

        firstStore.setEnvironment(randomizedEnvironment, for: 1)
        XCTAssertEqual(
            firstStore.environment(for: 2),
            profileTwoEnvironment,
            "Randomizing Profile 1 must not change Profile 2"
        )
        let profileOneCookieAfterRandomizing = await cookieValue(
            named: "NMB_PROFILE",
            in: sessions[0].dataStore.httpCookieStore
        )
        let profileTwoCookieAfterRandomizing = await cookieValue(
            named: "NMB_PROFILE",
            in: sessions[1].dataStore.httpCookieStore
        )
        XCTAssertEqual(
            profileOneCookieAfterRandomizing,
            "profile-one",
            "Randomizing an environment must not clear that profile's login cookie"
        )
        XCTAssertEqual(
            profileTwoCookieAfterRandomizing,
            "profile-two",
            "Randomizing Profile 1 must not affect Profile 2's login cookie"
        )

        var legacyTabletEnvironment = BrowserProfileEnvironment.default
        legacyTabletEnvironment.viewport = .iPadPro
        legacyTabletEnvironment.userAgent = .iPadSafari
        legacyTabletEnvironment.language = .english
        legacyTabletEnvironment.region = .unitedStates
        defaults.set(
            try JSONEncoder().encode(legacyTabletEnvironment),
            forKey: "NextMultiBrowser.profile.3.environment"
        )
        let migratedEnvironment = firstStore.environment(for: 3)
        XCTAssertTrue(migratedEnvironment.isPhoneOnly)
        XCTAssertEqual(migratedEnvironment.viewport, .iPhoneProMax)
        XCTAssertEqual(migratedEnvironment.userAgent, .iPhoneSafari)

        let environmentsBeforeGlobalRandomization = (1...BrowserProfileStore.profileCount).map {
            firstStore.environment(for: $0)
        }
        let globallyRandomized = firstStore.randomizeAllEnvironments()
        XCTAssertEqual(globallyRandomized.count, BrowserProfileStore.profileCount)
        XCTAssertEqual(
            Set(globallyRandomized).count,
            BrowserProfileStore.profileCount,
            "Global randomization must create 20 unique environment combinations"
        )
        XCTAssertTrue(
            globallyRandomized.allSatisfy { $0.isPhoneOnly && $0.usesCoherentRandomPreset },
            "Every global environment must be a coherent phone-only preset"
        )
        XCTAssertTrue(
            Set(globallyRandomized).isDisjoint(with: Set(environmentsBeforeGlobalRandomization)),
            "Global randomization must replace every previous environment"
        )
        XCTAssertEqual(
            (1...BrowserProfileStore.profileCount).map { firstStore.environment(for: $0) },
            globallyRandomized,
            "All 20 randomized environments must be saved to their matching profile"
        )
        XCTAssertEqual(
            (1...BrowserProfileStore.profileCount).map { firstStore.persistentIdentifier(for: $0) },
            identifiers,
            "Global randomization must not replace any persistent website-data store"
        )

        let profileOneCookieAfterGlobalRandomizing = await cookieValue(
            named: "NMB_PROFILE",
            in: sessions[0].dataStore.httpCookieStore
        )
        let profileTwoCookieAfterGlobalRandomizing = await cookieValue(
            named: "NMB_PROFILE",
            in: sessions[1].dataStore.httpCookieStore
        )
        XCTAssertEqual(profileOneCookieAfterGlobalRandomizing, "profile-one")
        XCTAssertEqual(profileTwoCookieAfterGlobalRandomizing, "profile-two")

        let relaunchedStore = BrowserProfileStore(
            defaults: defaults,
            profilesRootDirectory: root,
            usesNamedDataStoreWhenAvailable: true
        )
        XCTAssertEqual(relaunchedStore.displayName(for: 1), "Google Test 01")
        XCTAssertEqual(relaunchedStore.environment(for: 1), globallyRandomized[0])
        XCTAssertEqual(
            (1...BrowserProfileStore.profileCount).map { relaunchedStore.environment(for: $0) },
            globallyRandomized,
            "A relaunch must restore all 20 globally randomized environments"
        )
        XCTAssertEqual(
            relaunchedStore.persistentIdentifier(for: 1),
            identifiers[0],
            "A relaunch must restore the same named WebKit store"
        )

        let relaunchedSession = relaunchedStore.session(for: 1)
        await waitUntilReady(relaunchedSession)
        let relaunchedCookieValue = await cookieValue(
            named: "NMB_PROFILE",
            in: relaunchedSession.dataStore.httpCookieStore
        )
        XCTAssertEqual(
            relaunchedCookieValue,
            "profile-one",
            "The profile cookie must survive reconstruction of the app store"
        )

        await deleteProfile(1, from: firstStore)
        let deletedProfileCookie = await cookieValue(
            named: "NMB_PROFILE",
            in: sessions[0].dataStore.httpCookieStore
        )
        let unaffectedProfileCookie = await cookieValue(
            named: "NMB_PROFILE",
            in: sessions[1].dataStore.httpCookieStore
        )
        XCTAssertNil(
            deletedProfileCookie,
            "Deleting Profile 1 must clear Profile 1"
        )
        XCTAssertEqual(
            unaffectedProfileCookie,
            "profile-two",
            "Deleting Profile 1 must not affect Profile 2"
        )
        XCTAssertEqual(firstStore.displayName(for: 1), "Browser 1")
        XCTAssertEqual(firstStore.environment(for: 1), .default)
        XCTAssertEqual(firstStore.displayName(for: 2), "Google Test 02")
        XCTAssertEqual(firstStore.environment(for: 2), globallyRandomized[1])

        sessions.removeAll()
    }

    private func makeCookie(name: String, value: String) -> HTTPCookie {
        let cookie = HTTPCookie(properties: [
            .domain: "example.com",
            .path: "/",
            .name: name,
            .value: value,
            .secure: "TRUE",
            .expires: Date().addingTimeInterval(86_400)
        ])
        XCTAssertNotNil(cookie)
        return cookie!
    }

    private func waitUntilReady(_ session: BrowserProfileSession) async {
        await withCheckedContinuation { continuation in
            session.whenReady {
                continuation.resume()
            }
        }
    }

    private func setCookie(_ cookie: HTTPCookie, in store: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in
            store.setCookie(cookie) {
                continuation.resume()
            }
        }
    }

    private func cookieValue(named name: String, in store: WKHTTPCookieStore) async -> String? {
        await withCheckedContinuation { continuation in
            store.getAllCookies { cookies in
                continuation.resume(returning: cookies.first { $0.name == name }?.value)
            }
        }
    }

    private func deleteProfile(_ index: Int, from store: BrowserProfileStore) async {
        await withCheckedContinuation { continuation in
            store.deleteProfile(index) {
                continuation.resume()
            }
        }
    }
}
