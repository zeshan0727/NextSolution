from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
VIEWS = ROOT / "DailyLedger" / "Views"


def read(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def write(relative: str, content: str) -> None:
    (ROOT / relative).write_text(content, encoding="utf-8")


def replace_once(relative: str, old: str, new: str) -> None:
    text = read(relative)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"Expected one match in {relative}, found {count}: {old[:160]!r}")
    write(relative, text.replace(old, new, 1))


# A single reusable modifier keeps swipe behavior identical on every transaction
# list. For a trailing swipe, actions are declared Delete, Refund, Edit so the
# visible left-to-right order is Edit > Refund > Delete.
write(
    "DailyLedger/Views/TransactionSwipeActions.swift",
    r'''import SwiftUI

private struct TransactionSwipeActionsModifier: ViewModifier {
    @EnvironmentObject private var store: LedgerStore
    let transaction: LedgerTransaction

    @State private var editingTransaction: LedgerTransaction?
    @State private var refundingTransaction: LedgerTransaction?

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    store.delete(transaction)
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                if canRefund {
                    Button {
                        refundingTransaction = transaction
                    } label: {
                        Label("Refund", systemImage: "arrow.uturn.backward.circle")
                    }
                    .tint(AppTheme.green)
                }

                Button {
                    editingTransaction = transaction
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(AppTheme.blue)
            }
            .sheet(item: $editingTransaction) { item in
                if item.type == .transfer {
                    TransferView(transaction: item)
                        .environmentObject(store)
                } else {
                    AddTransactionView(transaction: item)
                        .environmentObject(store)
                }
            }
            .sheet(item: $refundingTransaction) { item in
                RefundTransactionView(transaction: item)
                    .environmentObject(store)
            }
    }

    private var canRefund: Bool {
        transaction.type != .transfer &&
            transaction.refundOfTransactionID == nil &&
            store.refundableAmount(for: transaction) > 0
    }
}

extension View {
    func transactionSwipeActions(_ transaction: LedgerTransaction) -> some View {
        modifier(TransactionSwipeActionsModifier(transaction: transaction))
    }
}
''',
)


# Replace every existing delete-only transaction swipe block, including the main
# Transactions screen and all report/account/category lists generated earlier.
delete_only_swipe = re.compile(
    r'(?P<indent>^[ \t]*)\.swipeActions\(edge: \.trailing, allowsFullSwipe: (?:true|false)\) \{\n'
    r'(?P=indent)    Button\(role: \.destructive\) \{\n'
    r'(?P=indent)        store\.delete\((?P<item>transaction|item)\)\n'
    r'(?P=indent)    \} label: \{\n'
    r'(?P=indent)        Label\("Delete", systemImage: "trash"\)\n'
    r'(?P=indent)    \}\n'
    r'(?P=indent)\}',
    re.MULTILINE,
)

replacement_count = 0
modified_files: list[str] = []
for path in sorted(VIEWS.glob("*.swift")):
    if path.name == "TransactionSwipeActions.swift":
        continue
    text = path.read_text(encoding="utf-8")

    def replacement(match: re.Match[str]) -> str:
        nonlocal_item = match.group("item")
        return f'{match.group("indent")}.transactionSwipeActions({nonlocal_item})'

    updated, count = delete_only_swipe.subn(replacement, text)
    if count:
        path.write_text(updated, encoding="utf-8")
        replacement_count += count
        modified_files.append(path.name)

if replacement_count < 8:
    raise RuntimeError(
        f"Expected at least 8 delete-only transaction swipe blocks, replaced {replacement_count}"
    )


# Dashboard recent rows previously had only a delete context menu because they are
# custom cards. Attach the same swipe component while retaining that menu.
replace_once(
    "DailyLedger/Views/DashboardView.swift",
    """                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                store.delete(transaction)
                            } label: {
                                Label("Delete Transaction", systemImage: "trash")
                            }
                        }
""",
    """                        .buttonStyle(.plain)
                        .transactionSwipeActions(transaction)
                        .contextMenu {
                            Button(role: .destructive) {
                                store.delete(transaction)
                            } label: {
                                Label("Delete Transaction", systemImage: "trash")
                            }
                        }
""",
)

print(
    "Added Edit > Refund > Delete swipe actions to "
    f"{replacement_count + 1} transaction surfaces: "
    + ", ".join(modified_files + ["DashboardView.swift"])
)
