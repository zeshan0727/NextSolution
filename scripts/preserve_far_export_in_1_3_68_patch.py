from pathlib import Path

path = Path(__file__).resolve().parent / "fix_fixed_liability_settlement_1_3_68.py"
text = path.read_text(encoding="utf-8")
old = '''# This is the final Swift type in this generated file.
end = len(text)
'''
new = '''# Preserve the Fixed Asset Register snapshot/export types appended by 1.3.67.
end = text.find("private struct FixedAssetRegisterExportView: View {", start)
if end < 0:
    raise RuntimeError("FixedAssetRegisterExportView marker missing while replacing liability editor")
'''
if old not in text:
    raise RuntimeError("1.3.68 editor end anchor not found")
text = text.replace(old, new, 1)
old2 = '''text = text[:start] + new_editor
write(view_path, text)
'''
new2 = '''text = text[:start] + new_editor + "\\n\\n" + text[end:]
write(view_path, text)
'''
if old2 not in text:
    raise RuntimeError("1.3.68 editor replacement anchor not found")
text = text.replace(old2, new2, 1)
path.write_text(text, encoding="utf-8")
print("Preserved FixedAssetRegisterExportView while applying Next Ledger 1.3.68 liability editor.")
