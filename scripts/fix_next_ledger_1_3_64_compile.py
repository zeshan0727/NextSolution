from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8")


# 1) Professional report aging helper needs LedgerStore explicitly after the
# destination-side balance reconciliation change.
path = "DailyLedger/Services/ProfessionalReportExportService.swift"
text = read(path)
old_call = "let normalized = signedMovement(transaction, accountID: account.id) * polarity"
new_call = "let normalized = signedMovement(transaction, accountID: account.id, store: store) * polarity"
if text.count(old_call) != 1:
    raise RuntimeError(f"signedMovement call count: {text.count(old_call)}")
text = text.replace(old_call, new_call, 1)
old_sig = "private static func signedMovement(_ transaction: LedgerTransaction, accountID: UUID) -> Decimal {"
new_sig = "private static func signedMovement(_ transaction: LedgerTransaction, accountID: UUID, store: LedgerStore) -> Decimal {"
if text.count(old_sig) != 1:
    raise RuntimeError(f"signedMovement signature count: {text.count(old_sig)}")
text = text.replace(old_sig, new_sig, 1)
write(path, text)


# 2) Preserve the scoped ReportDownloadButton API used throughout generated
# ReportsView while keeping the new snapshot-before-share behavior.
path = "DailyLedger/Views/ReportDownloadButton.swift"
text = read(path)
old_props = '''    let type: ProfessionalReportType
    let startDate: Date
    let endDate: Date
    var scope = ProfessionalReportScope()

    @State private var isGenerating = false
'''
new_props = '''    let type: ProfessionalReportType
    let startDate: Date
    let endDate: Date
    let transactionIDs: [UUID]
    let accountIDs: [UUID]
    let currencyCode: String?
    let reportTitle: String?

    init(
        type: ProfessionalReportType,
        startDate: Date,
        endDate: Date,
        transactionIDs: [UUID] = [],
        accountIDs: [UUID] = [],
        currencyCode: String? = nil,
        reportTitle: String? = nil
    ) {
        self.type = type
        self.startDate = startDate
        self.endDate = endDate
        self.transactionIDs = transactionIDs
        self.accountIDs = accountIDs
        self.currencyCode = currencyCode
        self.reportTitle = reportTitle
    }

    private var reportScope: ProfessionalReportScope {
        var value = ProfessionalReportScope()
        value.transactionIDs = Set(transactionIDs)
        value.accountIDs = Set(accountIDs)
        value.currencyCode = currencyCode
        value.reportTitle = reportTitle
        return value
    }

    @State private var isGenerating = false
'''
if text.count(old_props) != 1:
    raise RuntimeError(f"ReportDownloadButton property anchor count: {text.count(old_props)}")
text = text.replace(old_props, new_props, 1)
if text.count("scope: scope") != 1:
    raise RuntimeError(f"ReportDownloadButton scope call count: {text.count('scope: scope')}")
text = text.replace("scope: scope", "scope: reportScope", 1)
write(path, text)

print("Fixed Next Ledger 1.3.64 generated report compile compatibility and scoped snapshot exports.")
