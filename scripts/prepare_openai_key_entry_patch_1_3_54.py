from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / "scripts/fix_openai_api_key_entry_1_3_54.py"
text = path.read_text(encoding="utf-8")

if "import re\n" not in text:
    text = text.replace("from pathlib import Path\n", "from pathlib import Path\nimport re\n", 1)

old = '''old = \'\'\'                    SecureField(openAIConnected ? "Enter replacement API key" : "OpenAI API key", text: $openAIAPIKey)\\n                        .textInputAutocapitalization(.never).autocorrectionDisabled()\\n\'\'\'\nnew = '''
if old not in text:
    raise RuntimeError("Could not find strict OpenAI key-field patch block")
text = text.replace(old, '''pattern = r\'(?ms)^\\s*SecureField\\([^\\n]*text:\\s*\\$openAIAPIKey\\)[^\\n]*\\n(?:\\s*\\.[^\\n]*\\n){0,6}\'\nnew = ''', 1)
text = text.replace("replace_once(settings, old, new)\n", '''settings_text = read(settings)\nsettings_text, field_count = re.subn(pattern, new, settings_text, count=1)\nif field_count != 1:\n    raise RuntimeError(f"Expected one generated OpenAI key field, replaced {field_count}")\nwrite(settings, settings_text)\n''', 1)

path.write_text(text, encoding="utf-8")
print("Prepared flexible generated OpenAI API-key field anchor.")
