#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).with_name('patch_v142.py')
text = path.read_text()
start = text.find('# File sharing also restores and retries once when Render lost its connector database.')
end = text.find('project = ROOT / "project.yml"', start)
if start == -1 or end == -1:
    raise SystemExit('Could not locate optional File Sharing recovery patch')
text = text[:start] + '# Gmail file sharing uses the restored connector after the foreground health check.\n' + text[end:]
path.write_text(text)
print('Removed optional File Sharing source-pattern patch from v1.3.12 build.')
