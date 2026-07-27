#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).resolve().parents[1] / "DailyLedger/Services/LedgerStore.swift"
text = path.read_text(encoding="utf-8")
old = "return (defaults + used).compactMap { item in"
new = "return (defaults + Array(used)).compactMap { item in"
if old in text:
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print("Fixed cached category collection conversion.")
elif new in text:
    print("Cached category collection conversion already fixed.")
else:
    raise RuntimeError("Expected cached category block was not found.")
