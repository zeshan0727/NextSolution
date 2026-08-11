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
# Next Ledger 1.3.67 / build 75. App-only update; SMS daemon remains 2.2.3.
# ---------------------------------------------------------------------------
replace_once("project.yml", 'MARKETING_VERSION: "1.3.66"', 'MARKETING_VERSION: "1.3.67"')
replace_once("project.yml", 'CURRENT_PROJECT_VERSION: "74"', 'CURRENT_PROJECT_VERSION: "75"')

view_path = "DailyLedger/Views/FixedAccountingRegistersView.swift"
text = read(view_path)
if "import UIKit" not in text:
    text = text.replace("import SwiftUI\n", "import SwiftUI\nimport UIKit\n", 1)

# ---------------------------------------------------------------------------
# Fixed Asset Register: account nature -> register visibility, as-of date,
# and report snapshot/export.
# ---------------------------------------------------------------------------
far_start = text.find("struct FixedAssetRegisterView: View {")
far_end = text.find("private struct FixedAssetRegisterRow", far_start)
if far_start < 0 or far_end < 0:
    raise RuntimeError("FixedAssetRegisterView markers not found")
far = text[far_start:far_end]

state_old = '''    @State private var disposingAsset: FixedAssetRecord?\n    @State private var searchText = ""\n'''
state_new = '''    @State private var disposingAsset: FixedAssetRecord?\n    @State private var searchText = ""\n    @State private var customAsOfEnabled = false\n    @State private var asOfDate = Date()\n    @State private var showingExport = false\n'''
if far.count(state_old) != 1:
    raise RuntimeError("FAR state anchor not found")
far = far.replace(state_old, state_new, 1)

list_anchor = '''    var body: some View {\n        List {\n'''
list_insert = '''    var body: some View {\n        List {\n            Section {\n                Toggle("Custom As-of Date", isOn: $customAsOfEnabled)\n                if customAsOfEnabled {\n                    DatePicker("As of", selection: $asOfDate, displayedComponents: .date)\n                }\n            } header: {\n                Text("Register Date")\n            } footer: {\n                Text("Depreciation, NBV, Active/Sold/Disposed status and export use this reporting date. Assets purchased after the selected date are excluded.")\n            }\n'''
if far.count(list_anchor) != 1:
    raise RuntimeError("FAR List anchor not found")
far = far.replace(list_anchor, list_insert, 1)

# Row now receives the reporting date and whether this is an auto-discovered
# fixed-asset account which still needs FAR metadata.
far = far.replace(
    "FixedAssetRegisterRow(asset: asset)",
    "FixedAssetRegisterRow(asset: asset, asOfDate: reportingDate, needsDetails: needsDetails(asset))"
)

# Add export toolbar button.
toolbar_anchor = '''        .toolbar {\n            ToolbarItem(placement: .primaryAction) {\n'''
toolbar_insert = '''        .toolbar {\n            ToolbarItem(placement: .navigationBarLeading) {\n                Button { showingExport = true } label: {\n                    Image(systemName: "square.and.arrow.down.fill")\n                }\n                .accessibilityLabel("Download fixed asset register")\n            }\n            ToolbarItem(placement: .primaryAction) {\n'''
if far.count(toolbar_anchor) != 1:
    raise RuntimeError("FAR toolbar anchor not found")
far = far.replace(toolbar_anchor, toolbar_insert, 1)

# Add snapshot/export sheet immediately before the new-asset sheet.
sheet_anchor = '''        .sheet(isPresented: $showingNew) {\n'''
sheet_insert = '''        .sheet(isPresented: $showingExport) {\n            FixedAssetRegisterExportView(\n                assets: filteredAssets,\n                asOfDate: reportingDate,\n                registerTitle: filter.rawValue\n            )\n        }\n        .sheet(isPresented: $showingNew) {\n'''
if far.count(sheet_anchor) != 1:
    raise RuntimeError("FAR new sheet anchor not found")
far = far.replace(sheet_anchor, sheet_insert, 1)

# Replace filteredAssets with a source that includes accounts whose nature was
# changed to Fixed Asset even if a formal FAR record does not exist yet.
filtered_pattern = re.compile(
    r'''    private var filteredAssets: \[FixedAssetRecord\] \{.*?\n    \}\n\n    private var groupedCategories:''',
    re.S,
)
filtered_replacement = r'''    private var reportingDate: Date {
        guard customAsOfEnabled else { return Date() }
        let start = Calendar.current.startOfDay(for: asOfDate)
        return Calendar.current.date(byAdding: .day, value: 1, to: start)?.addingTimeInterval(-1) ?? asOfDate
    }

    private var allRegisterAssets: [FixedAssetRecord] {
        var records = store.fixedAssetRecords
        let linkedAccountIDs = Set(records.compactMap(\.linkedAccountID))
        let fixedAccounts = store.accounts.filter {
            !$0.isArchived && $0.nature == .fixedAsset && !linkedAccountIDs.contains($0.id)
        }
        for account in fixedAccounts {
            records.append(FixedAssetRecord(
                id: account.id,
                assetNumber: account.chartCode ?? "",
                name: account.name,
                category: "Needs Details",
                currencyCode: account.currencyCode,
                linkedAccountID: account.id,
                purchaseDate: account.createdAt,
                cost: 0,
                residualValue: 0,
                depreciationStartDate: account.createdAt,
                depreciationMethod: .none,
                annualDepreciationRate: 0,
                usefulLifeMonths: 0,
                openingAccumulatedDepreciation: 0,
                status: .active,
                notes: "Created automatically from Chart of Accounts. Complete the FAR details."
            ))
        }
        return records
    }

    private func needsDetails(_ asset: FixedAssetRecord) -> Bool {
        !store.fixedAssetRecords.contains(where: { $0.id == asset.id })
    }

    private func effectiveStatus(_ asset: FixedAssetRecord) -> FixedAssetStatus {
        if let disposalDate = asset.disposalDate,
           disposalDate <= reportingDate,
           asset.status != .active {
            return asset.status
        }
        return .active
    }

    private var filteredAssets: [FixedAssetRecord] {
        allRegisterAssets.filter { asset in
            guard asset.purchaseDate <= reportingDate else { return false }
            let status = effectiveStatus(asset)
            let statusMatches: Bool
            switch filter {
            case .active: statusMatches = status == .active
            case .sold: statusMatches = status == .sold
            case .disposed: statusMatches = status == .disposed
            case .all: statusMatches = true
            }
            guard statusMatches else { return false }
            guard !searchText.isEmpty else { return true }
            return asset.assetNumber.localizedCaseInsensitiveContains(searchText)
                || asset.name.localizedCaseInsensitiveContains(searchText)
                || asset.category.localizedCaseInsensitiveContains(searchText)
        }.sorted { $0.purchaseDate > $1.purchaseDate }
    }

    private var groupedCategories:'''
far, count = filtered_pattern.subn(filtered_replacement, far, count=1)
if count != 1:
    raise RuntimeError("FAR filteredAssets block not replaced")

# Summary cards use the selected reporting date instead of Date().
far = far.replace("            let now = Date()\n", "            let now = reportingDate\n", 1)

text = text[:far_start] + far + text[far_end:]

# Update row to show the as-of NBV and Needs Details badge.
row_start = text.find("private struct FixedAssetRegisterRow")
row_end = text.find("private struct FixedAssetEditorView", row_start)
if row_start < 0 or row_end < 0:
    raise RuntimeError("FixedAssetRegisterRow markers not found")
row = text[row_start:row_end]
row = row.replace(
    '''private struct FixedAssetRegisterRow: View {\n    let asset: FixedAssetRecord\n''',
    '''private struct FixedAssetRegisterRow: View {\n    let asset: FixedAssetRecord\n    let asOfDate: Date\n    let needsDetails: Bool\n''',
    1,
)
row = row.replace(
    'Text("NBV " + DisplayFormat.currency(asset.netBookValue(asOf: Date()), code: asset.currencyCode))',
    'Text("NBV " + DisplayFormat.currency(asset.netBookValue(asOf: asOfDate), code: asset.currencyCode))',
    1,
)
# Put a clear Needs Details badge beside the status where available.
status_anchor = '''                Text(asset.status.title)\n                    .font(.caption2.bold()).foregroundStyle(statusColor)\n'''
status_insert = '''                Text(asset.status.title)\n                    .font(.caption2.bold()).foregroundStyle(statusColor)\n                if needsDetails {\n                    Text("NEEDS DETAILS")\n                        .font(.system(size: 9, weight: .bold, design: .rounded))\n                        .foregroundStyle(AppTheme.orange)\n                        .padding(.horizontal, 6)\n                        .padding(.vertical, 3)\n                        .background(AppTheme.orange.opacity(0.12), in: Capsule())\n                }\n'''
if row.count(status_anchor) == 1:
    row = row.replace(status_anchor, status_insert, 1)
text = text[:row_start] + row + text[row_end:]

# ---------------------------------------------------------------------------
# Fixed liability register gets the same account-nature reflection behavior:
# changing an account to Fixed Liability makes it appear as Needs Details.
# ---------------------------------------------------------------------------
liab_start = text.find("struct FixedLiabilityRegisterView: View {")
if liab_start >= 0:
    # Replace only the first store.fixedLiabilityRecords.filter occurrence after this struct.
    pos = text.find("store.fixedLiabilityRecords.filter", liab_start)
    if pos >= 0:
        text = text[:pos] + "allRegisterLiabilities.filter" + text[pos + len("store.fixedLiabilityRecords.filter"):]
        helper_anchor = text.find("    private var filtered", liab_start)
        if helper_anchor >= 0:
            helper = r'''    private var allRegisterLiabilities: [FixedLiabilityRecord] {
        var records = store.fixedLiabilityRecords
        let linked = Set(records.compactMap(\.linkedAccountID))
        for account in store.accounts where !account.isArchived && account.nature == .fixedLiability && !linked.contains(account.id) {
            records.append(FixedLiabilityRecord(
                id: account.id,
                reference: account.chartCode ?? "",
                name: account.name,
                category: "Needs Details",
                lender: "",
                currencyCode: account.currencyCode,
                linkedAccountID: account.id,
                startDate: account.createdAt,
                originalPrincipal: abs(store.balance(for: account)),
                notes: "Created automatically from Chart of Accounts. Complete the liability register details."
            ))
        }
        return records
    }

'''
            text = text[:helper_anchor] + helper + text[helper_anchor:]

# ---------------------------------------------------------------------------
# Snapshot/export window. It is intentionally self-contained so every FAR
# export displays the register inside the app before Share/Save.
# ---------------------------------------------------------------------------
export_code = r'''

private struct FixedAssetRegisterExportView: View {
    @Environment(\.dismiss) private var dismiss
    let assets: [FixedAssetRecord]
    let asOfDate: Date
    let registerTitle: String
    @State private var generatedURL: URL?
    @State private var generatedLabel = ""
    @State private var exportError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FIXED ASSET REGISTER SNAPSHOT")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        Text(registerTitle)
                            .font(.title2.bold())
                        Text("As of \(asOfDate.formatted(date: .long, time: .omitted))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(currencySummaries, id: \.currency) { summary in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(summary.currency).font(.headline)
                            LabeledContent("Cost", value: DisplayFormat.currency(summary.cost, code: summary.currency))
                            LabeledContent("Accumulated Depreciation", value: DisplayFormat.currency(summary.accumulated, code: summary.currency))
                            LabeledContent("Net Book Value", value: DisplayFormat.currency(summary.nbv, code: summary.currency))
                            LabeledContent("Gain / (Loss)", value: DisplayFormat.currency(summary.gainLoss, code: summary.currency))
                        }
                        .padding(14)
                        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Register Detail · \(assets.count) assets")
                            .font(.headline)
                        ForEach(assets.prefix(30)) { asset in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(asset.assetNumber.isEmpty ? "—" : asset.assetNumber)
                                        .font(.caption.bold())
                                    Text(asset.name).font(.subheadline.bold())
                                    Spacer()
                                    Text(asset.status.title).font(.caption)
                                }
                                HStack {
                                    Text(asset.category).font(.caption).foregroundStyle(.secondary)
                                    Spacer()
                                    Text("Cost " + DisplayFormat.currency(asset.cost, code: asset.currencyCode))
                                        .font(.caption)
                                    Text("NBV " + DisplayFormat.currency(asset.netBookValue(asOf: asOfDate), code: asset.currencyCode))
                                        .font(.caption.bold())
                                }
                            }
                            .padding(.vertical, 5)
                            Divider()
                        }
                        if assets.count > 30 {
                            Text("Snapshot shows first 30 rows. The downloaded file contains all \(assets.count) rows.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    if let exportError {
                        Label(exportError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(AppTheme.red)
                    }
                    if let generatedURL {
                        ShareLink(item: generatedURL) {
                            Label("Share / Save \(generatedLabel)", systemImage: "square.and.arrow.up.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(16)
            }
            .background(AppTheme.page)
            .navigationTitle("Report Snapshot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            generatePDF()
                        } label: {
                            Label("PDF", systemImage: "doc.richtext.fill")
                        }
                        Button {
                            generateCSV()
                        } label: {
                            Label("Excel / CSV", systemImage: "tablecells.fill")
                        }
                    } label: {
                        Label("Download", systemImage: "square.and.arrow.down.fill")
                    }
                }
            }
        }
    }

    private var currencySummaries: [(currency: String, cost: Decimal, accumulated: Decimal, nbv: Decimal, gainLoss: Decimal)] {
        Dictionary(grouping: assets, by: \.currencyCode).map { currency, values in
            (
                currency,
                values.reduce(0) { $0 + $1.cost },
                values.reduce(0) { $0 + $1.accumulatedDepreciation(asOf: asOfDate) },
                values.reduce(0) { $0 + $1.netBookValue(asOf: asOfDate) },
                values.reduce(0) { $0 + ($1.disposalGainLoss ?? 0) }
            )
        }.sorted { $0.currency < $1.currency }
    }

    private func generatePDF() {
        do {
            generatedURL = try FixedAssetRegisterFileExporter.pdf(assets: assets, asOfDate: asOfDate, title: registerTitle)
            generatedLabel = "PDF"
            exportError = nil
        } catch {
            exportError = "PDF could not be generated: \(error.localizedDescription)"
        }
    }

    private func generateCSV() {
        do {
            generatedURL = try FixedAssetRegisterFileExporter.csv(assets: assets, asOfDate: asOfDate, title: registerTitle)
            generatedLabel = "Excel / CSV"
            exportError = nil
        } catch {
            exportError = "Excel file could not be generated: \(error.localizedDescription)"
        }
    }
}

private enum FixedAssetRegisterFileExporter {
    static func pdf(assets: [FixedAssetRecord], asOfDate: Date, title: String) throws -> URL {
        let url = temporaryURL(ext: "pdf", prefix: "Fixed-Asset-Register")
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        try renderer.writePDF(to: url) { context in
            let margin: CGFloat = 34
            var y: CGFloat = margin
            let normal: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9),
                .foregroundColor: UIColor.label
            ]
            let bold: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 9),
                .foregroundColor: UIColor.label
            ]
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 17),
                .foregroundColor: UIColor.label
            ]

            func newPage() {
                context.beginPage()
                y = margin
                NSString(string: "Fixed Asset Register — \(title)").draw(at: CGPoint(x: margin, y: y), withAttributes: titleAttrs)
                y += 24
                NSString(string: "As of \(asOfDate.formatted(date: .long, time: .omitted))").draw(at: CGPoint(x: margin, y: y), withAttributes: normal)
                y += 22
                NSString(string: "Asset No.   Asset / Category                         Cost           Accum.Dep.      NBV            Status").draw(at: CGPoint(x: margin, y: y), withAttributes: bold)
                y += 16
            }

            newPage()
            for asset in assets {
                if y > page.height - 48 { newPage() }
                let no = short(asset.assetNumber.isEmpty ? "—" : asset.assetNumber, 10)
                let name = short("\(asset.name) / \(asset.category)", 35)
                let cost = number(asset.cost)
                let dep = number(asset.accumulatedDepreciation(asOf: asOfDate))
                let nbv = number(asset.netBookValue(asOf: asOfDate))
                let line = String(format: "%-10@ %-35@ %12@ %12@ %12@  %@", no as NSString, name as NSString, cost as NSString, dep as NSString, nbv as NSString, asset.status.title as NSString)
                NSString(string: line).draw(at: CGPoint(x: margin, y: y), withAttributes: normal)
                y += 14
            }
        }
        return url
    }

    static func csv(assets: [FixedAssetRecord], asOfDate: Date, title: String) throws -> URL {
        let url = temporaryURL(ext: "csv", prefix: "Fixed-Asset-Register")
        let header = [
            "Register", "As Of", "Asset Number", "Asset Name", "Category", "Currency",
            "Purchase Date", "Cost", "Residual Value", "Depreciation Method", "Annual Rate %",
            "Useful Life Months", "Accumulated Depreciation", "Net Book Value", "Status",
            "Disposal Date", "Proceeds", "Gain/(Loss)", "Notes"
        ]
        var rows = [header.map(csvEscape).joined(separator: ",")]
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        for asset in assets {
            let row = [
                title,
                df.string(from: asOfDate),
                asset.assetNumber,
                asset.name,
                asset.category,
                asset.currencyCode,
                df.string(from: asset.purchaseDate),
                number(asset.cost),
                number(asset.residualValue),
                asset.depreciationMethod.title,
                number(asset.annualDepreciationRate),
                String(asset.usefulLifeMonths),
                number(asset.accumulatedDepreciation(asOf: asOfDate)),
                number(asset.netBookValue(asOf: asOfDate)),
                asset.status.title,
                asset.disposalDate.map(df.string) ?? "",
                asset.disposalProceeds.map(number) ?? "",
                asset.disposalGainLoss.map(number) ?? "",
                asset.notes
            ]
            rows.append(row.map(csvEscape).joined(separator: ","))
        }
        let contents = "\u{FEFF}" + rows.joined(separator: "\r\n")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func temporaryURL(ext: String, prefix: String) -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        let name = "\(prefix)-\(df.string(from: Date())).\(ext)"
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    private static func number(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? NSDecimalNumber(decimal: value).stringValue
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    private static func short(_ value: String, _ length: Int) -> String {
        if value.count <= length { return value }
        return String(value.prefix(max(1, length - 1))) + "…"
    }
}
'''
if "private struct FixedAssetRegisterExportView" not in text:
    text += export_code

write(view_path, text)

# Settings version label.
settings_path = "DailyLedger/Views/SettingsView.swift"
settings = read(settings_path)
settings, count = re.subn(
    r'LabeledContent\("Version", value: "[^"]+"\)',
    'LabeledContent("Version", value: "1.3.67")',
    settings,
    count=1,
)
if count != 1:
    raise RuntimeError("Settings version label not found")
write(settings_path, settings)

print("Prepared Next Ledger 1.3.67 build 75: fixed-asset nature auto-reflects in FAR, custom as-of reporting, and in-app snapshot with PDF/Excel export.")
