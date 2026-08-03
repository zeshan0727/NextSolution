from pathlib import Path

path = Path(__file__).resolve().parent / "fix_financial_summary_auto_sms_and_compact_settings.py"
text = path.read_text(encoding="utf-8")

needle = r'''    func loanDecreaseAmount(_ transaction: LedgerTransaction) -> Decimal {
        guard transaction.type == .transfer,
              isBankAccount(account(withID: transaction.accountID)),
              isFinancialLoanAccount(account(withID: transaction.destinationAccountID)) else {
            return 0
        }
        return transaction.amount
    }

'''

replacement = needle + r'''    func fixedReportConversionRate(from sourceCode: String, to destinationCode: String) -> Decimal? {
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

'''

count = text.count(needle)
if count != 1:
    raise RuntimeError(f"Expected one financial flow helper marker, found {count}")
path.write_text(text.replace(needle, replacement, 1), encoding="utf-8")
print("Prepared the financial flow patch with fixed report conversion helpers.")
