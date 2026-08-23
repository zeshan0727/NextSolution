#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SKIP_DIRS = {'.git', 'node_modules', '.build', 'build', 'DerivedData'}
SKIP_FILES = {
    ROOT / 'automation' / 'replace_personal_branding.py',
    ROOT / 'assets' / 'site-branding.js',
}

NAME_PATTERNS = [
    re.compile(r'\bMuhammad\s+Zeeshan\s+Barvi\b', re.I),
    re.compile(r'\bZeeshan\s+Barvi\b', re.I),
    re.compile(r'\bZeeshan\b'),
]
TOPLINE_PATTERN = re.compile(
    r'\s*<span\s+class=["\']topline-status["\'][^>]*>\s*<i[^>]*></i>\s*Direct\s+links?\s+to\s+original\s+sources?\s*</span>',
    re.I,
)


def looks_text(path: Path) -> bool:
    try:
        data = path.read_bytes()
    except OSError:
        return False
    if len(data) > 5_000_000 or b'\x00' in data:
        return False
    try:
        data.decode('utf-8')
    except UnicodeDecodeError:
        return False
    return True


def main() -> int:
    changed = []
    replacements = 0

    for path in ROOT.rglob('*'):
        if not path.is_file() or path in SKIP_FILES:
            continue
        if any(part in SKIP_DIRS for part in path.parts):
            continue
        if not looks_text(path):
            continue

        text = path.read_text(encoding='utf-8')
        original = text

        text, n = TOPLINE_PATTERN.subn('', text)
        replacements += n

        for pattern in NAME_PATTERNS:
            text, n = pattern.subn('NextSolution', text)
            replacements += n

        if text != original:
            path.write_text(text, encoding='utf-8')
            changed.append(str(path.relative_to(ROOT)))

    print(f'changed_files={len(changed)} replacements={replacements}')
    for item in changed:
        print(item)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
