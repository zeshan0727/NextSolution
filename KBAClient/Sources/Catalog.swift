// MARK: - Sources/Services/ServiceCatalog.swift
import Foundation

enum ServiceCatalog {
    static let all: [KBAService] = [
        KBAService(
            id: "uk-payroll",
            title: "Payroll Outsourcing",
            summary: "Compliant, cost-effective payroll support for UK charities and SMEs.",
            details: "Outsource recurring payroll processing and compliance while keeping a clear customer contact point for questions, documents and deadlines.",
            systemImage: "person.2.badge.gearshape",
            jurisdictions: [.unitedKingdom],
            highlights: ["Charities with 50–1,000+ employees", "SME payroll processing", "Compliance and payroll reporting"]
        ),
        KBAService(
            id: "usa-setup-tax",
            title: "USA Business Setup & Tax",
            summary: "LLC or corporation formation, tax IDs and IRS filing support.",
            details: "Guidance for residents and non-residents establishing and maintaining a business in the United States.",
            systemImage: "building.columns.fill",
            jurisdictions: [.unitedStates],
            highlights: ["LLC and corporation formation", "EIN, ITIN and PTIN applications", "Personal and business tax filings"]
        ),
        KBAService(
            id: "uae-setup-tax",
            title: "UAE Business Setup & Tax",
            summary: "UAE company formation, VAT, corporate tax and payroll support.",
            details: "Business setup and ongoing compliance support for companies and entrepreneurs operating in the UAE.",
            systemImage: "building.2.crop.circle.fill",
            jurisdictions: [.unitedArabEmirates],
            highlights: ["Company formation", "VAT and corporate tax", "Payroll and ongoing compliance"]
        ),
        KBAService(
            id: "qatar-payroll-advisory",
            title: "Qatar Payroll & Advisory",
            summary: "Payroll outsourcing, business setup and advisory for Qatar.",
            details: "Support for local and international entities with payroll operations, setup choices and ongoing reporting.",
            systemImage: "briefcase.fill",
            jurisdictions: [.qatar],
            highlights: ["Payroll outsourcing and compliance", "LLC, branch and representative office setup", "Tax advisory for expats and businesses"]
        ),
        KBAService(
            id: "cross-border",
            title: "Cross-Border Advisory",
            summary: "Practical support across the UK, USA, UAE and Qatar.",
            details: "Plan and manage international expansion with coordinated setup, reporting, payroll and tax compliance.",
            systemImage: "globe.europe.africa.fill",
            jurisdictions: [.crossBorder, .unitedKingdom, .unitedStates, .unitedArabEmirates, .qatar],
            highlights: ["International business setup", "Multi-jurisdiction payroll and tax", "Bank account and operational support"]
        ),
        KBAService(
            id: "general-accounting-tax",
            title: "General Accounting & Tax",
            summary: "Bookkeeping, annual accounts, compliance reporting and tax returns.",
            details: "A coordinated accounting service for SMEs, expats and international businesses across multiple jurisdictions.",
            systemImage: "chart.pie.fill",
            jurisdictions: [.unitedKingdom, .unitedStates, .unitedArabEmirates, .qatar, .crossBorder],
            highlights: ["Bookkeeping and management accounts", "Personal and corporate tax returns", "UK GAAP, IFRS and local compliance"]
        ),
        KBAService(
            id: "valuation-due-diligence",
            title: "Valuation & Due Diligence",
            summary: "Independent business valuations and due diligence reporting.",
            details: "Request an independent valuation or due diligence engagement for a transaction, investment or strategic decision.",
            systemImage: "magnifyingglass.circle.fill",
            jurisdictions: [.unitedKingdom, .unitedStates, .unitedArabEmirates, .qatar, .crossBorder],
            highlights: ["Independent valuation", "Financial due diligence", "Decision-ready reporting"]
        ),
        KBAService(
            id: "irs-itin-ein",
            title: "IRS ITIN & EIN Services",
            summary: "Assistance with US tax identification applications.",
            details: "Structured support for ITIN and EIN applications, including non-resident cases and document readiness.",
            systemImage: "number.circle.fill",
            jurisdictions: [.unitedStates, .crossBorder],
            highlights: ["ITIN applications", "EIN applications", "Resident and non-resident guidance"]
        )
    ]

    static func services(for jurisdiction: Jurisdiction?) -> [KBAService] {
        guard let jurisdiction else { return all }
        return all.filter { $0.jurisdictions.contains(jurisdiction) }
    }

    static func service(id: String) -> KBAService? {
        all.first { $0.id == id }
    }
}
