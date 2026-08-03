from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
target = ROOT / "scripts/add_payment_receivable_payable_automation.py"
text = target.read_text(encoding="utf-8")

old = '''text = read(accounts)
old_nature = "nature == .unassigned ? nil : nature"
count = text.count(old_nature)
if count != 2:
    raise RuntimeError(f"Expected two account-save nature expressions, found {count}")
write(accounts, text.replace(old_nature, "resolvedNature"))
'''

new = '''replace_once(
    accounts,
    "account.nature = nature == .unassigned ? nil : nature",
    "account.nature = resolvedNature",
)
replace_once(
    accounts,
    "nature: nature == .unassigned ? nil : nature,",
    "nature: resolvedNature,",
)
'''

count = text.count(old)
if count != 1:
    raise RuntimeError(f"Expected one broad nature-replacement block, found {count}")

target.write_text(text.replace(old, new, 1), encoding="utf-8")
print("Fixed payment automation account-nature patch targeting.")
