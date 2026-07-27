#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_required(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    if old not in text:
        raise RuntimeError(f"Could not find expected source block: {label}")
    return text.replace(old, new, 1)


def update_file(path: Path, transform) -> None:
    original = path.read_text(encoding="utf-8")
    updated = transform(original)
    if updated != original:
        path.write_text(updated, encoding="utf-8")
        print(f"Updated {path.relative_to(ROOT)}")
    else:
        print(f"No changes needed for {path.relative_to(ROOT)}")


def update_budget_view(text: str) -> str:
    if "private struct BudgetOverviewCard: View" in text:
        return text

    text = replace_required(
        text,
        r'''            } else {
                Section {
                    ForEach(snapshots) { snapshot in
                        Button {
                            editorRoute = BudgetEditorRoute(budget: snapshot.budget)
                        } label: {
                            BudgetProgressRow(snapshot: snapshot)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: store.deleteBudgets)
                } header: {
                    Text("Current Budget Cycle")
                } footer: {
                    Text("Only expenses in the selected types, currency and custom date cycle count toward each budget.")
                }
            }
''',
        r'''            } else {
                Section {
                    BudgetOverviewCard(snapshots: snapshots)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(snapshots) { snapshot in
                        VStack(spacing: 10) {
                            Button {
                                editorRoute = BudgetEditorRoute(budget: snapshot.budget)
                            } label: {
                                BudgetProgressRow(snapshot: snapshot)
                            }
                            .buttonStyle(.plain)

                            if snapshot.id != snapshots.last?.id {
                                Divider()
                                    .padding(.horizontal, 10)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .onDelete(perform: store.deleteBudgets)
                } header: {
                    Text("Current Budget Cycle")
                } footer: {
                    Text("Only expenses in the selected types, currency and custom date cycle count toward each budget.")
                }
            }
''',
        "budget settings list",
    )

    text = replace_required(
        text,
        r'''            } else {
                Section {
                    ForEach(snapshots) { snapshot in
                        NavigationLink {
                            BudgetTransactionsView(snapshot: snapshot)
                        } label: {
                            BudgetConsumptionCard(snapshot: snapshot)
                        }
                    }
                } header: {
                    Text("Current Consumption")
                } footer: {
                    Text("Tap a budget to view the expenses included in its current custom cycle.")
                }
            }
''',
        r'''            } else {
                Section {
                    BudgetOverviewCard(snapshots: snapshots)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                Section {
                    ForEach(snapshots) { snapshot in
                        NavigationLink {
                            BudgetTransactionsView(snapshot: snapshot)
                        } label: {
                            BudgetConsumptionCard(snapshot: snapshot)
                        }
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                } header: {
                    Text("Current Consumption")
                } footer: {
                    Text("Tap a budget to view the expenses included in its current custom cycle.")
                }
            }
''',
        "budget consumption list",
    )

    overview_types = r'''private struct BudgetCurrencySummary: Identifiable {
    let currencyCode: String
    let budgeted: Decimal
    let spent: Decimal

    var id: String { currencyCode }

    var progress: Double {
        guard budgeted > 0 else { return 0 }
        return NSDecimalNumber(decimal: spent / budgeted).doubleValue
    }

    var remaining: Decimal { budgeted - spent }
}

private struct BudgetOverviewCard: View {
    let snapshots: [BudgetConsumptionSnapshot]

    private var summaries: [BudgetCurrencySummary] {
        Dictionary(grouping: snapshots) { $0.budget.currencyCode.uppercased() }
            .map { currencyCode, values in
                BudgetCurrencySummary(
                    currencyCode: currencyCode,
                    budgeted: values.reduce(Decimal.zero) { $0 + $1.budget.monthlyAmount },
                    spent: values.reduce(Decimal.zero) { $0 + $1.spent }
                )
            }
            .sorted { $0.currencyCode < $1.currencyCode }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Budget Summary", systemImage: "chart.pie.fill")
                    .font(.headline)
                    .foregroundStyle(AppTheme.purple)
                Spacer()
                Text("\(snapshots.count) budget\(snapshots.count == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            ForEach(summaries) { summary in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        BudgetSummaryMetric(
                            title: "Budgeted",
                            value: DisplayFormat.currency(summary.budgeted, code: summary.currencyCode)
                        )
                        Divider().frame(height: 34)
                        BudgetSummaryMetric(
                            title: "Spent",
                            value: DisplayFormat.currency(summary.spent, code: summary.currencyCode)
                        )
                        Divider().frame(height: 34)
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int((summary.progress * 100).rounded()))%")
                                .font(.title3.bold())
                                .foregroundStyle(summary.progress >= 1 ? AppTheme.red : (summary.progress >= 0.8 ? AppTheme.orange : AppTheme.green))
                            Text("used")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }

                    ProgressView(value: min(max(summary.progress, 0), 1))
                        .tint(summary.progress >= 1 ? AppTheme.red : (summary.progress >= 0.8 ? AppTheme.orange : AppTheme.green))

                    HStack {
                        Text(summary.currencyCode)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(
                            summary.remaining >= 0
                                ? "\(DisplayFormat.currency(summary.remaining, code: summary.currencyCode)) remaining"
                                : "\(DisplayFormat.currency(abs(summary.remaining), code: summary.currencyCode)) over budget"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(summary.remaining >= 0 ? AppTheme.green : AppTheme.red)
                    }
                }

                if summary.id != summaries.last?.id {
                    Divider()
                }
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.purple.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.05), radius: 12, y: 5)
    }
}

private struct BudgetSummaryMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

'''
    text = replace_required(
        text,
        "private struct EmptyBudgetMessage: View {",
        overview_types + "private struct EmptyBudgetMessage: View {",
        "budget overview types",
    )

    old_progress = r'''private struct BudgetProgressRow: View {
    let snapshot: BudgetConsumptionSnapshot

    private var budget: ExpenseBudget { snapshot.budget }
    private var spent: Decimal { snapshot.spent }

    private var progress: Double {
        min(max(snapshot.progress, 0), 1)
    }

    private var color: Color {
        if spent >= budget.monthlyAmount { return AppTheme.red }
        if progress >= 0.8 { return AppTheme.orange }
        return AppTheme.green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(
                    budget.displayName,
                    systemImage: AppTheme.categoryIcon(budget.categories.first ?? "Other")
                )
                    .font(.headline)
                Spacer()
                if budget.alertsEnabled {
                    Image(systemName: "bell.fill")
                        .font(.caption)
                        .foregroundStyle(progress >= 0.8 ? AppTheme.orange : .secondary)
                }
            }
            ProgressView(value: progress)
                .tint(color)
            Text(budget.categories.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text("Cycle: day \(budget.cycleStartDay) to day \(budget.cycleEndDay)")
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack {
                Text("\(DisplayFormat.currency(spent, code: budget.currencyCode)) spent")
                Spacer()
                Text("\(DisplayFormat.currency(budget.monthlyAmount, code: budget.currencyCode)) budget")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }
}
'''
    new_progress = r'''private struct BudgetProgressRow: View {
    let snapshot: BudgetConsumptionSnapshot

    private var budget: ExpenseBudget { snapshot.budget }
    private var spent: Decimal { snapshot.spent }

    private var progress: Double {
        min(max(snapshot.progress, 0), 1)
    }

    private var color: Color {
        if spent >= budget.monthlyAmount { return AppTheme.red }
        if progress >= 0.8 { return AppTheme.orange }
        return AppTheme.green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: AppTheme.categoryIcon(budget.categories.first ?? "Other"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 38, height: 38)
                    .background(color.opacity(0.12), in: Circle())

                VStack(alignment: .leading, spacing: 3) {
                    Text(budget.displayName)
                        .font(.headline)
                    Text(budget.categories.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int((snapshot.progress * 100).rounded()))%")
                        .font(.subheadline.bold())
                        .foregroundStyle(color)
                    if budget.alertsEnabled {
                        Image(systemName: "bell.fill")
                            .font(.caption2)
                            .foregroundStyle(progress >= 0.8 ? AppTheme.orange : .secondary)
                    }
                }
            }

            Divider()

            ProgressView(value: progress)
                .tint(color)

            HStack(spacing: 12) {
                BudgetMetric(
                    title: "Spent",
                    value: DisplayFormat.currency(spent, code: budget.currencyCode)
                )
                BudgetMetric(
                    title: "Budget",
                    value: DisplayFormat.currency(budget.monthlyAmount, code: budget.currencyCode)
                )
            }

            HStack {
                Label("Day \(budget.cycleStartDay)–\(budget.cycleEndDay)", systemImage: "calendar")
                Spacer()
                Text(snapshot.remaining >= 0 ? "Remaining \(DisplayFormat.currency(snapshot.remaining, code: budget.currencyCode))" : "Over \(DisplayFormat.currency(abs(snapshot.remaining), code: budget.currencyCode))")
                    .foregroundStyle(snapshot.remaining >= 0 ? AppTheme.green : AppTheme.red)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(color.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.04), radius: 9, y: 4)
    }
}
'''
    text = replace_required(text, old_progress, new_progress, "budget progress card")

    text = replace_required(
        text,
        r'''            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 7)
    }
}

private struct BudgetMetric: View {''',
        r'''            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(progressColor.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.04), radius: 9, y: 4)
    }
}

private struct BudgetMetric: View {''',
        "budget consumption card styling",
    )
    return text


def update_reports_view(text: str) -> str:
    if 'title: "Carried Forward Balance"' in text:
        return text

    text = replace_required(
        text,
        r'''                .buttonStyle(.plain)
            }
            ForEach(store.loanNetMovements(in: selectedInterval)) { movement in''',
        r'''                .buttonStyle(.plain)
            }
            ReportTotalCard(
                title: "Carried Forward Balance",
                value: carriedForwardBalance,
                currencyCode: store.currencyCode,
                icon: "arrow.uturn.right.circle.fill",
                color: carriedForwardBalance >= 0 ? AppTheme.blue : AppTheme.red,
                secondaryText: "Opening balance before \(selectedInterval.start.formatted(date: .abbreviated, time: .omitted))"
            )
            ForEach(store.loanNetMovements(in: selectedInterval)) { movement in''',
        "carried forward card",
    )

    carried_forward = r'''    private var carriedForwardBalance: Decimal {
        let selectedAccounts = store.accounts.filter {
            !$0.isArchived &&
            $0.currencyCode.uppercased() == store.currencyCode.uppercased()
        }
        let selectedIDs = Set(selectedAccounts.map(\.id))
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

'''
    text = replace_required(
        text,
        "    private var financeSummaryNetBalance: Decimal {",
        carried_forward + "    private var financeSummaryNetBalance: Decimal {",
        "carried forward calculation",
    )
    return text


def update_dashboard_view(text: str) -> str:
    if "private struct NextSolutionHeaderLogo: View" in text:
        return text

    text = replace_required(
        text,
        "import SwiftUI\n",
        "import SwiftUI\nimport UIKit\n",
        "UIKit import",
    )

    logo_view = r'''private struct NextSolutionHeaderLogo: View {
    private var appIcon: UIImage? {
        guard let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
              let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String] else {
            return UIImage(named: "AppIcon")
        }

        for iconName in iconFiles.reversed() {
            if let image = UIImage(named: iconName) {
                return image
            }
        }
        return UIImage(named: "AppIcon")
    }

    var body: some View {
        Group {
            if let appIcon {
                Image(uiImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Image(systemName: "wallet.pass.fill")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.balanceGradient)
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.22), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .accessibilityLabel("Next Solution logo")
    }
}

'''
    text = replace_required(
        text,
        "struct DashboardView: View {",
        logo_view + "struct DashboardView: View {",
        "header logo view",
    )

    text = replace_required(
        text,
        r'''            Image(systemName: "wallet.pass.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(AppTheme.balanceGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))''',
        "            NextSolutionHeaderLogo()",
        "dashboard header icon",
    )
    return text


def update_project(text: str) -> str:
    return (
        text.replace('MARKETING_VERSION: "1.3.36"', 'MARKETING_VERSION: "1.3.37"')
            .replace('CURRENT_PROJECT_VERSION: "44"', 'CURRENT_PROJECT_VERSION: "45"')
    )


def update_workflow(text: str) -> str:
    return (
        text.replace("Next Ledger 1.3.36", "Next Ledger 1.3.37")
            .replace(
                "budget consumption report and batched budget calculations",
                "polished budgets, carried-forward balance and Next Solution header logo",
            )
            .replace("NextLedger-1.3.36", "NextLedger-1.3.37")
    )


update_file(ROOT / "DailyLedger/Views/BudgetSettingsView.swift", update_budget_view)
update_file(ROOT / "DailyLedger/Views/ReportsView.swift", update_reports_view)
update_file(ROOT / "DailyLedger/Views/DashboardView.swift", update_dashboard_view)
update_file(ROOT / "project.yml", update_project)
update_file(ROOT / ".github/workflows/build-tipa.yml", update_workflow)
