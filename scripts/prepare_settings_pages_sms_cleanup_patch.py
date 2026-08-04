from pathlib import Path

path = Path(__file__).resolve().parent / "add_settings_pages_custom_sms_and_log_cleanup.py"
text = path.read_text(encoding="utf-8")
old = '''replace_once(
    console,
    ''' + "'''" + '''    @State private var snapshot = SMSImportConsoleSnapshot()\n    @State private var notice: String?\n''' + "'''" + ''',
    ''' + "'''" + '''    @State private var snapshot = SMSImportConsoleSnapshot()\n    @State private var notice: String?\n    @State private var loadingConfiguration = true\n''' + "'''" + ''',
)
'''
new = '''replace_once(
    console,
    ''' + "'''" + '''    @State private var notice: String?\n''' + "'''" + ''',
    ''' + "'''" + '''    @State private var notice: String?\n    @State private var loadingConfiguration = true\n''' + "'''" + ''',
)
'''
count = text.count(old)
if count != 1:
    raise RuntimeError(f"Expected one SMS state-anchor patch, found {count}")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("Prepared the SMS console patch with a diagnostics-independent state anchor.")
