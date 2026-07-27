#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / "DailyLedger/Views/ReportsView.swift"
PROJECT = ROOT / "project.yml"

reports = REPORTS.read_text(encoding="utf-8")

card = '''            ReportTotalCard(
                title: "Carried Forward Balance",
                value: carriedForwardBalance,
                currencyCode: store.currencyCode,
                icon: "arrow.uturn.right.circle.fill",
                color: carriedForwardBalance >= 0 ? AppTheme.blue : AppTheme.red,
                secondaryText: "Opening balance before \\(selectedInterval.start.formatted(date: .abbreviated, time: .omitted))"
            )
'''

card_anchor = '''                .buttonStyle(.plain)
            }
            ForEach(store.loanNetMovements(in: selectedInterval)) { movement in
'''

if card not in reports:
    if card_anchor not in reports:
        raise RuntimeError("Could not locate Finance Summary card insertion point")
    reports = reports.replace(
        card_anchor,
        '''                .buttonStyle(.plain)
            }
''' + card + '''            ForEach(store.loanNetMovements(in: selectedInterval)) { movement in
''',
        1,
    )

current_logic = '''    private var financeSummaryNetBalance: Decimal {
        totals.income + convertedLoanMovement - totals.expense
    }

    private var convertedLoanMovement: Decimal {
        convertedLoanMovement(in: selectedInterval)
    }

    private func convertedLoanMovement(in interval: DateInterval) -> Decimal {
        store.loanNetMovements(in: interval).reduce(Decimal.zero) {
            result, movement in
            switch movement.currencyCode.uppercased() {
            case "QAR":
                return result + movement.netAmount
            case "PKR":
                return result + movement.netAmount / Decimal(77)
            default:
                return result
            }
        }
    }
'''

legacy_logic = '''    private var carriedForwardBalance: Decimal {
        let selectedAccounts = store.accounts.filter {
            !$0.isArchived &&
            $0.currencyCode.uppercased() == store.currencyCode.uppercased()
        }
        let selectedIDs = Set(selectedAccounts.map(\\.id))
        var balance = selectedAccounts.reduce(Decimal.zero) { $0 + $1.openingBalance }

        for transaction in store.transactions where transaction.date < selectedInterval.start {
            switch transaction.type {
            case .income:
                if transaction.accountID.map(selectedIDs.contains) == true {
                    balance += transaction.amount
                }
            case .expense:
                if transaction.accountID.map(selectedIDs.contains) == true {
                    balance -= transaction.amount
                }
            case .transfer:
                if transaction.accountID.map(selectedIDs.contains) == true {
                    balance -= transaction.amount
                }
                if transaction.destinationAccountID.map(selectedIDs.contains) == true {
                    balance += transaction.destinationAmount ?? transaction.amount
                }
            }
        }
        return balance
    }

    private var financeSummaryNetBalance: Decimal {
        totals.income + convertedLoanMovement - totals.expense
    }

    private var convertedLoanMovement: Decimal {
        store.loanNetMovements(in: selectedInterval).reduce(Decimal.zero) {
            result, movement in
            switch movement.currencyCode.uppercased() {
            case "QAR":
                return result + movement.netAmount
            case "PKR":
                return result + movement.netAmount / Decimal(77)
            default:
                return result
            }
        }
    }
'''

if legacy_logic not in reports:
    if current_logic not in reports:
        raise RuntimeError("Could not locate current Finance Summary calculation block")
    reports = reports.replace(current_logic, legacy_logic, 1)

REPORTS.write_text(reports, encoding="utf-8")

project = PROJECT.read_text(encoding="utf-8")
project = project.replace('MARKETING_VERSION: "1.3.38"', 'MARKETING_VERSION: "1.3.39"')
project = project.replace('CURRENT_PROJECT_VERSION: "46"', 'CURRENT_PROJECT_VERSION: "47"')
PROJECT.write_text(project, encoding="utf-8")

print("Finance Summary restored exactly to 1.3.37 behaviour; performance and logo changes retained.")
