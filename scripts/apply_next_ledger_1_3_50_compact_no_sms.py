from __future__ import annotations

from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    (ROOT / path).write_text(content, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one match in {path}, found {count}: {old[:80]!r}")
    write(path, text.replace(old, new, 1))


def replace_range(path: str, start_marker: str, end_marker: str, replacement: str) -> None:
    text = read(path)
    start = text.find(start_marker)
    if start < 0:
        raise RuntimeError(f"Start marker not found in {path}: {start_marker[:80]!r}")
    end_start = text.find(end_marker, start)
    if end_start < 0:
        raise RuntimeError(f"End marker not found in {path}: {end_marker[:80]!r}")
    end = end_start + len(end_marker)
    write(path, text[:start] + replacement + text[end:])


# Make Chart of Accounts rows more compact and hide balances that display as 0.00.
chart_path = "DailyLedger/Views/ChartOfAccountsView.swift"
replace_once(chart_path, "import SwiftUI\n", "import Foundation\nimport SwiftUI\n")
replace_once(
    chart_path,
    "            .filter { !hideZeroBalanceAccounts || store.balance(for: $0) != 0 }\n",
    "            .filter { !hideZeroBalanceAccounts || !isEffectivelyZeroBalance($0) }\n",
)
replace_once(
    chart_path,
    """    private func filteredCategories(_ type: TransactionType) -> [String] {
""",
    """    private func isEffectivelyZeroBalance(_ account: LedgerAccount) -> Bool {
        var balance = store.balance(for: account)
        var rounded = Decimal.zero
        NSDecimalRound(&rounded, &balance, 2, .plain)
        return rounded == 0
    }

    private func filteredCategories(_ type: TransactionType) -> [String] {
""",
)
replace_once(
    chart_path,
    """            VStack(alignment: .leading, spacing: 3) {
                Text(account.name).font(.body.weight(.semibold))
                Text("\\(account.group.title) · \\(account.currencyCode)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(DisplayFormat.currency(store.balance(for: account), code: account.currencyCode))
                .font(.caption.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
""",
    """            Text(account.name)
                .font(.body.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text(DisplayFormat.currency(store.balance(for: account), code: account.currencyCode))
                    .font(.caption.bold().monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(account.group.title.uppercased())
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
""",
)

# Remove the RootHide SMS importer UI while keeping vendor-category rules available.
settings_path = "DailyLedger/Views/SettingsView.swift"
replace_once(settings_path, "    @State private var showingSMSStatus = true\n", "")
settings_start = """                Section {
                    if showingSMSStatus, let result = store.settings.smsImporterLastResult, !result.isEmpty {
"""
settings_end = """                } footer: {
                    Text("Shows the latest importer result and lets you record the latest matching bank message or cancel the prompt.")
                }
"""
settings_replacement = """                Section {
                    NavigationLink {
                        VendorRulesView()
                    } label: {
                        SettingsRow(
                            title: "Vendor Category Rules",
                            subtitle: "Match vendor words to expense categories",
                            icon: "tag.fill",
                            color: AppTheme.purple
                        )
                    }
                } header: {
                    Label("Vendor Rules", systemImage: "tag.fill")
                } footer: {
                    Text("Vendor rules remain available for automatic transaction categorization.")
                }
"""
replace_range(settings_path, settings_start, settings_end, settings_replacement)

sms_view = ROOT / "DailyLedger/Views/SMSImportPreferencesView.swift"
if not sms_view.exists():
    raise RuntimeError("SMSImportPreferencesView.swift was already missing")
sms_view.unlink()

# Remove importer methods and serialized importer settings from the app model.
store_path = "DailyLedger/Services/LedgerStore.swift"
store_text = read(store_path)
method_pattern = re.compile(
    r"\n    func updateSMSAutoImport\(_ enabled: Bool\) \{.*?\n    \}\n\n"
    r"    func updateSMSPreferences\(matchText: String, destinationAccountID: UUID\?\) \{.*?\n    \}\n\n"
    r"    func requestSMSRescan\(\) \{.*?\n    \}\n",
    re.DOTALL,
)
store_text, count = method_pattern.subn("\n", store_text, count=1)
if count != 1:
    raise RuntimeError(f"Expected one SMS method block in {store_path}, found {count}")
write(store_path, store_text)

model_path = "DailyLedger/Models/LedgerTransaction.swift"
model_text = read(model_path)
sms_fields = (
    "smsAutoImportEnabled",
    "smsMatchText",
    "smsDestinationAccountID",
    "smsRescanRequestID",
    "smsImporterLastCheck",
    "smsImporterLastResult",
)
for field in sms_fields:
    if field not in model_text:
        raise RuntimeError(f"Expected {field} in {model_path}")
model_lines = model_text.splitlines()
model_text = "\n".join(
    line for line in model_lines if not any(field in line for field in sms_fields)
) + "\n"
write(model_path, model_text)

replace_once(
    "DailyLedger/Services/LedgerDiskStore.swift",
    "                    ledger.settings.smsDestinationAccountID = nil\n",
    "",
)
replace_once(
    "DailyLedger/Views/InsightsView.swift",
    "without raw SMS text, account numbers, or individual vendor descriptions.",
    "without raw transaction descriptions, account numbers, or individual vendor descriptions.",
)

# Ensure no RootHide importer source is present in the build workspace.
root_hide = ROOT / "RootHideSMSImport"
if root_hide.exists():
    shutil.rmtree(root_hide)

print("Applied compact Chart of Accounts and removed RootHide SMS importer.")
