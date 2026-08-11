from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "DailyLedger/Views/FixedAccountingRegistersView.swift"
text = path.read_text(encoding="utf-8")

old_settlement = '''        Section("Ledger Settlement") {
            valueRow("Original Principal", snapshot.originalPrincipal)
            valueRow("Additional Increases", snapshot.increases)
            valueRow("Repaid / Settled", snapshot.repayments, incoming: true)
            valueRow("Outstanding Liability", snapshot.outstanding, emphasized: true)
            LabeledContent("Status", value: snapshot.status.title)
                .foregroundStyle(snapshot.status == .settled ? AppTheme.green : AppTheme.orange)
            ProgressView(value: snapshot.repaymentProgress)
                .tint(snapshot.status == .settled ? AppTheme.green : AppTheme.blue)
            if let date = snapshot.settledDate, snapshot.status == .settled {
                LabeledContent(
                    "Settled Date",
                    value: date.formatted(date: .long, time: .omitted)
                )
            }
        } footer: {
            Text("Status is automatic for linked liabilities. Bank → Liability reduces the outstanding amount. Liability → Bank increases it. Internal Liability → Liability transfers do not count as repayments.")
        }
'''
new_settlement = '''        Section {
            valueRow("Original Principal", snapshot.originalPrincipal)
            valueRow("Additional Increases", snapshot.increases)
            valueRow("Repaid / Settled", snapshot.repayments, incoming: true)
            valueRow("Outstanding Liability", snapshot.outstanding, emphasized: true)
            LabeledContent("Status", value: snapshot.status.title)
                .foregroundStyle(snapshot.status == .settled ? AppTheme.green : AppTheme.orange)
            ProgressView(value: snapshot.repaymentProgress)
                .tint(snapshot.status == .settled ? AppTheme.green : AppTheme.blue)
            if let date = snapshot.settledDate, snapshot.status == .settled {
                LabeledContent(
                    "Settled Date",
                    value: date.formatted(date: .long, time: .omitted)
                )
            }
        } header: {
            Text("Ledger Settlement")
        } footer: {
            Text("Status is automatic for linked liabilities. Bank → Liability reduces the outstanding amount. Liability → Bank increases it. Internal Liability → Liability transfers do not count as repayments.")
        }
'''
if text.count(old_settlement) != 1:
    raise RuntimeError(f"Ledger Settlement Section anchor count: {text.count(old_settlement)}")
text = text.replace(old_settlement, new_settlement, 1)

old_status = '''        Section("Status") {
            Picker("Status", selection: $status) {
                ForEach(FixedLiabilityStatus.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            if status == .settled {
                DatePicker("Settled Date", selection: settledDate, displayedComponents: .date)
            }
        } footer: {
            Text("Link a liability account to calculate repayment and settlement automatically from ledger transactions.")
        }
'''
new_status = '''        Section {
            Picker("Status", selection: $status) {
                ForEach(FixedLiabilityStatus.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            if status == .settled {
                DatePicker("Settled Date", selection: settledDate, displayedComponents: .date)
            }
        } header: {
            Text("Status")
        } footer: {
            Text("Link a liability account to calculate repayment and settlement automatically from ledger transactions.")
        }
'''
if text.count(old_status) != 1:
    raise RuntimeError(f"Manual Status Section anchor count: {text.count(old_status)}")
text = text.replace(old_status, new_status, 1)

path.write_text(text, encoding="utf-8")
print("Fixed Next Ledger 1.3.68 Fixed Liability editor Section syntax for iOS 16 / Swift 5.7.")
