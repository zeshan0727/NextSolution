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
text = text.replace(needle, replacement, 1)

old_receivable = r'''            if !receivableMovements.isEmpty {
                ForEach(receivableMovements) { movement in
                    formulaOperator("+", color: color)
                    movementCard(
                        title: "Receivable Collected",
                        movement: movement,
                        icon: "person.crop.circle.badge.checkmark",
                        color: AppTheme.blue
                    )
                }
            }
'''
new_receivable = r'''            if !receivableMovements.isEmpty {
                ForEach(receivableMovements) { movement in
                    formulaOperator("+", color: color)
                    NavigationLink {
                        ReceivableCollectionTransactionsView(
                            interval: selectedInterval,
                            currencyCode: movement.currencyCode
                        )
                    } label: {
                        movementCard(
                            title: "Receivable Collected",
                            movement: movement,
                            icon: "person.crop.circle.badge.checkmark",
                            color: AppTheme.blue
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
'''
count = text.count(old_receivable)
if count != 1:
    raise RuntimeError(f"Expected one old receivable removal argument, found {count}")
text = text.replace(old_receivable, new_receivable, 1)

sms_marker = '''# ---------------------------------------------------------------------------
# SMS auto record. Off = drafts. On = background record only when every mapping
'''
remove_unused_drilldown = '''# Remove the now-unused receivable drill-down that an earlier patch appended.\nreports_text = read(reports)\nreceivable_view_marker = "\\nprivate struct ReceivableCollectionTransactionsView: View"\nif receivable_view_marker in reports_text:\n    reports_text = reports_text[:reports_text.index(receivable_view_marker)].rstrip() + "\\n"\nwrite(reports, reports_text)\n\n\n'''
count = text.count(sms_marker)
if count != 1:
    raise RuntimeError(f"Expected one SMS section marker, found {count}")
text = text.replace(sms_marker, remove_unused_drilldown + sms_marker, 1)

path.write_text(text, encoding="utf-8")
print("Prepared report conversion helpers and the actual receivable drill-down removal.")
