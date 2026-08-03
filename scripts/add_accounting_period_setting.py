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


settings = "DailyLedger/Views/SettingsView.swift"

replace_once(
    settings,
    '''    @AppStorage("DailyLedgerVisualTheme") private var visualTheme = AppVisualTheme.glass.rawValue

    private let currencies = ["QAR", "USD", "GBP", "EUR", "AED", "SAR", "PKR", "INR"]
''',
    '''    @AppStorage("DailyLedgerVisualTheme") private var visualTheme = AppVisualTheme.glass.rawValue
    @AppStorage("AccountingPeriodStartDay") private var accountingPeriodStartDay = 26

    private let currencies = ["QAR", "USD", "GBP", "EUR", "AED", "SAR", "PKR", "INR"]
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
                    LabeledContent("Default Cycle", value: accountingPeriodLabel)
                } header: {
                    Label("Accounting Period", systemImage: "calendar.badge.clock")
                } footer: {
                    Text("Reports can use this cycle automatically. A start day of 26 creates a period from the 26th through the 25th of the next month.")
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
        return "\(ordinalDay(accountingPeriodStartDay)) → \(ordinalDay(accountingPeriodStartDay - 1))"
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

    private func currencyLabel(_ code: String) -> String {
''',
)

print("Added global Accounting Period setting with a default 26th-to-25th cycle.")
