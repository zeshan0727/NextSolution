#!/usr/bin/env python3
from pathlib import Path
from email.utils import formatdate
import re, sys, time

PACKAGE = 'com.nextsolution.internetlosthaptic'
packages_path = Path('Packages')
release_path = Path('Release')
new_stanzas = Path(sys.argv[1]).read_text(encoding='utf-8').strip()
if not new_stanzas:
    raise SystemExit('generated stanza file is empty')

existing = packages_path.read_text(encoding='utf-8') if packages_path.exists() else ''
blocks = [b.strip() for b in re.split(r'\n\s*\n', existing) if b.strip()]
blocks = [b for b in blocks if f'Package: {PACKAGE}' not in b.splitlines()]
new_blocks = [b.strip() for b in re.split(r'\n\s*\n', new_stanzas) if b.strip()]
if len(new_blocks) != 2:
    raise SystemExit(f'expected exactly two generated package stanzas, got {len(new_blocks)}')
for block in new_blocks:
    if f'Package: {PACKAGE}' not in block:
        raise SystemExit('generated stanza has unexpected package id')
    if 'Filename: ./debfiles/' not in block:
        raise SystemExit('generated stanza does not use live relative debfiles path')
blocks.extend(new_blocks)
packages_path.write_text('\n\n'.join(blocks) + '\n', encoding='utf-8')

release = release_path.read_text(encoding='utf-8')
m = re.search(r'^Version:\s*(\d+)\.(\d+)\.(\d+)\s*$', release, flags=re.M)
if not m:
    raise SystemExit('Release Version not found')
major, minor, patch = map(int, m.groups())
release = re.sub(r'^Version:.*$', f'Version: {major}.{minor}.{patch + 1}', release, count=1, flags=re.M)
release = re.sub(r'^Date:.*$', f'Date: {formatdate(time.time(), usegmt=True)}', release, count=1, flags=re.M)
release_path.write_text(release, encoding='utf-8')
print(f'Published two {PACKAGE} stanzas; Release -> {major}.{minor}.{patch + 1}')
