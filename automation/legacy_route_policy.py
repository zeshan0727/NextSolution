#!/usr/bin/env python3
"""Keep legacy root HTML publisher targets out of search indexes.

Root ``*.html`` files remain editable publisher targets for compatibility with
existing automation. Clean public routes live at ``/<slug>/``. The clean-URL
workflow calls ``prepare`` before generating public copies, then ``finalize``
to add a marked noindex directive only to the legacy root duplicates.
"""

from __future__ import annotations

import argparse
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
START = "<!-- legacy-route-noindex:start -->"
END = "<!-- legacy-route-noindex:end -->"
BLOCK = (
    f"  {START}\n"
    '  <meta name="robots" content="noindex,follow,max-image-preview:large">\n'
    f"  {END}\n"
)
BLOCK_RE = re.compile(
    rf"\s*{re.escape(START)}.*?{re.escape(END)}\s*",
    re.IGNORECASE | re.DOTALL,
)


def legacy_pages(root: Path = ROOT) -> list[Path]:
    return sorted(
        path
        for path in root.glob("*.html")
        if path.name.lower() not in {"index.html", "404.html"}
    )


def prepare_text(text: str) -> str:
    return BLOCK_RE.sub("\n", text)


def finalize_text(text: str) -> str:
    text = prepare_text(text)
    if "</head>" not in text.lower():
        raise ValueError("legacy HTML page is missing </head>")
    return re.sub(r"</head>", BLOCK + "</head>", text, count=1, flags=re.IGNORECASE)


def apply(mode: str, root: Path = ROOT) -> int:
    changed = 0
    for path in legacy_pages(root):
        old = path.read_text(encoding="utf-8")
        new = prepare_text(old) if mode == "prepare" else finalize_text(old)
        if new != old:
            path.write_text(new, encoding="utf-8")
            changed += 1
    return changed


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("prepare", "finalize"))
    parser.add_argument("--repository-root", type=Path, default=ROOT)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    changed = apply(args.mode, args.repository_root)
    print(f"legacy-route-policy {args.mode}: {changed} file(s) changed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
