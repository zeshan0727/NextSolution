import XCTest
import WebKit
@testable import Next_Multi_Browser

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
        profileTwoEnvironment.viewport = .iPadPro
        profileTwoEnvironment.language = .arabic
        profileTwoEnvironment.region = .qatar
        firstStore.setDisplayName("Google Test 02", for: 2)
        firstStore.setEnvironment(profileTwoEnvironment, for: 2)

        let relaunchedStore = BrowserProfileStore(
            defaults: defaults,
            profilesRootDirectory: root,
            usesNamedDataStoreWhenAvailable: true
        )
        XCTAssertEqual(relaunchedStore.displayName(for: 1), "Google Test 01")
        XCTAssertEqual(relaunchedStore.environment(for: 1), profileOneEnvironment)
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
        XCTAssertEqual(firstStore.environment(for: 2), profileTwoEnvironment)

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
