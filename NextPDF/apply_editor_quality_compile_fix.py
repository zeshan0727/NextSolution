#!/usr/bin/env python3
from pathlib import Path
import sys

MODEL = Path(__file__).resolve().parent / "NextPDF" / "PDFEditorModel.swift"


def main() -> int:
    try:
        text = MODEL.read_text(encoding="utf-8")
        old = '''            let targetHeight = max(
                draft.bounds.height + 2,
                measured.height + 3,
                font.lineHeight + 2
            )
'''
        new = '''            let targetHeight = max(
                draft.bounds.height + 2,
                max(measured.height + 3, font.lineHeight + 2)
            )
'''
        count = text.count(old)
        if count != 1:
            raise RuntimeError(f"target height normalization: expected one match, found {count}")
        MODEL.write_text(text.replace(old, new, 1), encoding="utf-8")
        print("Normalized NextPDF editor quality Swift")
        return 0
    except Exception as exc:
        print(f"Editor quality compile normalization failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
