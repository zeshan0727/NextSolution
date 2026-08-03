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
            f"Expected one match in {relative}, found {count}: {old[:240]!r}"
        )
    write(relative, text.replace(old, new, 1))


# Global accounting-period setting. The start day is restricted to 1...28 so
# the configured cycle is valid in every month. A start day of 26 means the
# accounting period runs from the 26th through the 25th of the next month.
settings = "DailyLedger/Views/SettingsView.swift"
replace_once(
    settings,
    '''    @AppStorage("DailyLedgerVisualTheme") private var visualTheme = AppVisualTheme.glass.rawValue
    @State private var showingSMSStatus = true
''',
    '''    @AppStorage("DailyLedgerVisualTheme") private var visualTheme = AppVisualTheme.glass.rawValue
    @AppStorage("AccountingPeriodStartDay") private var accountingPeriodStartDay = 26
    @State private var showingSMSStatus = true
''',
)

replace_once(
    settings,
    '''                } footer: {
                    Text("Reporting Currency controls Home and Reports totals. Account balances remain in each account's own currency.")
                }

                Section {
                    Button {
                        exportingCSV = true
''',
    '''                } footer: {
                    Text("Reporting Currency controls Home and Reports totals. Account balances remain in each account's own currency.")
                }

                Section {
                    Stepper(value: $accountingPeriodStartDay, in: 1...28) {
                        HStack {
                            Text("Period Start Day")
                            Spacer()
                            Text(ordinalDay(accountingPeriodStartDay))
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent(
                        "Default Cycle",
                        value: accountingPeriodLabel
                    )
                } header: {
                    Label("Accounting Period", systemImage: "calendar.badge.clock")
                } footer: {
                    Text("Reports can use this cycle automatically. For example, a start day of 26 creates a period from the 26th through the 25th of the next month.")
                }

                Section {
                    Button {
                        exportingCSV = true
''',
)

replace_once(
    settings,
    '''    private func currencyLabel(_ code: String) -> String {
''',
    '''    private var accountingPeriodLabel: String {
        if accountingPeriodStartDay == 1 {
            return "1st → Month End"
        }
        return "\\(ordinalDay(accountingPeriodStartDay)) → \\(ordinalDay(accountingPeriodStartDay - 1))"
    }

    private func ordinalDay(_ day: Int) -> String {
        let suffix: String
        switch day % 100 {
        case 11, 12, 13:
            suffix = "th"
        default:
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\\(day)\\(suffix)"
    }

    private func currencyLabel(_ code: String) -> String {
''',
)


# Loan Summary Comparison: replace fixed month selection with persistent custom
# From/To dates. The configured accounting period is applied by default, while
# editing either date automatically switches the report to a custom range.
reports = "DailyLedger/Views/ReportsView.swift"
replace_once(
    reports,
    '''private struct LoanSummaryComparisonView: View {
    @EnvironmentObject private var store: LedgerStore
    @State private var selectedMonth = Date()
''',
    '''private struct LoanSummaryComparisonView: View {
    @EnvironmentObject private var store: LedgerStore
    @AppStorage("AccountingPeriodStartDay") private var accountingPeriodStartDay = 26
    @AppStorage("LoanSummaryUseAccountingPeriod") private var useAccountingPeriod = true
    @AppStorage("LoanSummaryCustomStart") private var storedStart = 0.0
    @AppStorage("LoanSummaryCustomEnd") private var storedEnd = 0.0
    @State private var initialized = false
''',
)

replace_once(
    reports,
    '''            Section("Comparison Period") {
                DatePicker(
                    "Selected Month",
                    selection: $selectedMonth,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)

                LabeledContent("Selected", value: monthTitle(currentInterval.start))
                LabeledContent("Previous", value: monthTitle(previousInterval.start))
            }
''',
    '''            Section("Comparison Period") {
                Toggle("Use Accounting Period by Default", isOn: $useAccountingPeriod)
                    .onChange(of: useAccountingPeriod) { enabled in
                        if enabled {
                            applyCurrentAccountingPeriod()
                        }
                    }

                DatePicker("From", selection: startBinding, displayedComponents: .date)
                DatePicker(
                    "To",
                    selection: endBinding,
                    in: Date(timeIntervalSince1970: storedStart)...,
                    displayedComponents: .date
                )

                Button {
                    useAccountingPeriod = true
                    applyCurrentAccountingPeriod()
                } label: {
                    Label(
                        "Apply Current \\(accountingPeriodLabel) Period",
                        systemImage: "calendar.badge.checkmark"
                    )
                }

                LabeledContent("Selected", value: periodTitle(currentInterval))
                LabeledContent("Previous", value: periodTitle(previousInterval))
            }
''',
)

replace_once(
    reports,
    '''                consolidatedRow(
                    title: monthTitle(currentInterval.start),
                    amount: consolidatedNetMovement(in: currentInterval)
                )
                consolidatedRow(
                    title: monthTitle(previousInterval.start),
                    amount: consolidatedNetMovement(in: previousInterval)
                )
''',
    '''                consolidatedRow(
                    title: periodTitle(currentInterval),
                    amount: consolidatedNetMovement(in: currentInterval)
                )
                consolidatedRow(
                    title: periodTitle(previousInterval),
                    amount: consolidatedNetMovement(in: previousInterval)
                )
''',
)

replace_once(
    reports,
    '''        .navigationTitle("Loan Summary Comparison")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var currentInterval: DateInterval {
        Calendar.current.dateInterval(of: .month, for: selectedMonth)!
    }

    private var previousInterval: DateInterval {
        let previousDate = Calendar.current.date(
            byAdding: .month,
            value: -1,
            to: currentInterval.start
        ) ?? currentInterval.start
        return Calendar.current.dateInterval(of: .month, for: previousDate)!
    }
''',
    '''        .navigationTitle("Loan Summary Comparison")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !initialized else { return }
            initialized = true
            if useAccountingPeriod || storedStart <= 0 || storedEnd <= 0 {
                applyCurrentAccountingPeriod()
            }
        }
        .onChange(of: accountingPeriodStartDay) { _ in
            if useAccountingPeriod {
                applyCurrentAccountingPeriod()
            }
        }
    }

    private var currentInterval: DateInterval {
        let calendar = Calendar.current
        let start = calendar.startOfDay(
            for: Date(timeIntervalSince1970: storedStart)
        )
        let selectedEnd = calendar.startOfDay(
            for: Date(timeIntervalSince1970: storedEnd)
        )
        let end = calendar.date(byAdding: .day, value: 1, to: max(start, selectedEnd))!
        return DateInterval(start: start, end: end)
    }

    private var previousInterval: DateInterval {
        let calendar = Calendar.current
        let dayCount = max(
            1,
            calendar.dateComponents(
                [.day],
                from: currentInterval.start,
                to: currentInterval.end
            ).day ?? 1
        )
        let start = calendar.date(
            byAdding: .day,
            value: -dayCount,
            to: currentInterval.start
        ) ?? currentInterval.start.addingTimeInterval(-currentInterval.duration)
        return DateInterval(start: start, end: currentInterval.start)
    }

    private var startBinding: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: storedStart) },
            set: { value in
                let start = Calendar.current.startOfDay(for: value)
                storedStart = start.timeIntervalSince1970
                if storedEnd < storedStart {
                    storedEnd = storedStart
                }
                useAccountingPeriod = false
            }
        )
    }

    private var endBinding: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: storedEnd) },
            set: { value in
                storedEnd = Calendar.current.startOfDay(for: value).timeIntervalSince1970
                useAccountingPeriod = false
            }
        )
    }

    private func applyCurrentAccountingPeriod() {
        let interval = currentAccountingPeriod
        storedStart = interval.start.timeIntervalSince1970
        storedEnd = Calendar.current.date(
            byAdding: .day,
            value: -1,
            to: interval.end
        )!.timeIntervalSince1970
    }

    private var currentAccountingPeriod: DateInterval {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDay = min(max(accountingPeriodStartDay, 1), 28)
        let todayDay = calendar.component(.day, from: today)
        let monthAnchor = todayDay >= startDay
            ? today
            : calendar.date(byAdding: .month, value: -1, to: today) ?? today
        let components = calendar.dateComponents([.year, .month], from: monthAnchor)
        let start = calendar.date(from: DateComponents(
            year: components.year,
            month: components.month,
            day: startDay
        )) ?? today
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return DateInterval(start: start, end: end)
    }

    private var accountingPeriodLabel: String {
        if accountingPeriodStartDay == 1 {
            return "1st–Month End"
        }
        return "\\(ordinalDay(accountingPeriodStartDay))–\\(ordinalDay(accountingPeriodStartDay - 1))"
    }
''',
)

replace_once(
    reports,
    '''    private func monthTitle(_ date: Date) -> String {
        Self.monthFormatter.string(from: date)
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()
''',
    '''    private func periodTitle(_ interval: DateInterval) -> String {
        let end = Calendar.current.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        return "\\(Self.periodFormatter.string(from: interval.start)) – \\(Self.periodFormatter.string(from: end))"
    }

    private func ordinalDay(_ day: Int) -> String {
        let suffix: String
        switch day % 100 {
        case 11, 12, 13:
            suffix = "th"
        default:
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\\(day)\\(suffix)"
    }

    private static let periodFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy"
        return formatter
    }()
''',
)

write(reports, read(reports))
print("Added global accounting period settings and custom-date Loan Summary Comparison periods.")
