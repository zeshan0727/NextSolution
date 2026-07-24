#!/bin/bash
set -euo pipefail

python3 - <<'PY'
from pathlib import Path

source_path = Path('NextMediaApp/build146.sh')
source = source_path.read_text()

about_edit = "replace_once(settings, 'Text(\"1.4.5\")', 'Text(\"1.4.6\")', 'About version')"
about_update = '''settings_text = settings.read_text()
settings_text = "\\n".join(
    '                        Text("1.4.6").foregroundColor(.secondary)'
    if 'Text("1.4.' in line and 'foregroundColor(.secondary)' in line
    else line
    for line in settings_text.splitlines()
) + "\\n"
settings.write_text(settings_text)'''
if about_edit not in source:
    raise SystemExit('Could not locate About version edit')
source = source.replace(about_edit, about_update, 1)

old_project_edit = '''project_text = project_text.replace('MARKETING_VERSION: "1.4.5"', 'MARKETING_VERSION: "1.4.6"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "11"', 'CURRENT_PROJECT_VERSION: "12"')'''
new_project_edit = '''project_text = "\\n".join(
    '    MARKETING_VERSION: "1.4.6"'
    if line.strip().startswith('MARKETING_VERSION:')
    else '    CURRENT_PROJECT_VERSION: "12"'
    if line.strip().startswith('CURRENT_PROJECT_VERSION:')
    else line
    for line in project_text.splitlines()
) + "\\n"'''
if old_project_edit not in source:
    raise SystemExit('Could not locate project version edit')
source = source.replace(old_project_edit, new_project_edit, 1)

Path('/tmp/NextMedia-build146-fixed.sh').write_text(source)
PY

exec bash /tmp/NextMedia-build146-fixed.sh
