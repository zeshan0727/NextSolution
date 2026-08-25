#!/usr/bin/env python3
import csv
import io
import sys
import urllib.request
from collections import defaultdict
from pathlib import Path

SOURCES = [
    "https://www.vpngate.net/api/iphone/",
    "http://121.141.108.75:12433/api/iphone/",
    "http://211.196.188.156:65104/api/iphone/",
    "http://183.99.115.118:31489/api/iphone/",
]


def fetch_text(url: str):
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "NextMultiBrowser-CI/1.0.5",
            "Accept": "text/plain,text/csv,*/*",
        },
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        data = response.read()
    return data.decode("utf-8", errors="replace")


def select_rows(text: str):
    rows = []
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("*"):
            continue
        try:
            fields = next(csv.reader([line]))
        except Exception:
            continue
        if len(fields) < 15 or not fields[14].strip():
            continue
        try:
            score = int(fields[2] or 0)
            speed = int(fields[4] or 0)
        except ValueError:
            score, speed = 0, 0
        country_key = (fields[6] or fields[5] or "ZZ").upper()
        rows.append((country_key, score, speed, fields))

    grouped = defaultdict(list)
    for item in rows:
        grouped[item[0]].append(item)

    selected = []
    for country in sorted(grouped):
        best = sorted(grouped[country], key=lambda item: (item[1], item[2]), reverse=True)[:8]
        selected.extend(item[3] for item in best)
    return selected


def main():
    if len(sys.argv) != 2:
        print("usage: fetch-vpngate-seed.py OUTPUT", file=sys.stderr)
        return 2

    output = Path(sys.argv[1])
    output.parent.mkdir(parents=True, exist_ok=True)

    text = None
    used = None
    for source in SOURCES:
        try:
            candidate = fetch_text(source)
            rows = select_rows(candidate)
            if rows:
                text = candidate
                used = source
                break
        except Exception as exc:
            print(f"VPN Gate seed source failed: {source}: {exc}")

    if text is None:
        print("No VPN Gate seed source available; continuing without bundled seed.")
        output.write_text("", encoding="utf-8")
        return 0

    rows = select_rows(text)
    with output.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerows(rows)

    print(f"Bundled {len(rows)} VPN Gate servers from {used}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
