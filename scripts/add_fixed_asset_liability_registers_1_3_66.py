from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(text, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected one match, got {count}: {old[:180]!r}")
    write(path, text.replace(old, new, 1))


# ---------------------------------------------------------------------------
# Next Ledger 1.3.66 / build 74. App-only update; SMS daemon remains 2.2.3.
# ---------------------------------------------------------------------------
replace_once("project.yml", 'MARKETING_VERSION: "1.3.65"', 'MARKETING_VERSION: "1.3.66"')
replace_once("project.yml", 'CURRENT_PROJECT_VERSION: "73"', 'CURRENT_PROJECT_VERSION: "74"')


# ---------------------------------------------------------------------------
# Models: proper Fixed Asset / Fixed Liability account natures and persistent
# accounting register records stored inside LedgerSettings / ledger.json.
# ---------------------------------------------------------------------------
model = "DailyLedger/Models/LedgerTransaction.swift"
text = read(model)
text = text.replace(
'''    case asset
    case dailyExpense
    case bank
''',
'''    case asset
    case fixedAsset
    case fixedLiability
    case dailyExpense
    case bank
''', 1)
text = text.replace(
'''        case .asset: return "Asset"
        case .dailyExpense: return "Daily Expense"
''',
'''        case .asset: return "Asset"
        case .fixedAsset: return "Fixed Asset"
        case .fixedLiability: return "Fixed Liability"
        case .dailyExpense: return "Daily Expense"
''', 1)

settings_anchor = "struct LedgerSettings: Codable, Equatable {\n"
if text.count(settings_anchor) != 1:
    raise RuntimeError("LedgerSettings anchor missing")

register_models = r'''enum FixedAssetStatus: String, Codable, CaseIterable, Identifiable {
    case active
    case sold
    case disposed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .active: return "Active"
        case .sold: return "Sold"
        case .disposed: return "Disposed"
        }
    }
}

enum FixedAssetDepreciationMethod: String, Codable, CaseIterable, Identifiable {
    case straightLineRate
    case straightLineLife
    case none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .straightLineRate: return "Straight Line %"
        case .straightLineLife: return "Straight Line Life"
        case .none: return "No Depreciation"
        }
    }
}

struct FixedAssetRecord: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var assetNumber: String
    var name: String
    var category: String
    var currencyCode: String
    var linkedAccountID: UUID?
    var purchaseDate: Date
    var cost: Decimal
    var residualValue: Decimal
    var depreciationStartDate: Date
    var depreciationMethod: FixedAssetDepreciationMethod
    var annualDepreciationRate: Decimal
    var usefulLifeMonths: Int
    var openingAccumulatedDepreciation: Decimal
    var status: FixedAssetStatus
    var disposalDate: Date?
    var disposalProceeds: Decimal?
    var disposalReason: String
    var notes: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        assetNumber: String = "",
        name: String = "",
        category: String = "Furniture & Fixtures",
        currencyCode: String = "QAR",
        linkedAccountID: UUID? = nil,
        purchaseDate: Date = Date(),
        cost: Decimal = 0,
        residualValue: Decimal = 0,
        depreciationStartDate: Date = Date(),
        depreciationMethod: FixedAssetDepreciationMethod = .straightLineRate,
        annualDepreciationRate: Decimal = 15,
        usefulLifeMonths: Int = 60,
        openingAccumulatedDepreciation: Decimal = 0,
        status: FixedAssetStatus = .active,
        disposalDate: Date? = nil,
        disposalProceeds: Decimal? = nil,
        disposalReason: String = "",
        notes: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.assetNumber = assetNumber
        self.name = name
        self.category = category
        self.currencyCode = currencyCode
        self.linkedAccountID = linkedAccountID
        self.purchaseDate = purchaseDate
        self.cost = cost
        self.residualValue = residualValue
        self.depreciationStartDate = depreciationStartDate
        self.depreciationMethod = depreciationMethod
        self.annualDepreciationRate = annualDepreciationRate
        self.usefulLifeMonths = usefulLifeMonths
        self.openingAccumulatedDepreciation = openingAccumulatedDepreciation
        self.status = status
        self.disposalDate = disposalDate
        self.disposalProceeds = disposalProceeds
        self.disposalReason = disposalReason
        self.notes = notes
        self.createdAt = createdAt
    }

    static let defaultCategories = [
        "Furniture & Fixtures", "Computers & IT Equipment", "Office Equipment",
        "Motor Vehicles", "Machinery & Equipment", "Leasehold Improvements",
        "Buildings", "Right-of-Use Assets", "Other Fixed Assets"
    ]

    var depreciableAmount: Decimal { max(0, cost - max(0, residualValue)) }

    func accumulatedDepreciation(asOf requestedDate: Date, calendar: Calendar = .current) -> Decimal {
        let terminalDate: Date
        if status != .active, let disposalDate {
            terminalDate = min(requestedDate, disposalDate)
        } else {
            terminalDate = requestedDate
        }
        let opening = min(max(0, openingAccumulatedDepreciation), depreciableAmount)
        guard terminalDate >= depreciationStartDate, depreciationMethod != .none else { return opening }
        let startComponents = calendar.dateComponents([.year, .month], from: depreciationStartDate)
        let endComponents = calendar.dateComponents([.year, .month], from: terminalDate)
        guard let startMonth = calendar.date(from: startComponents),
              let endMonth = calendar.date(from: endComponents) else { return opening }
        let elapsed = max(0, calendar.dateComponents([.month], from: startMonth, to: endMonth).month ?? 0)
        let months = elapsed + 1 // full-month convention
        let monthly: Decimal
        switch depreciationMethod {
        case .straightLineRate:
            monthly = cost * max(0, annualDepreciationRate) / Decimal(100) / Decimal(12)
        case .straightLineLife:
            monthly = usefulLifeMonths > 0 ? depreciableAmount / Decimal(usefulLifeMonths) : 0
        case .none:
            monthly = 0
        }
        return min(depreciableAmount, opening + monthly * Decimal(months))
    }

    func netBookValue(asOf date: Date) -> Decimal {
        max(0, cost - accumulatedDepreciation(asOf: date))
    }

    var disposalGainLoss: Decimal? {
        guard status != .active, let disposalDate else { return nil }
        return (disposalProceeds ?? 0) - netBookValue(asOf: disposalDate)
    }
}

enum FixedLiabilityStatus: String, Codable, CaseIterable, Identifiable {
    case active
    case settled
    var id: String { rawValue }
    var title: String { self == .active ? "Active" : "Settled" }
}

struct FixedLiabilityRecord: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var reference: String
    var name: String
    var category: String
    var lender: String
    var currencyCode: String
    var linkedAccountID: UUID?
    var startDate: Date
    var maturityDate: Date?
    var originalPrincipal: Decimal
    var annualInterestRate: Decimal
    var currentPortion: Decimal
    var status: FixedLiabilityStatus
    var settledDate: Date?
    var notes: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        reference: String = "",
        name: String = "",
        category: String = "Bank Loan",
        lender: String = "",
        currencyCode: String = "QAR",
        linkedAccountID: UUID? = nil,
        startDate: Date = Date(),
        maturityDate: Date? = nil,
        originalPrincipal: Decimal = 0,
        annualInterestRate: Decimal = 0,
        currentPortion: Decimal = 0,
        status: FixedLiabilityStatus = .active,
        settledDate: Date? = nil,
        notes: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.reference = reference
        self.name = name
        self.category = category
        self.lender = lender
        self.currencyCode = currencyCode
        self.linkedAccountID = linkedAccountID
        self.startDate = startDate
        self.maturityDate = maturityDate
        self.originalPrincipal = originalPrincipal
        self.annualInterestRate = annualInterestRate
        self.currentPortion = currentPortion
        self.status = status
        self.settledDate = settledDate
        self.notes = notes
        self.createdAt = createdAt
    }

    static let defaultCategories = [
        "Bank Loan", "Finance Lease / Lease Liability", "Vehicle Finance",
        "Related Party / Shareholder Loan", "Long-Term Payable", "Other Long-Term Liability"
    ]
}

'''
text = text.replace(settings_anchor, register_models + settings_anchor, 1)

# LedgerSettings stored properties.
text = text.replace(
'''    var incomeCategoryCodes: [String: String]
    var chartOfAccountsMigrationVersion: Int
''',
'''    var incomeCategoryCodes: [String: String]
    var chartOfAccountsMigrationVersion: Int
    var fixedAssetRecords: [FixedAssetRecord]
    var fixedAssetCategories: [String]
    var fixedLiabilityRecords: [FixedLiabilityRecord]
    var fixedLiabilityCategories: [String]
''', 1)

text = text.replace(
'''        incomeCategoryCodes: [String: String] = LedgerTransaction.defaultIncomeCategoryCodes,
        chartOfAccountsMigrationVersion: Int = 0
''',
'''        incomeCategoryCodes: [String: String] = LedgerTransaction.defaultIncomeCategoryCodes,
        chartOfAccountsMigrationVersion: Int = 0,
        fixedAssetRecords: [FixedAssetRecord] = [],
        fixedAssetCategories: [String] = FixedAssetRecord.defaultCategories,
        fixedLiabilityRecords: [FixedLiabilityRecord] = [],
        fixedLiabilityCategories: [String] = FixedLiabilityRecord.defaultCategories
''', 1)

text = text.replace(
'''        self.incomeCategoryCodes = incomeCategoryCodes
        self.chartOfAccountsMigrationVersion = chartOfAccountsMigrationVersion
''',
'''        self.incomeCategoryCodes = incomeCategoryCodes
        self.chartOfAccountsMigrationVersion = chartOfAccountsMigrationVersion
        self.fixedAssetRecords = fixedAssetRecords
        self.fixedAssetCategories = fixedAssetCategories
        self.fixedLiabilityRecords = fixedLiabilityRecords
        self.fixedLiabilityCategories = fixedLiabilityCategories
''', 1)

text = text.replace(
'''        case incomeCategoryCodes
        case chartOfAccountsMigrationVersion
''',
'''        case incomeCategoryCodes
        case chartOfAccountsMigrationVersion
        case fixedAssetRecords
        case fixedAssetCategories
        case fixedLiabilityRecords
        case fixedLiabilityCategories
''', 1)

text = text.replace(
'''        chartOfAccountsMigrationVersion = try values.decodeIfPresent(
            Int.self,
            forKey: .chartOfAccountsMigrationVersion
        ) ?? 0
''',
'''        chartOfAccountsMigrationVersion = try values.decodeIfPresent(
            Int.self,
            forKey: .chartOfAccountsMigrationVersion
        ) ?? 0
        fixedAssetRecords = try values.decodeIfPresent([FixedAssetRecord].self, forKey: .fixedAssetRecords) ?? []
        fixedAssetCategories = try values.decodeIfPresent([String].self, forKey: .fixedAssetCategories)
            ?? FixedAssetRecord.defaultCategories
        fixedLiabilityRecords = try values.decodeIfPresent([FixedLiabilityRecord].self, forKey: .fixedLiabilityRecords) ?? []
        fixedLiabilityCategories = try values.decodeIfPresent([String].self, forKey: .fixedLiabilityCategories)
            ?? FixedLiabilityRecord.defaultCategories
''', 1)
write(model, text)


# ---------------------------------------------------------------------------
# LedgerStore CRUD and linked-account classification.
# ---------------------------------------------------------------------------
store_path = "DailyLedger/Services/LedgerStore.swift"
text = read(store_path)
text = text.replace(
'''    var activeAccounts: [LedgerAccount] { accounts.filter { !$0.isArchived } }
''',
'''    var activeAccounts: [LedgerAccount] { accounts.filter { !$0.isArchived } }
    var fixedAssetRecords: [FixedAssetRecord] { settings.fixedAssetRecords }
    var fixedLiabilityRecords: [FixedLiabilityRecord] { settings.fixedLiabilityRecords }
    var fixedAssetCategories: [String] { settings.fixedAssetCategories }
    var fixedLiabilityCategories: [String] { settings.fixedLiabilityCategories }
''', 1)

crud_anchor = '''    func updateAccount(_ account: LedgerAccount) {
        updateLedger(failureMessage: "The account could not be updated.") { ledger in
            guard let index = ledger.accounts.firstIndex(where: { $0.id == account.id }) else { return }
            ledger.accounts[index] = account
        }
    }
'''
if text.count(crud_anchor) != 1:
    raise RuntimeError("updateAccount CRUD anchor missing")
crud = crud_anchor + r'''

    func saveFixedAssetRecord(_ record: FixedAssetRecord) {
        updateLedger(failureMessage: "The fixed asset could not be saved.") { ledger in
            var cleaned = record
            cleaned.assetNumber = record.assetNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.name = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.category = record.category.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.disposalReason = record.disposalReason.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.notes = record.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if let index = ledger.settings.fixedAssetRecords.firstIndex(where: { $0.id == record.id }) {
                ledger.settings.fixedAssetRecords[index] = cleaned
            } else {
                ledger.settings.fixedAssetRecords.append(cleaned)
            }
            if !cleaned.category.isEmpty,
               !ledger.settings.fixedAssetCategories.contains(where: { $0.caseInsensitiveCompare(cleaned.category) == .orderedSame }) {
                ledger.settings.fixedAssetCategories.append(cleaned.category)
                ledger.settings.fixedAssetCategories.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            }
            if let linked = cleaned.linkedAccountID,
               let index = ledger.accounts.firstIndex(where: { $0.id == linked }) {
                ledger.accounts[index].nature = .fixedAsset
            }
        }
    }

    func deleteFixedAssetRecord(_ id: UUID) {
        updateLedger(failureMessage: "The fixed asset could not be removed.") { ledger in
            ledger.settings.fixedAssetRecords.removeAll { $0.id == id }
        }
    }

    func saveFixedLiabilityRecord(_ record: FixedLiabilityRecord) {
        updateLedger(failureMessage: "The fixed liability could not be saved.") { ledger in
            var cleaned = record
            cleaned.reference = record.reference.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.name = record.name.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.category = record.category.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.lender = record.lender.trimmingCharacters(in: .whitespacesAndNewlines)
            cleaned.notes = record.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if let index = ledger.settings.fixedLiabilityRecords.firstIndex(where: { $0.id == record.id }) {
                ledger.settings.fixedLiabilityRecords[index] = cleaned
            } else {
                ledger.settings.fixedLiabilityRecords.append(cleaned)
            }
            if !cleaned.category.isEmpty,
               !ledger.settings.fixedLiabilityCategories.contains(where: { $0.caseInsensitiveCompare(cleaned.category) == .orderedSame }) {
                ledger.settings.fixedLiabilityCategories.append(cleaned.category)
                ledger.settings.fixedLiabilityCategories.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            }
            if let linked = cleaned.linkedAccountID,
               let index = ledger.accounts.firstIndex(where: { $0.id == linked }) {
                ledger.accounts[index].nature = .fixedLiability
            }
        }
    }

    func deleteFixedLiabilityRecord(_ id: UUID) {
        updateLedger(failureMessage: "The fixed liability could not be removed.") { ledger in
            ledger.settings.fixedLiabilityRecords.removeAll { $0.id == id }
        }
    }
'''
text = text.replace(crud_anchor, crud, 1)

# Fixed liabilities participate in loan cash flow just like long-term borrowing.
text = text.replace(
'''              source.nature == .loan,
              destination.nature == .bank else { return 0 }
''',
'''              (source.nature == .loan || source.nature == .fixedLiability),
              destination.nature == .bank else { return 0 }
''', 1)
text = text.replace(
'''              source.nature == .bank,
              destination.nature == .loan else { return 0 }
''',
'''              source.nature == .bank,
              (destination.nature == .loan || destination.nature == .fixedLiability) else { return 0 }
''', 1)
write(store_path, text)


# ---------------------------------------------------------------------------
# Chart of Accounts: icons / badges for the two new natures.
# ---------------------------------------------------------------------------
chart_path = "DailyLedger/Views/ChartOfAccountsView.swift"
text = read(chart_path)
text = text.replace(
'''        case .asset: return "house.fill"
        case .loan: return "creditcard.trianglebadge.exclamationmark"
''',
'''        case .asset: return "house.fill"
        case .fixedAsset: return "building.2.crop.circle.fill"
        case .fixedLiability: return "calendar.badge.minus"
        case .loan: return "creditcard.trianglebadge.exclamationmark"
''', 1)
text = text.replace(
'''        case .asset: return "ASSET"
        case .loan: return "LOAN"
''',
'''        case .asset: return "ASSET"
        case .fixedAsset: return "FIXED"
        case .fixedLiability: return "LT DEBT"
        case .loan: return "LOAN"
''', 1)
write(chart_path, text)


# ---------------------------------------------------------------------------
# Account nature report: preserve explicit fixed classifications before legacy
# group-based coercion.
# ---------------------------------------------------------------------------
reports_path = "DailyLedger/Views/ReportsView.swift"
text = read(reports_path)
text = text.replace(
'''    private func effectiveNature(_ account: LedgerAccount) -> AccountNature {
        if account.group == .payments { return .loan }
        if account.group == .assets { return .asset }
        return account.nature ?? .unassigned
    }
''',
'''    private func effectiveNature(_ account: LedgerAccount) -> AccountNature {
        if account.nature == .fixedAsset { return .fixedAsset }
        if account.nature == .fixedLiability { return .fixedLiability }
        if account.group == .payments { return .loan }
        if account.group == .assets { return .asset }
        return account.nature ?? .unassigned
    }
''', 1)

# Add dedicated Accounting Registers section at the top of Reports.
reports_section_anchor = '''            List {
                Section("Planning & Comparison") {
'''
register_links = '''            List {
                Section("Accounting Registers") {
                    NavigationLink { FixedAssetRegisterView() } label: {
                        Label("Fixed Asset Register", systemImage: "building.2.crop.circle.fill")
                    }
                    NavigationLink { FixedLiabilityRegisterView() } label: {
                        Label("Fixed Liabilities Register", systemImage: "calendar.badge.minus")
                    }
                }
                Section("Planning & Comparison") {
'''
if text.count(reports_section_anchor) != 1:
    raise RuntimeError("Reports accounting register insertion anchor missing")
text = text.replace(reports_section_anchor, register_links, 1)
write(reports_path, text)


# ---------------------------------------------------------------------------
# Dedicated Fixed Asset / Fixed Liability register windows.
# ---------------------------------------------------------------------------
register_view = r'''import SwiftUI

private enum FixedAssetRegisterFilter: String, CaseIterable, Identifiable {
    case active = "Active"
    case sold = "Sold"
    case disposed = "Disposed"
    case all = "All"
    var id: String { rawValue }
}

private struct FixedAssetCurrencySummary: Identifiable {
    let currency: String
    let cost: Decimal
    let accumulated: Decimal
    let nbv: Decimal
    let gainLoss: Decimal
    var id: String { currency }
}

struct FixedAssetRegisterView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var filter: FixedAssetRegisterFilter = .active
    @State private var showingNew = false
    @State private var editingAsset: FixedAssetRecord?
    @State private var disposingAsset: FixedAssetRecord?
    @State private var searchText = ""

    var body: some View {
        List {
            Section {
                Picker("Register", selection: $filter) {
                    ForEach(FixedAssetRegisterFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            if summaries.isEmpty {
                Section("Register Summary") {
                    LabeledContent("Original Cost", value: DisplayFormat.currency(0, code: store.currencyCode))
                    LabeledContent("Net Book Value", value: DisplayFormat.currency(0, code: store.currencyCode))
                }
            } else {
                ForEach(summaries) { summary in
                    Section("\(summary.currency) Register Summary") {
                        LabeledContent("Original Cost", value: DisplayFormat.currency(summary.cost, code: summary.currency))
                        LabeledContent("Accumulated Depreciation", value: DisplayFormat.currency(summary.accumulated, code: summary.currency))
                        LabeledContent("Net Book Value", value: DisplayFormat.currency(summary.nbv, code: summary.currency))
                        LabeledContent("Disposal Gain / (Loss)", value: DisplayFormat.currency(summary.gainLoss, code: summary.currency))
                            .foregroundStyle(summary.gainLoss >= 0 ? AppTheme.green : AppTheme.red)
                    }
                }
            }

            if filteredAssets.isEmpty {
                Section {
                    EmptyLedgerView(
                        title: "No fixed assets",
                        message: filter == .active
                            ? "Register fixed assets here. Sold and disposed items remain permanently visible in their own tabs."
                            : "No assets match this register view."
                    )
                }
            } else {
                ForEach(groupedCategories, id: \.0) { category, assets in
                    Section(category) {
                        ForEach(assets) { asset in
                            Button { editingAsset = asset } label: {
                                FixedAssetRegisterRow(asset: asset)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button { editingAsset = asset } label: { Label("Edit Asset", systemImage: "pencil") }
                                if asset.status == .active {
                                    Button { disposingAsset = asset } label: { Label("Sell / Dispose", systemImage: "arrow.uturn.down.square") }
                                }
                                Button(role: .destructive) {
                                    store.deleteFixedAssetRecord(asset.id)
                                } label: { Label("Delete Register Record", systemImage: "trash") }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if asset.status == .active {
                                    Button { disposingAsset = asset } label: { Label("Dispose", systemImage: "arrow.uturn.down.square") }
                                        .tint(AppTheme.orange)
                                }
                                Button { editingAsset = asset } label: { Label("Edit", systemImage: "pencil") }
                                    .tint(AppTheme.blue)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Fixed Asset Register")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Asset no., name, category")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: { Image(systemName: "plus.circle.fill") }
                    .accessibilityLabel("Register fixed asset")
            }
        }
        .sheet(isPresented: $showingNew) {
            FixedAssetEditorView(asset: nil).environmentObject(store)
        }
        .sheet(item: $editingAsset) { asset in
            FixedAssetEditorView(asset: asset).environmentObject(store)
        }
        .sheet(item: $disposingAsset) { asset in
            FixedAssetDisposalView(asset: asset).environmentObject(store)
        }
    }

    private var filteredAssets: [FixedAssetRecord] {
        store.fixedAssetRecords.filter { asset in
            let statusMatches: Bool
            switch filter {
            case .active: statusMatches = asset.status == .active
            case .sold: statusMatches = asset.status == .sold
            case .disposed: statusMatches = asset.status == .disposed
            case .all: statusMatches = true
            }
            guard statusMatches else { return false }
            guard !searchText.isEmpty else { return true }
            return asset.assetNumber.localizedCaseInsensitiveContains(searchText)
                || asset.name.localizedCaseInsensitiveContains(searchText)
                || asset.category.localizedCaseInsensitiveContains(searchText)
        }.sorted { $0.purchaseDate > $1.purchaseDate }
    }

    private var groupedCategories: [(String, [FixedAssetRecord])] {
        Dictionary(grouping: filteredAssets, by: \.category)
            .map { ($0.key, $0.value) }
            .sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    }

    private var summaries: [FixedAssetCurrencySummary] {
        let grouped = Dictionary(grouping: filteredAssets, by: \.currencyCode)
        return grouped.map { currency, assets in
            let now = Date()
            return FixedAssetCurrencySummary(
                currency: currency,
                cost: assets.reduce(0) { $0 + $1.cost },
                accumulated: assets.reduce(0) { $0 + $1.accumulatedDepreciation(asOf: now) },
                nbv: assets.reduce(0) { $0 + $1.netBookValue(asOf: now) },
                gainLoss: assets.reduce(0) { $0 + ($1.disposalGainLoss ?? 0) }
            )
        }.sorted { $0.currency < $1.currency }
    }
}

private struct FixedAssetRegisterRow: View {
    let asset: FixedAssetRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: asset.status == .active ? "building.2.fill" : "archivebox.fill")
                .foregroundStyle(statusColor)
                .frame(width: 38, height: 38)
                .background(statusColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text(asset.name).font(.body.weight(.semibold))
                Text([asset.assetNumber, asset.category].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(asset.status.title)
                    .font(.caption2.bold()).foregroundStyle(statusColor)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("NBV " + DisplayFormat.currency(asset.netBookValue(asOf: Date()), code: asset.currencyCode))
                    .font(.caption.bold())
                Text("Cost " + DisplayFormat.currency(asset.cost, code: asset.currencyCode))
                    .font(.caption2).foregroundStyle(.secondary)
                if let gainLoss = asset.disposalGainLoss {
                    Text((gainLoss >= 0 ? "Gain " : "Loss ") + DisplayFormat.currency(abs(gainLoss), code: asset.currencyCode))
                        .font(.caption2.bold())
                        .foregroundStyle(gainLoss >= 0 ? AppTheme.green : AppTheme.red)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch asset.status {
        case .active: return AppTheme.green
        case .sold: return AppTheme.blue
        case .disposed: return AppTheme.orange
        }
    }
}

private struct FixedAssetEditorView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: FixedAssetRecord
    @State private var costText: String
    @State private var residualText: String
    @State private var rateText: String
    @State private var lifeText: String
    @State private var openingDepText: String
    private let isNew: Bool
    private let currencies = ["QAR", "PKR", "USD", "GBP", "EUR", "AED", "SAR", "INR"]

    init(asset: FixedAssetRecord?) {
        let value = asset ?? FixedAssetRecord()
        _draft = State(initialValue: value)
        _costText = State(initialValue: NSDecimalNumber(decimal: value.cost).stringValue)
        _residualText = State(initialValue: NSDecimalNumber(decimal: value.residualValue).stringValue)
        _rateText = State(initialValue: NSDecimalNumber(decimal: value.annualDepreciationRate).stringValue)
        _lifeText = State(initialValue: String(value.usefulLifeMonths))
        _openingDepText = State(initialValue: NSDecimalNumber(decimal: value.openingAccumulatedDepreciation).stringValue)
        isNew = asset == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Asset Identity") {
                    TextField("Asset number / tag", text: $draft.assetNumber)
                    TextField("Asset name", text: $draft.name)
                    Menu {
                        ForEach(store.fixedAssetCategories, id: \.self) { category in
                            Button(category) { draft.category = category }
                        }
                    } label: {
                        LabeledContent("Choose Category", value: draft.category)
                    }
                    TextField("Category", text: $draft.category)
                    Picker("Currency", selection: $draft.currencyCode) {
                        ForEach(currencies, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Linked Fixed Asset Account", selection: $draft.linkedAccountID) {
                        Text("Not Linked").tag(Optional<UUID>.none)
                        ForEach(linkableAccounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                }

                Section("Acquisition") {
                    DatePicker("Purchase Date", selection: $draft.purchaseDate, displayedComponents: .date)
                    TextField("Original Cost", text: $costText).keyboardType(.numbersAndPunctuation)
                    TextField("Residual Value", text: $residualText).keyboardType(.numbersAndPunctuation)
                }

                Section("Depreciation") {
                    Picker("Method", selection: $draft.depreciationMethod) {
                        ForEach(FixedAssetDepreciationMethod.allCases) { Text($0.title).tag($0) }
                    }
                    DatePicker("Depreciation Start", selection: $draft.depreciationStartDate, displayedComponents: .date)
                    if draft.depreciationMethod == .straightLineRate {
                        TextField("Annual Rate %", text: $rateText).keyboardType(.decimalPad)
                    } else if draft.depreciationMethod == .straightLineLife {
                        TextField("Useful Life (Months)", text: $lifeText).keyboardType(.numberPad)
                    }
                    TextField("Opening Accumulated Depreciation", text: $openingDepText)
                        .keyboardType(.numbersAndPunctuation)
                    Text("Full-month straight-line convention is used from the depreciation start month.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Current Register Preview") {
                    LabeledContent("Accumulated Depreciation", value: DisplayFormat.currency(preview.accumulatedDepreciation(asOf: Date()), code: preview.currencyCode))
                    LabeledContent("Net Book Value", value: DisplayFormat.currency(preview.netBookValue(asOf: Date()), code: preview.currencyCode))
                    LabeledContent("Status", value: preview.status.title)
                }

                Section("Notes") {
                    TextEditor(text: $draft.notes).frame(minHeight: 90)
                }
            }
            .navigationTitle(isNew ? "Register Fixed Asset" : "Edit Fixed Asset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
        }
    }

    private var linkableAccounts: [LedgerAccount] {
        store.activeAccounts.filter {
            $0.nature == .asset || $0.nature == .fixedAsset || $0.group == .assets
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func decimal(_ text: String) -> Decimal? {
        Decimal(string: text.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX"))
    }

    private var preview: FixedAssetRecord {
        var value = draft
        value.cost = decimal(costText) ?? 0
        value.residualValue = decimal(residualText) ?? 0
        value.annualDepreciationRate = decimal(rateText) ?? 0
        value.usefulLifeMonths = Int(lifeText) ?? 0
        value.openingAccumulatedDepreciation = decimal(openingDepText) ?? 0
        return value
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (decimal(costText) ?? 0) > 0
            && (decimal(residualText) ?? 0) >= 0
            && (decimal(openingDepText) ?? 0) >= 0
            && (draft.depreciationMethod != .straightLineLife || (Int(lifeText) ?? 0) > 0)
    }

    private func save() {
        var value = preview
        if value.assetNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            value.assetNumber = String(format: "FA-%04d", store.fixedAssetRecords.count + 1)
        }
        store.saveFixedAssetRecord(value)
        dismiss()
    }
}

private struct FixedAssetDisposalView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    let asset: FixedAssetRecord
    @State private var status: FixedAssetStatus
    @State private var disposalDate: Date
    @State private var proceedsText: String
    @State private var reason: String

    init(asset: FixedAssetRecord) {
        self.asset = asset
        _status = State(initialValue: asset.status == .active ? .sold : asset.status)
        _disposalDate = State(initialValue: asset.disposalDate ?? Date())
        _proceedsText = State(initialValue: NSDecimalNumber(decimal: asset.disposalProceeds ?? 0).stringValue)
        _reason = State(initialValue: asset.disposalReason)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Asset") {
                    LabeledContent("Asset", value: asset.name)
                    LabeledContent("Asset No.", value: asset.assetNumber)
                    LabeledContent("Original Cost", value: DisplayFormat.currency(asset.cost, code: asset.currencyCode))
                }
                Section("Sale / Disposal") {
                    Picker("Type", selection: $status) {
                        Text("Sold").tag(FixedAssetStatus.sold)
                        Text("Disposed").tag(FixedAssetStatus.disposed)
                    }
                    DatePicker("Date", selection: $disposalDate, displayedComponents: .date)
                    TextField("Sale / Disposal Proceeds", text: $proceedsText).keyboardType(.numbersAndPunctuation)
                    TextField("Reason / Reference", text: $reason)
                }
                Section("Accounting Result") {
                    LabeledContent("Accumulated Depreciation", value: DisplayFormat.currency(asset.accumulatedDepreciation(asOf: disposalDate), code: asset.currencyCode))
                    LabeledContent("NBV at Disposal", value: DisplayFormat.currency(asset.netBookValue(asOf: disposalDate), code: asset.currencyCode))
                    LabeledContent("Proceeds", value: DisplayFormat.currency(proceeds, code: asset.currencyCode))
                    LabeledContent("Gain / (Loss)", value: DisplayFormat.currency(gainLoss, code: asset.currencyCode))
                        .foregroundStyle(gainLoss >= 0 ? AppTheme.green : AppTheme.red)
                }
            }
            .navigationTitle("Sell / Dispose Asset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Post to Register", action: save) }
            }
        }
    }

    private var proceeds: Decimal {
        Decimal(string: proceedsText.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }
    private var gainLoss: Decimal { proceeds - asset.netBookValue(asOf: disposalDate) }

    private func save() {
        var value = asset
        value.status = status
        value.disposalDate = disposalDate
        value.disposalProceeds = proceeds
        value.disposalReason = reason
        store.saveFixedAssetRecord(value)
        dismiss()
    }
}

private enum FixedLiabilityFilter: String, CaseIterable, Identifiable {
    case active = "Active"
    case settled = "Settled"
    case all = "All"
    var id: String { rawValue }
}

struct FixedLiabilityRegisterView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var filter: FixedLiabilityFilter = .active
    @State private var showingNew = false
    @State private var editing: FixedLiabilityRecord?
    @State private var searchText = ""

    var body: some View {
        List {
            Section {
                Picker("Register", selection: $filter) {
                    ForEach(FixedLiabilityFilter.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
            }
            ForEach(currencySummaries, id: \.0) { currency, values in
                Section("\(currency) Summary") {
                    LabeledContent("Original Principal", value: DisplayFormat.currency(values.0, code: currency))
                    LabeledContent("Current Ledger Balance", value: DisplayFormat.currency(values.1, code: currency))
                    LabeledContent("Current Portion", value: DisplayFormat.currency(values.2, code: currency))
                    LabeledContent("Long-Term Portion", value: DisplayFormat.currency(max(0, values.1 - values.2), code: currency))
                }
            }
            if filtered.isEmpty {
                Section { EmptyLedgerView(title: "No fixed liabilities", message: "Register long-term loans, lease liabilities and other fixed liabilities here.") }
            } else {
                ForEach(Dictionary(grouping: filtered, by: \.category).keys.sorted(), id: \.self) { category in
                    Section(category) {
                        ForEach(Dictionary(grouping: filtered, by: \.category)[category] ?? []) { item in
                            Button { editing = item } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.name).font(.body.weight(.semibold))
                                        Text([item.reference, item.lender].filter { !$0.isEmpty }.joined(separator: " · "))
                                            .font(.caption).foregroundStyle(.secondary)
                                        Text(item.status.title).font(.caption2.bold())
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 3) {
                                        Text(DisplayFormat.currency(currentBalance(item), code: item.currencyCode)).font(.caption.bold())
                                        if let maturity = item.maturityDate {
                                            Text("Due " + maturity.formatted(date: .abbreviated, time: .omitted))
                                                .font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }.buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button { editing = item } label: { Label("Edit", systemImage: "pencil") }.tint(AppTheme.blue)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Fixed Liabilities")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Liability, lender, category")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: { Image(systemName: "plus.circle.fill") }
            }
        }
        .sheet(isPresented: $showingNew) { FixedLiabilityEditorView(record: nil).environmentObject(store) }
        .sheet(item: $editing) { FixedLiabilityEditorView(record: $0).environmentObject(store) }
    }

    private var filtered: [FixedLiabilityRecord] {
        store.fixedLiabilityRecords.filter { item in
            let statusMatches: Bool
            switch filter {
            case .active: statusMatches = item.status == .active
            case .settled: statusMatches = item.status == .settled
            case .all: statusMatches = true
            }
            guard statusMatches else { return false }
            guard !searchText.isEmpty else { return true }
            return item.name.localizedCaseInsensitiveContains(searchText)
                || item.lender.localizedCaseInsensitiveContains(searchText)
                || item.category.localizedCaseInsensitiveContains(searchText)
                || item.reference.localizedCaseInsensitiveContains(searchText)
        }.sorted { $0.startDate > $1.startDate }
    }

    private func currentBalance(_ item: FixedLiabilityRecord) -> Decimal {
        guard let account = store.account(withID: item.linkedAccountID) else { return item.status == .settled ? 0 : item.originalPrincipal }
        return abs(store.balance(for: account))
    }

    private var currencySummaries: [(String, (Decimal, Decimal, Decimal))] {
        let grouped = Dictionary(grouping: filtered, by: \.currencyCode)
        return grouped.map { currency, values in
            (
                currency,
                (
                    values.reduce(0) { $0 + $1.originalPrincipal },
                    values.reduce(0) { $0 + currentBalance($1) },
                    values.reduce(0) { $0 + $1.currentPortion }
                )
            )
        }.sorted { $0.0 < $1.0 }
    }
}

private struct FixedLiabilityEditorView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: FixedLiabilityRecord
    @State private var principalText: String
    @State private var rateText: String
    @State private var currentPortionText: String
    @State private var hasMaturity: Bool
    private let isNew: Bool
    private let currencies = ["QAR", "PKR", "USD", "GBP", "EUR", "AED", "SAR", "INR"]

    init(record: FixedLiabilityRecord?) {
        let value = record ?? FixedLiabilityRecord()
        _draft = State(initialValue: value)
        _principalText = State(initialValue: NSDecimalNumber(decimal: value.originalPrincipal).stringValue)
        _rateText = State(initialValue: NSDecimalNumber(decimal: value.annualInterestRate).stringValue)
        _currentPortionText = State(initialValue: NSDecimalNumber(decimal: value.currentPortion).stringValue)
        _hasMaturity = State(initialValue: value.maturityDate != nil)
        isNew = record == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Liability") {
                    TextField("Reference", text: $draft.reference)
                    TextField("Name", text: $draft.name)
                    TextField("Lender / Counterparty", text: $draft.lender)
                    Menu {
                        ForEach(store.fixedLiabilityCategories, id: \.self) { category in
                            Button(category) { draft.category = category }
                        }
                    } label: { LabeledContent("Choose Category", value: draft.category) }
                    TextField("Category", text: $draft.category)
                    Picker("Currency", selection: $draft.currencyCode) {
                        ForEach(currencies, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Linked Liability Account", selection: $draft.linkedAccountID) {
                        Text("Not Linked").tag(Optional<UUID>.none)
                        ForEach(linkableAccounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                }
                Section("Terms") {
                    DatePicker("Start Date", selection: $draft.startDate, displayedComponents: .date)
                    Toggle("Has Maturity Date", isOn: $hasMaturity)
                    if hasMaturity {
                        DatePicker("Maturity", selection: Binding(
                            get: { draft.maturityDate ?? Date() },
                            set: { draft.maturityDate = $0 }
                        ), displayedComponents: .date)
                    }
                    TextField("Original Principal", text: $principalText).keyboardType(.numbersAndPunctuation)
                    TextField("Annual Interest %", text: $rateText).keyboardType(.decimalPad)
                    TextField("Current Portion (Next 12 Months)", text: $currentPortionText).keyboardType(.numbersAndPunctuation)
                }
                Section("Status") {
                    Picker("Status", selection: $draft.status) {
                        ForEach(FixedLiabilityStatus.allCases) { Text($0.title).tag($0) }
                    }
                    if draft.status == .settled {
                        DatePicker("Settled Date", selection: Binding(
                            get: { draft.settledDate ?? Date() },
                            set: { draft.settledDate = $0 }
                        ), displayedComponents: .date)
                    }
                }
                Section("Notes") { TextEditor(text: $draft.notes).frame(minHeight: 90) }
                if !isNew {
                    Section {
                        Button("Delete Register Record", role: .destructive) {
                            store.deleteFixedLiabilityRecord(draft.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Register Fixed Liability" : "Edit Fixed Liability")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(!canSave) }
            }
        }
    }

    private var linkableAccounts: [LedgerAccount] {
        store.activeAccounts.filter {
            $0.nature == .loan || $0.nature == .fixedLiability || $0.group == .payments
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    private func decimal(_ text: String) -> Decimal? {
        Decimal(string: text.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX"))
    }
    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (decimal(principalText) ?? 0) > 0
    }
    private func save() {
        draft.originalPrincipal = decimal(principalText) ?? 0
        draft.annualInterestRate = decimal(rateText) ?? 0
        draft.currentPortion = decimal(currentPortionText) ?? 0
        if !hasMaturity { draft.maturityDate = nil }
        if draft.status == .active { draft.settledDate = nil }
        if draft.reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.reference = String(format: "FL-%04d", store.fixedLiabilityRecords.count + 1)
        }
        store.saveFixedLiabilityRecord(draft)
        dismiss()
    }
}
'''
write("DailyLedger/Views/FixedAccountingRegistersView.swift", register_view)


# Settings version label.
settings_path = "DailyLedger/Views/SettingsView.swift"
settings = read(settings_path)
settings, count = re.subn(
    r'LabeledContent\("Version", value: "[^"]+"\)',
    'LabeledContent("Version", value: "1.3.66")',
    settings,
    count=1,
)
if count != 1:
    raise RuntimeError("Settings version label not found")
write(settings_path, settings)

print("Prepared Next Ledger 1.3.66 build 74: dedicated Fixed Asset Register with sold/disposed/gain-loss accounting and separate Fixed Liabilities Register.")
