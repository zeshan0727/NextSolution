from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def write(relative: str, content: str) -> None:
    (ROOT / relative).write_text(content, encoding="utf-8")


def replace_once(relative: str, old: str, new: str) -> None:
    text = read(relative)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(
            f"Expected one match in {relative}, found {count}: {old[:180]!r}"
        )
    write(relative, text.replace(old, new, 1))


# Central report conversion. Account nature never changes transaction type: an
# expense paid from a bank account remains an expense. Report totals convert the
# original account currency using the same fixed rates used by transfers.
store = "DailyLedger/Services/LedgerStore.swift"
replace_once(
    store,
    """    func reportIncomeAccountID(_ transaction: LedgerTransaction) -> UUID? {
        isAmaraTransfer(transaction) ? transaction.destinationAccountID : transaction.accountID
    }

""",
    """    func reportIncomeAccountID(_ transaction: LedgerTransaction) -> UUID? {
        isAmaraTransfer(transaction) ? transaction.destinationAccountID : transaction.accountID
    }

    func fixedReportConversionRate(from sourceCode: String, to destinationCode: String) -> Decimal? {
        let source = sourceCode.uppercased()
        let destination = destinationCode.uppercased()
        if source == destination { return Decimal(1) }

        let qarToPkr = Decimal(string: "77")!
        let usdToQar = Decimal(string: "3.65")!
        let usdToPkr = usdToQar * qarToPkr

        switch (source, destination) {
        case ("QAR", "PKR"):
            return qarToPkr
        case ("PKR", "QAR"):
            return Decimal(1) / qarToPkr
        case ("USD", "QAR"):
            return usdToQar
        case ("QAR", "USD"):
            return Decimal(1) / usdToQar
        case ("USD", "PKR"):
            return usdToPkr
        case ("PKR", "USD"):
            return Decimal(1) / usdToPkr
        default:
            return nil
        }
    }

    func convertedReportAmount(
        _ amount: Decimal,
        accountID: UUID?,
        to destinationCode: String? = nil
    ) -> Decimal? {
        let destination = (destinationCode ?? currencyCode).uppercased()
        let source = account(withID: accountID)?.currencyCode.uppercased() ?? destination
        guard let rate = fixedReportConversionRate(from: source, to: destination) else {
            return nil
        }
        var input = amount * rate
        var output = Decimal.zero
        NSDecimalRound(&output, &input, 2, .plain)
        return output
    }

    func convertedReportIncomeAmount(
        _ transaction: LedgerTransaction,
        to destinationCode: String? = nil
    ) -> Decimal? {
        guard isReportIncome(transaction) else { return nil }
        return convertedReportAmount(
            reportIncomeAmount(transaction),
            accountID: reportIncomeAccountID(transaction),
            to: destinationCode
        )
    }

    func convertedReportExpenseAmount(
        _ transaction: LedgerTransaction,
        to destinationCode: String? = nil
    ) -> Decimal? {
        guard transaction.type == .expense else { return nil }
        return convertedReportAmount(
            transaction.amount,
            accountID: transaction.accountID,
            to: destinationCode
        )
    }

""",
)

replace_once(
    store,
    """    func totals(in interval: DateInterval, accountIDs: Set<UUID>? = nil) -> LedgerTotals {
        let cacheKey = reportCacheKey(interval: interval, accountIDs: accountIDs)
        if let cached = totalsCache[cacheKey] {
            return cached
        }
        let selected = transactions.filter {
            interval.contains($0.date) &&
            accountsByID[$0.accountID ?? LedgerAccount.legacyMainID]?.currencyCode == currencyCode &&
            (accountIDs == nil || accountIDs?.contains($0.accountID ?? LedgerAccount.legacyMainID) == true)
        }
        let income = transactions.lazy
            .filter {
                guard interval.contains($0.date), self.isReportIncome($0) else { return false }
                let incomeAccountID = self.reportIncomeAccountID($0) ?? LedgerAccount.legacyMainID
                return self.accountsByID[incomeAccountID]?.currencyCode == self.currencyCode &&
                    (accountIDs == nil || accountIDs?.contains(incomeAccountID) == true)
            }
            .reduce(Decimal.zero) { $0 + self.reportIncomeAmount($1) }
        let expense = selected
            .filter { $0.type == .expense }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let loan = selected
            .filter {
                $0.type == .transfer &&
                accountsByID[$0.destinationAccountID ?? LedgerAccount.legacyMainID]?.group == .payments
            }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let transfer = selected
            .filter { $0.type == .transfer }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let result = LedgerTotals(
            income: income,
            expense: expense,
            loan: loan,
            transfer: transfer,
            count: selected.count
        )
        totalsCache[cacheKey] = result
        return result
    }
""",
    """    func totals(in interval: DateInterval, accountIDs: Set<UUID>? = nil) -> LedgerTotals {
        let cacheKey = reportCacheKey(interval: interval, accountIDs: accountIDs)
        if let cached = totalsCache[cacheKey] {
            return cached
        }

        let selectedBySourceAccount = transactions.filter {
            interval.contains($0.date) &&
            (accountIDs == nil || accountIDs?.contains($0.accountID ?? LedgerAccount.legacyMainID) == true)
        }
        let expenseTransactions = selectedBySourceAccount.filter {
            $0.type == .expense && convertedReportExpenseAmount($0) != nil
        }
        let incomeTransactions = transactions.filter {
            guard interval.contains($0.date), isReportIncome($0) else { return false }
            let incomeAccountID = reportIncomeAccountID($0) ?? LedgerAccount.legacyMainID
            return (accountIDs == nil || accountIDs?.contains(incomeAccountID) == true) &&
                convertedReportIncomeAmount($0) != nil
        }
        let sameCurrencySelected = selectedBySourceAccount.filter {
            accountsByID[$0.accountID ?? LedgerAccount.legacyMainID]?.currencyCode == currencyCode
        }

        let income = incomeTransactions.reduce(Decimal.zero) {
            $0 + (convertedReportIncomeAmount($1) ?? 0)
        }
        let expense = expenseTransactions.reduce(Decimal.zero) {
            $0 + (convertedReportExpenseAmount($1) ?? 0)
        }
        let loan = sameCurrencySelected
            .filter {
                $0.type == .transfer &&
                accountsByID[$0.destinationAccountID ?? LedgerAccount.legacyMainID]?.group == .payments
            }
            .reduce(Decimal.zero) { $0 + $1.amount }
        let transfer = sameCurrencySelected
            .filter { $0.type == .transfer }
            .reduce(Decimal.zero) { $0 + $1.amount }

        let countedIDs = Set(
            expenseTransactions.map(\\.id) +
            incomeTransactions.map(\\.id) +
            sameCurrencySelected.filter { $0.type == .transfer }.map(\\.id)
        )
        let result = LedgerTotals(
            income: income,
            expense: expense,
            loan: loan,
            transfer: transfer,
            count: countedIDs.count
        )
        totalsCache[cacheKey] = result
        return result
    }
""",
)

reports = "DailyLedger/Views/ReportsView.swift"

replace_once(
    reports,
    """    private func amount(_ type: TransactionType, in interval: DateInterval) -> Decimal {
        store.transactions.lazy.filter {
            guard interval.contains($0.date) else { return false }
            if type == .income {
                return store.isReportIncome($0) &&
                    store.account(withID: store.reportIncomeAccountID($0))?.currencyCode == store.currencyCode
            }
            return $0.type == type &&
                store.account(withID: $0.accountID)?.currencyCode == store.currencyCode
        }.reduce(Decimal.zero) {
            $0 + (type == .income ? store.reportIncomeAmount($1) : $1.amount)
        }
    }
""",
    """    private func amount(_ type: TransactionType, in interval: DateInterval) -> Decimal {
        store.transactions.lazy.filter {
            guard interval.contains($0.date) else { return false }
            if type == .income {
                return store.convertedReportIncomeAmount($0) != nil
            }
            return store.convertedReportExpenseAmount($0) != nil
        }.reduce(Decimal.zero) {
            $0 + (type == .income
                ? (store.convertedReportIncomeAmount($1) ?? 0)
                : (store.convertedReportExpenseAmount($1) ?? 0))
        }
    }
""",
)

replace_once(
    reports,
    """    private func transactionCount(in interval: DateInterval) -> Int {
        store.transactions.lazy.filter {
            guard interval.contains($0.date) else { return false }
            if store.isReportIncome($0) {
                return store.account(withID: store.reportIncomeAccountID($0))?.currencyCode == store.currencyCode
            }
            return $0.type == .expense &&
                store.account(withID: $0.accountID)?.currencyCode == store.currencyCode
        }.count
    }
""",
    """    private func transactionCount(in interval: DateInterval) -> Int {
        store.transactions.lazy.filter {
            guard interval.contains($0.date) else { return false }
            if store.isReportIncome($0) {
                return store.convertedReportIncomeAmount($0) != nil
            }
            return store.convertedReportExpenseAmount($0) != nil
        }.count
    }
""",
)

replace_once(
    reports,
    """    private func matchingTransactions(_ type: TransactionType, in interval: DateInterval) -> [LedgerTransaction] {
        transactions(in: interval).filter {
            if type == .income {
                return store.isReportIncome($0) &&
                    selected.contains(store.reportIncomeAccountID($0) ?? LedgerAccount.legacyMainID)
            }
            return $0.type == type && selected.contains($0.accountID ?? LedgerAccount.legacyMainID)
        }
    }
    private func total(_ type: TransactionType, in interval: DateInterval) -> Decimal {
        matchingTransactions(type, in: interval).reduce(0) {
            $0 + (type == .income ? store.reportIncomeAmount($1) : $1.amount)
        }
    }
""",
    """    private func matchingTransactions(_ type: TransactionType, in interval: DateInterval) -> [LedgerTransaction] {
        transactions(in: interval).filter {
            if type == .income {
                return store.isReportIncome($0) &&
                    selected.contains(store.reportIncomeAccountID($0) ?? LedgerAccount.legacyMainID) &&
                    store.convertedReportIncomeAmount($0) != nil
            }
            return $0.type == .expense &&
                selected.contains($0.accountID ?? LedgerAccount.legacyMainID) &&
                store.convertedReportExpenseAmount($0) != nil
        }
    }
    private func total(_ type: TransactionType, in interval: DateInterval) -> Decimal {
        matchingTransactions(type, in: interval).reduce(0) {
            $0 + (type == .income
                ? (store.convertedReportIncomeAmount($1) ?? 0)
                : (store.convertedReportExpenseAmount($1) ?? 0))
        }
    }
""",
)

replace_once(
    reports,
    """    private var transactionListTotal: Decimal {
        selectedTransactions.reduce(Decimal.zero) {
            $0 + (kind == .income ? store.reportIncomeAmount($1) : $1.amount)
        }
    }
""",
    """    private var transactionListTotal: Decimal {
        selectedTransactions.reduce(Decimal.zero) {
            switch kind {
            case .income:
                return $0 + (store.convertedReportIncomeAmount($1) ?? 0)
            case .expenses:
                return $0 + (store.convertedReportExpenseAmount($1) ?? 0)
            default:
                return $0 + $1.amount
            }
        }
    }
""",
)

replace_once(
    reports,
    """    private var selectedTransactions: [LedgerTransaction] {
        if kind == .expenses { return cachedExpenseTransactions }
        return store.transactions.filter {
            guard selectedInterval.contains($0.date) else { return false }
            let kindMatches: Bool
            switch kind {
            case .summary, .categories:
                kindMatches = store.account(withID: $0.accountID)?.currencyCode == store.currencyCode
            case .income:
                kindMatches = store.isReportIncome($0) &&
                    store.account(withID: store.reportIncomeAccountID($0))?.currencyCode == store.currencyCode
            case .expenses:
                kindMatches = $0.type == .expense &&
                    store.account(withID: $0.accountID)?.currencyCode == store.currencyCode
            case .loans:
                kindMatches = $0.type == .transfer &&
                    store.account(withID: $0.accountID)?.currencyCode == store.currencyCode &&
                    store.account(withID: $0.destinationAccountID)?.group == .payments
            }
            guard kindMatches, !searchText.isEmpty else { return kindMatches }
            return $0.category.localizedCaseInsensitiveContains(searchText) ||
                ($0.vendor?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                $0.details.localizedCaseInsensitiveContains(searchText) ||
                NSDecimalNumber(decimal: $0.amount).stringValue.contains(searchText)
        }
    }

    private func refreshExpenseCache() {
        guard kind == .expenses else { return }
        let interval = selectedInterval
        let accountCurrency = Dictionary(uniqueKeysWithValues: store.accounts.map { ($0.id, $0.currencyCode) })
        let query = searchText
        cachedExpenseTransactions = store.transactions.filter {
            guard $0.type == .expense, interval.contains($0.date),
                  accountCurrency[$0.accountID ?? LedgerAccount.legacyMainID] == store.currencyCode else { return false }
            guard !query.isEmpty else { return true }
            return $0.category.localizedCaseInsensitiveContains(query) ||
                ($0.vendor?.localizedCaseInsensitiveContains(query) ?? false) ||
                $0.details.localizedCaseInsensitiveContains(query) ||
                NSDecimalNumber(decimal: $0.amount).stringValue.contains(query)
        }
    }
""",
    """    private var selectedTransactions: [LedgerTransaction] {
        if kind == .expenses { return cachedExpenseTransactions }
        return store.transactions.filter {
            guard selectedInterval.contains($0.date) else { return false }
            let kindMatches: Bool
            switch kind {
            case .summary, .categories:
                kindMatches = store.convertedReportIncomeAmount($0) != nil ||
                    store.convertedReportExpenseAmount($0) != nil
            case .income:
                kindMatches = store.convertedReportIncomeAmount($0) != nil
            case .expenses:
                kindMatches = store.convertedReportExpenseAmount($0) != nil
            case .loans:
                kindMatches = $0.type == .transfer &&
                    store.account(withID: $0.accountID)?.currencyCode == store.currencyCode &&
                    store.account(withID: $0.destinationAccountID)?.group == .payments
            }
            guard kindMatches, !searchText.isEmpty else { return kindMatches }
            return $0.category.localizedCaseInsensitiveContains(searchText) ||
                ($0.vendor?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                $0.details.localizedCaseInsensitiveContains(searchText) ||
                NSDecimalNumber(decimal: $0.amount).stringValue.contains(searchText)
        }
    }

    private func refreshExpenseCache() {
        guard kind == .expenses else { return }
        let interval = selectedInterval
        let query = searchText
        cachedExpenseTransactions = store.transactions.filter {
            guard interval.contains($0.date),
                  store.convertedReportExpenseAmount($0) != nil else { return false }
            guard !query.isEmpty else { return true }
            return $0.category.localizedCaseInsensitiveContains(query) ||
                ($0.vendor?.localizedCaseInsensitiveContains(query) ?? false) ||
                $0.details.localizedCaseInsensitiveContains(query) ||
                NSDecimalNumber(decimal: $0.amount).stringValue.contains(query)
        }
    }
""",
)

replace_once(
    reports,
    """    private var categoryTotals: [CategoryTotal] {
        let expenses = selectedTransactions.filter { $0.type == .expense }
        let grouped = Dictionary(grouping: expenses, by: \\.category)
        return grouped.map { category, items in
            CategoryTotal(
                id: category,
                name: category,
                amount: items.reduce(Decimal.zero) { $0 + $1.amount }
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    private func makeBucket(id: String, label: String, items: [LedgerTransaction]) -> ReportBucket {
        let income = items.filter(store.isReportIncome).reduce(Decimal.zero) {
            $0 + store.reportIncomeAmount($1)
        }
        let expense = items.filter { $0.type == .expense }.reduce(Decimal.zero) { $0 + $1.amount }
""",
    """    private var categoryTotals: [CategoryTotal] {
        let expenses = selectedTransactions.filter { $0.type == .expense }
        let grouped = Dictionary(grouping: expenses, by: \\.category)
        return grouped.map { category, items in
            CategoryTotal(
                id: category,
                name: category,
                amount: items.reduce(Decimal.zero) {
                    $0 + (store.convertedReportExpenseAmount($1) ?? 0)
                }
            )
        }
        .sorted { $0.amount > $1.amount }
    }

    private func makeBucket(id: String, label: String, items: [LedgerTransaction]) -> ReportBucket {
        let income = items.filter(store.isReportIncome).reduce(Decimal.zero) {
            $0 + (store.convertedReportIncomeAmount($1) ?? 0)
        }
        let expense = items.filter { $0.type == .expense }.reduce(Decimal.zero) {
            $0 + (store.convertedReportExpenseAmount($1) ?? 0)
        }
""",
)

replace_once(
    reports,
    """            LabeledContent("Total", value: DisplayFormat.currency(items.reduce(0) {
                $0 + (type == .income ? store.reportIncomeAmount($1) : $1.amount)
            }, code: store.currencyCode))
""",
    """            LabeledContent("Total", value: DisplayFormat.currency(items.reduce(0) {
                $0 + (type == .income
                    ? (store.convertedReportIncomeAmount($1) ?? 0)
                    : (store.convertedReportExpenseAmount($1) ?? 0))
            }, code: store.currencyCode))
""",
)

replace_once(
    reports,
    """    private var transactions: [LedgerTransaction] {
        store.transactions.filter {
            guard interval.contains($0.date) else { return false }
            if store.isReportIncome($0) {
                return store.account(withID: store.reportIncomeAccountID($0))?.currencyCode == store.currencyCode
            }
            return $0.type == .expense &&
                store.account(withID: $0.accountID)?.currencyCode == store.currencyCode
        }.sorted { $0.date > $1.date }
    }
""",
    """    private var transactions: [LedgerTransaction] {
        store.transactions.filter {
            guard interval.contains($0.date) else { return false }
            if store.isReportIncome($0) {
                return store.convertedReportIncomeAmount($0) != nil
            }
            return store.convertedReportExpenseAmount($0) != nil
        }.sorted { $0.date > $1.date }
    }
""",
)

replace_once(
    reports,
    """    private var transactions: [LedgerTransaction] {
        store.transactions.filter {
            guard interval.contains($0.date) else { return false }
            if type == .income {
                return store.isReportIncome($0) &&
                    accountIDs.contains(store.reportIncomeAccountID($0) ?? LedgerAccount.legacyMainID)
            }
            return accountIDs.contains($0.accountID ?? LedgerAccount.legacyMainID) && $0.type == type
        }.sorted { $0.date > $1.date }
    }
    private var total: Decimal {
        transactions.reduce(0) {
            $0 + (type == .income ? store.reportIncomeAmount($1) : $1.amount)
        }
    }
""",
    """    private var transactions: [LedgerTransaction] {
        store.transactions.filter {
            guard interval.contains($0.date) else { return false }
            if type == .income {
                return store.isReportIncome($0) &&
                    accountIDs.contains(store.reportIncomeAccountID($0) ?? LedgerAccount.legacyMainID) &&
                    store.convertedReportIncomeAmount($0) != nil
            }
            return accountIDs.contains($0.accountID ?? LedgerAccount.legacyMainID) &&
                store.convertedReportExpenseAmount($0) != nil
        }.sorted { $0.date > $1.date }
    }
    private var total: Decimal {
        transactions.reduce(0) {
            $0 + (type == .income
                ? (store.convertedReportIncomeAmount($1) ?? 0)
                : (store.convertedReportExpenseAmount($1) ?? 0))
        }
    }
""",
)

period = "DailyLedger/Views/PeriodTransactionsView.swift"
replace_once(
    period,
    """            case .income:
                kindMatches = store.isReportIncome(transaction) &&
                    store.account(withID: store.reportIncomeAccountID(transaction))?.currencyCode == store.currencyCode
            case .expenses:
                kindMatches = transaction.type == .expense &&
                    store.account(withID: transaction.accountID)?.currencyCode == store.currencyCode
""",
    """            case .income:
                kindMatches = store.convertedReportIncomeAmount(transaction) != nil
            case .expenses:
                kindMatches = store.convertedReportExpenseAmount(transaction) != nil
""",
)
replace_once(
    period,
    """    private var total: Decimal {
        transactions.reduce(Decimal.zero) {
            $0 + (kind == .income ? store.reportIncomeAmount($1) : $1.amount)
        }
    }
""",
    """    private var total: Decimal {
        transactions.reduce(Decimal.zero) {
            switch kind {
            case .income:
                return $0 + (store.convertedReportIncomeAmount($1) ?? 0)
            case .expenses:
                return $0 + (store.convertedReportExpenseAmount($1) ?? 0)
            case .loans:
                return $0 + $1.amount
            }
        }
    }
""",
)

category = "DailyLedger/Views/CategoryTransactionsView.swift"
replace_once(
    category,
    """        store.transactions.filter {
            interval.contains($0.date) &&
            $0.category.caseInsensitiveCompare(category) == .orderedSame &&
            store.account(withID: $0.accountID)?.currencyCode == store.currencyCode &&
            (searchText.isEmpty ||
""",
    """        store.transactions.filter {
            interval.contains($0.date) &&
            $0.type == .expense &&
            $0.category.caseInsensitiveCompare(category) == .orderedSame &&
            store.convertedReportExpenseAmount($0) != nil &&
            (searchText.isEmpty ||
""",
)
replace_once(
    category,
    """    private var total: Decimal {
        transactions.reduce(Decimal.zero) { $0 + $1.amount }
    }
""",
    """    private var total: Decimal {
        transactions.reduce(Decimal.zero) {
            $0 + (store.convertedReportExpenseAmount($1) ?? 0)
        }
    }
""",
)

print("Included bank-account expenses in reports and converted QAR/PKR/USD amounts using fixed rates.")
