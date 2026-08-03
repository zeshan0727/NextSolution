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
                        "Apply Current \(accountingPeriodLabel) Period",
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
        let start = calendar.startOfDay(for: Date(timeIntervalSince1970: storedStart))
        let selectedEnd = calendar.startOfDay(for: Date(timeIntervalSince1970: storedEnd))
        let inclusiveEnd = max(start, selectedEnd)
        let end = calendar.date(byAdding: .day, value: 1, to: inclusiveEnd)!
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
        return "\(ordinalDay(accountingPeriodStartDay))–\(ordinalDay(accountingPeriodStartDay - 1))"
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
        return "\(Self.periodFormatter.string(from: interval.start)) – \(Self.periodFormatter.string(from: end))"
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
        return "\(day)\(suffix)"
    }

    private static let periodFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy"
        return formatter
    }()
''',
)

print("Added custom From/To dates and accounting-period defaults to Loan Summary Comparison.")
