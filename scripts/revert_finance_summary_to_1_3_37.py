#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPORTS = ROOT / "DailyLedger/Views/ReportsView.swift"
PROJECT = ROOT / "project.yml"

reports = REPORTS.read_text(encoding="utf-8")

old_card = '''            ReportTotalCard(
                title: "Carried Forward Balance",
                value: carriedForwardBalance,
                currencyCode: store.currencyCode,
                icon: "arrow.uturn.right.circle.fill",
                color: carriedForwardBalance >= 0 ? AppTheme.blue : AppTheme.red,
                secondaryText: "Opening balance + prior net activity before \\(selectedInterval.start.formatted(date: .abbreviated, time: .omitted))"
            )
'''
new_card = '''            ReportTotalCard(
                title: "Carried Forward Balance",
                value: carriedForwardBalance,
                currencyCode: store.currencyCode,
                icon: "arrow.uturn.right.circle.fill",
                color: carriedForwardBalance >= 0 ? AppTheme.blue : AppTheme.red,
                secondaryText: "Opening balance before \\(selectedInterval.start.formatted(date: .abbreviated, time: .omitted))"
            )
'''

old_logic = '''    private var openingBalance: Decimal {
        store.accounts.lazy
            .filter {
                !$0.isArchived &&
                $0.currencyCode.uppercased() == store.currencyCode.uppercased()
            }
            .reduce(Decimal.zero) { $0 + $1.openingBalance }
    }

    private var carriedForwardInterval: DateInterval? {
        guard let earliest = store.transactions.last?.date,
              earliest < selectedInterval.start else {
            return nil
        }
        return DateInterval(start: earliest, end: selectedInterval.start)
    }

    private var carriedForwardBalance: Decimal {
        guard let interval = carriedForwardInterval else {
            return openingBalance
        }
        let historicalTotals = store.totals(in: interval)
        return openingBalance
            + historicalTotals.income
            + convertedLoanMovement(in: interval)
            - historicalTotals.expense
    }

    private var financeSummaryNetBalance: Decimal {
        carriedForwardBalance
            + totals.income
            + convertedLoanMovement
            - totals.expense
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

new_logic = '''    private var carriedForwardBalance: Decimal {
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

if new_card not in reports:
    if old_card not in reports:
        raise RuntimeError("Could not locate the 1.3.38 carried-forward card")
    reports = reports.replace(old_card, new_card, 1)

if new_logic not in reports:
    if old_logic not in reports:
        raise RuntimeError("Could not locate the 1.3.38 Finance Summary logic")
    reports = reports.replace(old_logic, new_logic, 1)

REPORTS.write_text(reports, encoding="utf-8")

project = PROJECT.read_text(encoding="utf-8")
project = project.replace('MARKETING_VERSION: "1.3.38"', 'MARKETING_VERSION: "1.3.39"')
project = project.replace('CURRENT_PROJECT_VERSION: "46"', 'CURRENT_PROJECT_VERSION: "47"')
PROJECT.write_text(project, encoding="utf-8")

print("Reverted Finance Summary to 1.3.37 behaviour and set version 1.3.39.")
