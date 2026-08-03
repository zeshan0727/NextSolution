from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one match in {path}, found {count}: {old[:240]!r}")
    write(path, text.replace(old, new, 1))


# Daemon: recognize incoming Fawran credits as editable transfer drafts.
source = "RootHideSMSQueue/Sources/main.m"
replace_once(
    source,
    'static NSString *const kDaemonVersion = @"2.1.3";',
    'static NSString *const kDaemonVersion = @"2.1.4";',
)
replace_once(
    source,
    '''    else if ([lower containsString:@"used for"] || [lower containsString:@"purchase"] || [lower containsString:@"debited"]) kind = @"expense";
    else if ([lower containsString:@"credited to"] || [lower containsString:@"received"]) kind = @"income";
''',
    '''    else if ([lower containsString:@"current acc"] && [lower containsString:@"credited with"] && [lower containsString:@"fawran instant payment"]) kind = @"incomingTransfer";
    else if ([lower containsString:@"used for"] || [lower containsString:@"purchase"] || [lower containsString:@"debited"]) kind = @"expense";
    else if ([lower containsString:@"credited to"] || [lower containsString:@"received"]) kind = @"income";
''',
)
replace_once(
    source,
    '''    NSString *ending = Capture(@"\\\\*\\\\*(\\\\d{4})", clean, 1);
    if (!ending) return nil;
''',
    '''    NSString *ending = Capture(@"\\\\*\\\\*(\\\\d{4})", clean, 1);
    if (!ending) ending = Capture(@"\\\\bCurrent\\\\s+Acc\\\\s+x{2,}(\\\\d{4,8})\\\\b", clean, 1);
    if (!ending) return nil;
''',
)
replace_once(
    source,
    '''    } else if ([kind isEqualToString:@"cashback"]) {
        vendor = @"Credit Card Cashback";
    } else {
''',
    '''    } else if ([kind isEqualToString:@"incomingTransfer"]) {
        vendor = Capture(@"\\\\bref\\\\s+(.+?)(?=\\\\s+withM-|\\\\s+at\\\\s+\\\\d{1,2}:\\\\d{2}|$)", clean, 1) ?: @"Fawran Instant Payment";
    } else if ([kind isEqualToString:@"cashback"]) {
        vendor = @"Credit Card Cashback";
    } else {
''',
)
replace_once(
    source,
    '''        @{@"pattern": @"\\\\b(\\\\d{1,2}:\\\\d{2})\\\\s+(\\\\d{1,2}-[A-Za-z]{3}-\\\\d{4})\\\\b", @"format": @"HH:mm dd-MMM-yyyy"},
        @{@"pattern": @"\\\\b(\\\\d{1,2}:\\\\d{2})\\\\s+(\\\\d{1,2}-[A-Za-z]{3}-\\\\d{2})\\\\b", @"format": @"HH:mm dd-MMM-yy"}
''',
    '''        @{@"pattern": @"\\\\b(\\\\d{1,2}:\\\\d{2}),?\\\\s+(\\\\d{1,2}-[A-Za-z]{3}-\\\\d{4})\\\\b", @"format": @"HH:mm dd-MMM-yyyy"},
        @{@"pattern": @"\\\\b(\\\\d{1,2}:\\\\d{2}),?\\\\s+(\\\\d{1,2}-[A-Za-z]{3}-\\\\d{2})\\\\b", @"format": @"HH:mm dd-MMM-yy"}
''',
)
replace_once(
    source,
    '''        @"\\\\b(Cashback amount of\\\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\\\s*[0-9][0-9,]*(?:\\\\.[0-9]{1,2})?.*?Available Limit(?:\\\\s+is|:)?\\\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\\\s*[0-9][0-9,]*(?:\\\\.[0-9]{1,2})?)\\\\b"
''',
    '''        @"\\\\b(Cashback amount of\\\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\\\s*[0-9][0-9,]*(?:\\\\.[0-9]{1,2})?.*?Available Limit(?:\\\\s+is|:)?\\\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\\\s*[0-9][0-9,]*(?:\\\\.[0-9]{1,2})?)\\\\b",
        @"\\\\b(Current Acc\\\\s+x{2,}\\\\d{4,8}\\\\s+credited with\\\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\\\s*[0-9][0-9,]*(?:\\\\.[0-9]{1,2})?\\\\s+for Fawran instant payment.*?Current Acc Bal:\\s+(?:QAR|QR|USD|PKR|AED|SAR|EUR|GBP)\\\\s*[0-9][0-9,]*(?:\\\\.[0-9]{1,2})?)\\\\b"
''',
)
replace_once(
    source,
    '''        if (!CardEndingApproved(config, parsed[@"cardEnding"])) {
            ignoredCard += 1;
''',
    '''        BOOL requiresMappedEnding = ![parsed[@"kind"] isEqualToString:@"incomingTransfer"];
        if (requiresMappedEnding && !CardEndingApproved(config, parsed[@"cardEnding"])) {
            ignoredCard += 1;
''',
)
replace_once(
    source,
    '''        @{
            @"name": @"loan payment transfer",
            @"sms": @"Bill Payment of QAR 1279.31 from card **0023 to LOAN PAYMENT FOR XXXXXXXX on 25/07/2026 17:15 was successful.",
            @"kind": @"billPayment", @"ending": @"0023", @"amount": @"1279.31"
        }
''',
    '''        @{
            @"name": @"loan payment transfer",
            @"sms": @"Bill Payment of QAR 1279.31 from card **0023 to LOAN PAYMENT FOR XXXXXXXX on 25/07/2026 17:15 was successful.",
            @"kind": @"billPayment", @"ending": @"0023", @"amount": @"1279.31"
        },
        @{
            @"name": @"incoming Fawran transfer",
            @"sms": @"Current Acc xxx364001 credited with QAR 1,000.00 for Fawran instant payment ref zeeshan,MOHAMED ASHFAAQ MOHAMED AZW withM-33510982 at 16:09, 03-Aug-26 Current Acc Bal: QAR 2,596.69",
            @"kind": @"incomingTransfer", @"ending": @"364001", @"amount": @"1000"
        }
''',
)

# App model: treat the new parser suggestion as Transfer and keep the clean counterparty.
service = "DailyLedger/Services/SMSImportConsoleService.swift"
replace_once(
    service,
    '''        case "withdrawal", "billPayment": return .transfer
''',
    '''        case "withdrawal", "billPayment", "incomingTransfer": return .transfer
''',
)
replace_once(
    service,
    '''        case "withdrawal":
            pattern = "(?i)\\\\bat\\\\s+(.+?)(?=\\\\s+your available|\\\\s+available balance|$)"
        case "billPayment":
''',
    '''        case "withdrawal":
            pattern = "(?i)\\\\bat\\\\s+(.+?)(?=\\\\s+your available|\\\\s+available balance|$)"
        case "incomingTransfer":
            pattern = "(?i)\\\\bref\\\\s+(.+?)(?=\\\\s+withM-|\\\\s+at\\\\s+\\\\d{1,2}:\\\\d{2}|$)"
        case "billPayment":
''',
)

# Optional persistent mapping for the user's Current Account; every account remains editable in the draft.
console = "DailyLedger/Views/SMSImportConsoleView.swift"
replace_once(
    console,
    '''                accountPicker(
                    title: "Cash Account",
''',
    '''                accountPicker(
                    title: "Current Account xxx364001",
                    selection: cardBinding("364001"),
                    suggestedWords: ["364001", "current", "cbq"]
                )
                accountPicker(
                    title: "Cash Account",
''',
)
replace_once(
    console,
    '''        if configuration.cashAccountID == nil,
''',
    '''        if configuration.cardAccountIDs["364001"] == nil,
           let account = suggestedAccount(words: ["364001", "current", "cbq"]) {
            configuration.cardAccountIDs["364001"] = account.id.uuidString
        }
        if configuration.cashAccountID == nil,
''',
)

# Add a direct reviewed-transaction writer so all fields can be corrected before approval.
store = "DailyLedger/Services/LedgerStore.swift"
replace_once(
    store,
    '''    @discardableResult
    func approveSMSDraft(_ draft: SMSImportDraft, configuration: SMSImportConfiguration) -> Bool {
''',
    '''    @discardableResult
    func approveReviewedSMSDraft(
        _ draft: SMSImportDraft,
        transactionType: TransactionType,
        amount: Decimal,
        date: Date,
        category: String,
        vendor: String,
        details: String,
        accountID: UUID,
        destinationAccountID: UUID?
    ) -> Bool {
        guard requireOpenPeriod(date, action: "approve") else { return false }
        if transactions.contains(where: { $0.id == draft.id }) { return true }
        guard amount > 0 else {
            errorMessage = "Enter an amount greater than zero."
            return false
        }
        guard let sourceAccount = accountsByID[accountID] else {
            errorMessage = "Choose a valid account."
            return false
        }

        let cleanCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanVendor = vendor.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanDetails.isEmpty else {
            errorMessage = "Description cannot be empty."
            return false
        }

        let item: LedgerTransaction
        if transactionType == .transfer {
            guard let destinationAccountID,
                  let destinationAccount = accountsByID[destinationAccountID],
                  destinationAccountID != accountID else {
                errorMessage = "Choose different From and To accounts for the transfer."
                return false
            }
            guard sourceAccount.currencyCode == destinationAccount.currencyCode else {
                errorMessage = "For SMS draft transfers, choose From and To accounts with the same currency."
                return false
            }
            item = LedgerTransaction(
                id: draft.id,
                type: .transfer,
                amount: amount,
                date: date,
                category: cleanCategory.isEmpty ? "Transfer" : cleanCategory,
                vendor: cleanVendor,
                details: cleanDetails,
                accountID: accountID,
                destinationAccountID: destinationAccountID,
                destinationAmount: amount
            )
        } else {
            item = LedgerTransaction(
                id: draft.id,
                type: transactionType,
                amount: amount,
                date: date,
                category: cleanCategory.isEmpty ? "Other" : cleanCategory,
                vendor: cleanVendor,
                details: cleanDetails,
                accountID: accountID
            )
        }

        do {
            let ledger = try LedgerDiskStore.shared.mutate { ledger in
                guard !ledger.transactions.contains(where: { $0.id == item.id }) else { return }
                ledger.transactions.append(item)
            }
            apply(ledger)
            return true
        } catch {
            errorMessage = "The reviewed SMS draft could not be recorded."
            return false
        }
    }

    @discardableResult
    func approveSMSDraft(_ draft: SMSImportDraft, configuration: SMSImportConfiguration) -> Bool {
''',
)

# Replace the inbox with compact cards plus a complete editable review screen.
inbox = r'''import SwiftUI

enum SMSDraftReviewType: String, CaseIterable, Identifiable {
    case income = "Income"
    case expense = "Expense"
    case transfer = "Transfer"

    var id: String { rawValue }

    var transactionType: TransactionType {
        switch self {
        case .income: return .income
        case .expense: return .expense
        case .transfer: return .transfer
        }
    }
}

struct SMSDraftInboxView: View {
    @State private var drafts: [SMSImportDraft] = []
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        List {
            if drafts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("No SMS Drafts")
                        .font(.headline)
                    Text("Only new, never-reviewed bank SMS will appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            } else {
                ForEach(drafts) { draft in
                    NavigationLink {
                        SMSDraftReviewView(draft: draft)
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(draft.cleanedVendor.isEmpty ? "Unknown Vendor" : draft.cleanedVendor)
                                    .font(.headline)
                                    .lineLimit(2)
                                Spacer()
                                Text("\(draft.currency) \(draft.amount.formatted())")
                                    .font(.headline)
                            }
                            HStack {
                                Label(draft.displayType, systemImage: draft.transactionType == .transfer ? "arrow.left.arrow.right.circle.fill" : (draft.transactionType == .income ? "arrow.down.circle.fill" : "arrow.up.circle.fill"))
                                Spacer()
                                Text(draft.date.formatted(date: .abbreviated, time: .shortened))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            Text("Tap to review type, accounts, category and all transaction details")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 7)
                    }
                }
            }
        }
        .navigationTitle("SMS Drafts")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .onReceive(timer) { _ in reload() }
    }

    private func reload() {
        drafts = SMSImportConsoleService.loadDrafts().sorted {
            if $0.rowID != $1.rowID { return $0.rowID > $1.rowID }
            return $0.queuedAt > $1.queuedAt
        }
    }
}

struct SMSDraftReviewView: View {
    @EnvironmentObject private var store: LedgerStore
    @Environment(\.dismiss) private var dismiss

    let draft: SMSImportDraft

    @State private var initialized = false
    @State private var reviewType: SMSDraftReviewType = .expense
    @State private var amountText = ""
    @State private var date = Date()
    @State private var vendor = ""
    @State private var category = ""
    @State private var details = ""
    @State private var accountID: UUID?
    @State private var destinationAccountID: UUID?
    @State private var notice: String?

    var body: some View {
        Form {
            Section("Transaction") {
                Picker("Type", selection: $reviewType) {
                    ForEach(SMSDraftReviewType.allCases) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)

                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)
                Text(draft.currency)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DatePicker("Date", selection: $date)
                TextField("Vendor / Counterparty", text: $vendor)
                TextField("Category", text: $category)
            }

            Section(reviewType == .transfer ? "Transfer Accounts" : "Account") {
                accountPicker(
                    title: reviewType == .transfer ? "From Account" : "Account",
                    selection: $accountID
                )
                if reviewType == .transfer {
                    accountPicker(title: "To Account", selection: $destinationAccountID)
                }
            }

            Section("Description") {
                TextEditor(text: $details)
                    .frame(minHeight: 130)
                Text("The complete original SMS is retained as the description. You may correct it before approval.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    approve()
                } label: {
                    Label("Approve and Record", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    reject()
                } label: {
                    Label("Reject Draft", systemImage: "xmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Review SMS Draft")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: prepareDefaults)
        .onChange(of: reviewType) { newValue in
            if newValue == .transfer && category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                category = "Transfer"
            }
        }
        .alert("SMS Draft", isPresented: Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )) {
            Button("OK", role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }

    private var activeAccounts: [LedgerAccount] {
        store.activeAccounts.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func accountPicker(title: String, selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) {
            Text("Select Account").tag(UUID?.none)
            ForEach(activeAccounts) { account in
                Text("\(account.name) · \(account.currencyCode)")
                    .tag(Optional(account.id))
            }
        }
    }

    private func prepareDefaults() {
        guard !initialized else { return }
        initialized = true
        amountText = NSDecimalNumber(decimal: draft.amount).stringValue
        date = draft.date
        vendor = draft.cleanedVendor
        details = draft.cleanedDescription
        category = store.smsDraftCategory(for: draft)

        switch draft.transactionType {
        case .income: reviewType = .income
        case .expense: reviewType = .expense
        case .transfer: reviewType = .transfer
        }

        let configuration = SMSImportConsoleService.loadConfiguration()
        let mapped = configuration.cardAccountIDs[draft.cardEnding].flatMap(UUID.init(uuidString:))
        switch draft.kind {
        case "incomingTransfer":
            destinationAccountID = mapped
        case "withdrawal":
            accountID = mapped
            destinationAccountID = configuration.cashAccountID.flatMap(UUID.init(uuidString:))
        case "billPayment":
            accountID = mapped
            destinationAccountID = configuration.loanPaymentAccountID.flatMap(UUID.init(uuidString:))
        default:
            accountID = mapped
        }
        if reviewType == .transfer { category = "Transfer" }
    }

    private func approve() {
        let normalized = amountText.replacingOccurrences(of: ",", with: "")
        guard let amount = Decimal(string: normalized), amount > 0 else {
            notice = "Enter a valid amount greater than zero."
            return
        }
        guard let accountID else {
            notice = reviewType == .transfer ? "Choose the From Account." : "Choose an account."
            return
        }
        if reviewType == .transfer && destinationAccountID == nil {
            notice = "Choose the To Account."
            return
        }

        guard store.approveReviewedSMSDraft(
            draft,
            transactionType: reviewType.transactionType,
            amount: amount,
            date: date,
            category: category,
            vendor: vendor,
            details: details,
            accountID: accountID,
            destinationAccountID: destinationAccountID
        ) else {
            notice = store.errorMessage ?? "This reviewed draft could not be recorded."
            return
        }

        do {
            try SMSImportConsoleService.completeDraft(draft)
            dismiss()
        } catch {
            notice = "The transaction was recorded, but the draft status could not be saved. Approving it again is safe because the transaction ID is duplicate-protected."
        }
    }

    private func reject() {
        do {
            try SMSImportConsoleService.completeDraft(draft)
            dismiss()
        } catch {
            notice = "The draft could not be rejected: \(error.localizedDescription)"
        }
    }
}
'''
write("DailyLedger/Views/SMSDraftInboxView.swift", inbox)

for path in ["RootHideSMSQueue/control"]:
    replace_once(path, "Version: 2.1.3", "Version: 2.1.4")
for path in ["RootHideSMSQueue/postinst", "RootHideSMSQueue/layout/DEBIAN/postinst"]:
    replace_once(
        path,
        "Next Ledger SMS Daemon 2.1.3 installation started",
        "Next Ledger SMS Daemon 2.1.4 installation started",
    )

print("Added Fawran incoming-transfer drafts and complete editable SMS draft review.")
