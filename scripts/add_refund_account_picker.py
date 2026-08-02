from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one match in {path}, found {count}: {old[:100]!r}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


store_path = ROOT / "DailyLedger/Services/LedgerStore.swift"
replace_once(
    store_path,
    """        amount: Decimal,
        date: Date,
        details: String
    ) -> Bool {
""",
    """        amount: Decimal,
        date: Date,
        accountID: UUID,
        details: String
    ) -> Bool {
""",
)
replace_once(
    store_path,
    """        let remaining = refundableAmount(for: transaction)
        guard amount > 0, amount <= remaining else {
            errorMessage = "Refund amount must be greater than zero and no more than the remaining refundable amount."
            return false
        }

        let reverseType: TransactionType = transaction.type == .expense ? .income : .expense
""",
    """        let remaining = refundableAmount(for: transaction)
        guard amount > 0, amount <= remaining else {
            errorMessage = "Refund amount must be greater than zero and no more than the remaining refundable amount."
            return false
        }
        guard let refundAccount = account(withID: accountID),
              !refundAccount.isArchived || refundAccount.id == transaction.accountID else {
            errorMessage = "Choose an available refund account."
            return false
        }
        let originalCurrency = account(withID: transaction.accountID)?.currencyCode ?? currencyCode
        guard refundAccount.currencyCode == originalCurrency else {
            errorMessage = "The refund account must use the same currency as the original transaction."
            return false
        }

        let reverseType: TransactionType = transaction.type == .expense ? .income : .expense
""",
)
replace_once(
    store_path,
    """            details: refundDetails,
            accountID: transaction.accountID,
            refundOfTransactionID: transaction.id
""",
    """            details: refundDetails,
            accountID: accountID,
            refundOfTransactionID: transaction.id
""",
)

view_path = ROOT / "DailyLedger/Views/RefundTransactionView.swift"
replace_once(
    view_path,
    """    @State private var amountText = ""
    @State private var refundDate = Date()
""",
    """    @State private var amountText = ""
    @State private var selectedAccountID: UUID?
    @State private var refundDate = Date()
""",
)
replace_once(
    view_path,
    """                    LabeledContent(
                        "Account",
                        value: store.account(withID: transaction.accountID)?.name ?? "Unknown"
                    )
""",
    """                    LabeledContent(
                        "Original Account",
                        value: store.account(withID: transaction.accountID)?.name ?? "Unknown"
                    )
""",
)
replace_once(
    view_path,
    """                Section {
                    TextField("Refund amount", text: $amountText)
""",
    """                Section {
                    Picker("Refund To Account", selection: $selectedAccountID) {
                        ForEach(availableRefundAccounts) { account in
                            HStack {
                                Text(account.name)
                                Spacer()
                                Text(account.currencyCode)
                            }
                            .tag(Optional(account.id))
                        }
                    }
                    TextField("Refund amount", text: $amountText)
""",
)
replace_once(
    view_path,
    """                if amountText.isEmpty {
                    amountText = NSDecimalNumber(decimal: remainingAmount).stringValue
                }
""",
    """                if selectedAccountID == nil {
                    selectedAccountID = availableRefundAccounts.first(where: {
                        $0.id == transaction.accountID
                    })?.id ?? availableRefundAccounts.first?.id
                }
                if amountText.isEmpty {
                    amountText = NSDecimalNumber(decimal: remainingAmount).stringValue
                }
""",
)
replace_once(
    view_path,
    """    private var refundedAmount: Decimal {
        store.refundedAmount(for: transaction)
    }
""",
    """    private var availableRefundAccounts: [LedgerAccount] {
        store.accounts
            .filter {
                $0.currencyCode == currencyCode &&
                (!$0.isArchived || $0.id == transaction.accountID)
            }
            .sorted {
                if $0.group != $1.group { return $0.group.title < $1.group.title }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    private var refundedAmount: Decimal {
        store.refundedAmount(for: transaction)
    }
""",
)
replace_once(
    view_path,
    """    private var isValidAmount: Bool {
        guard let amount = parsedAmount else { return false }
        return amount > 0 && amount <= remainingAmount
    }
""",
    """    private var isValidAmount: Bool {
        guard let amount = parsedAmount,
              let selectedAccountID,
              availableRefundAccounts.contains(where: { $0.id == selectedAccountID }) else { return false }
        return amount > 0 && amount <= remainingAmount
    }
""",
)
replace_once(
    view_path,
    """        guard let amount = parsedAmount else {
            localError = "Enter a valid refund amount."
            return
        }
        if store.addRefund(
            for: transaction,
            amount: amount,
            date: refundDate,
            details: note
""",
    """        guard let amount = parsedAmount else {
            localError = "Enter a valid refund amount."
            return
        }
        guard let selectedAccountID else {
            localError = "Choose the account receiving the refund."
            return
        }
        if store.addRefund(
            for: transaction,
            amount: amount,
            date: refundDate,
            accountID: selectedAccountID,
            details: note
""",
)

print("Added same-currency account selection to transaction refunds.")
