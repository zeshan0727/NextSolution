import XCTest
@testable import KBAClient

final class ServiceCatalogTests: XCTestCase {
    func testCatalogContainsWebsiteServiceGroups() {
        XCTAssertEqual(ServiceCatalog.all.count, 8)
        XCTAssertTrue(ServiceCatalog.all.contains { $0.id == "uk-payroll" })
        XCTAssertTrue(ServiceCatalog.all.contains { $0.id == "usa-setup-tax" })
        XCTAssertTrue(ServiceCatalog.all.contains { $0.id == "qatar-payroll-advisory" })
        XCTAssertTrue(ServiceCatalog.all.contains { $0.id == "irs-itin-ein" })
    }

    func testQatarFilterIncludesQatarService() {
        let services = ServiceCatalog.services(for: .qatar)
        XCTAssertTrue(services.contains { $0.id == "qatar-payroll-advisory" })
        XCTAssertFalse(services.contains { $0.id == "uk-payroll" })
    }

    func testReferenceFormatIsStable() {
        let date = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01 UTC
        let reference = AppStore.makeReference(date: date, suffix: 1234)
        XCTAssertTrue(reference.hasPrefix("KBA-"))
        XCTAssertTrue(reference.hasSuffix("-1234"))
    }
}
