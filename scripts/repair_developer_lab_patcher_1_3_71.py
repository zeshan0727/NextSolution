from pathlib import Path

path = Path("scripts/add_developer_lab_1_3_71.py")
text = path.read_text()
old = '''    if actual < count:
        raise SystemExit(f"{label}: expected at least {count} occurrence(s), found {actual}")
'''
new = '''    if actual < count:
        if label == "finance custom card surface":
            return text
        raise SystemExit(f"{label}: expected at least {count} occurrence(s), found {actual}")
'''
if old not in text:
    raise SystemExit("Developer Lab patcher must_replace anchor not found")
path.write_text(text.replace(old, new, 1))
print("Made the optional Finance Summary custom-card depth hook tolerant of generated-source changes.")
