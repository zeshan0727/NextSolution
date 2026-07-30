#!/usr/bin/env python3
from pathlib import Path
import sys

WORKSPACE = Path(__file__).resolve().parent / "NextPDF" / "RobustPDFWorkspaceView.swift"


def main() -> int:
    try:
        text = WORKSPACE.read_text(encoding="utf-8")
        old = '''                    .frame(
                        width: floatingToolsWidth(for: geometry.size.width),
                        maxHeight: max(240, geometry.size.height - 24)
                    )
'''
        new = '''                    .frame(width: floatingToolsWidth(for: geometry.size.width))
                    .frame(maxHeight: max(240, geometry.size.height - 24))
'''
        count = text.count(old)
        if count != 1:
            raise RuntimeError(f"floating palette frame: expected one match, found {count}")
        WORKSPACE.write_text(text.replace(old, new, 1), encoding="utf-8")
        print("Normalized floating palette SwiftUI frame overload")
        return 0
    except Exception as exc:
        print(f"Floating tools compile fix failed: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
