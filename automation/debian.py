"""Small, dependency-free helpers for Debian repository metadata."""

from __future__ import annotations

from functools import cmp_to_key
import re
from typing import Iterable


FIELD_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9-]*$")


def parse_control(text: str) -> list[dict[str, str]]:
    """Parse RFC822/Deb822 paragraphs used by APT Packages indexes.

    Malformed paragraphs are ignored instead of aborting the whole source. This
    scanner only consumes metadata and never downloads package binaries.
    """

    records: list[dict[str, str]] = []
    fields: dict[str, str] = {}
    current: str | None = None

    def finish() -> None:
        nonlocal fields, current
        if fields:
            records.append(fields)
        fields = {}
        current = None

    for raw_line in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        if not raw_line:
            finish()
            continue
        if raw_line[0] in " \t":
            if current is not None:
                continuation = raw_line[1:]
                fields[current] += "\n" + ("" if continuation == "." else continuation)
            continue
        if ":" not in raw_line:
            current = None
            continue
        key, value = raw_line.split(":", 1)
        if not FIELD_RE.fullmatch(key):
            current = None
            continue
        current = key.lower()
        fields[current] = value.lstrip()
    finish()
    return records


def _split_version(version: str) -> tuple[int, str, str]:
    epoch = 0
    remainder = version
    if ":" in remainder:
        possible_epoch, remainder = remainder.split(":", 1)
        if possible_epoch.isdigit():
            epoch = int(possible_epoch)
        else:
            remainder = version
    if "-" in remainder:
        upstream, revision = remainder.rsplit("-", 1)
    else:
        upstream, revision = remainder, "0"
    return epoch, upstream, revision


def _char_order(char: str) -> int:
    if char == "~":
        return -1
    if not char:
        return 0
    if char.isalpha():
        return ord(char)
    return ord(char) + 256


def _compare_part(left: str, right: str) -> int:
    li = ri = 0
    while li < len(left) or ri < len(right):
        while (li < len(left) and not left[li].isdigit()) or (
            ri < len(right) and not right[ri].isdigit()
        ):
            lc = left[li] if li < len(left) and not left[li].isdigit() else ""
            rc = right[ri] if ri < len(right) and not right[ri].isdigit() else ""
            lo, ro = _char_order(lc), _char_order(rc)
            if lo != ro:
                return -1 if lo < ro else 1
            if lc:
                li += 1
            if rc:
                ri += 1

        left_start = li
        right_start = ri
        while left_start < len(left) and left[left_start] == "0":
            left_start += 1
        while right_start < len(right) and right[right_start] == "0":
            right_start += 1
        left_end = left_start
        right_end = right_start
        while left_end < len(left) and left[left_end].isdigit():
            left_end += 1
        while right_end < len(right) and right[right_end].isdigit():
            right_end += 1
        left_digits = left[left_start:left_end]
        right_digits = right[right_start:right_end]
        if len(left_digits) != len(right_digits):
            return -1 if len(left_digits) < len(right_digits) else 1
        if left_digits != right_digits:
            return -1 if left_digits < right_digits else 1

        while li < len(left) and left[li].isdigit():
            li += 1
        while ri < len(right) and right[ri].isdigit():
            ri += 1
    return 0


def compare_versions(left: str, right: str) -> int:
    """Compare Debian versions using epoch, upstream, and revision ordering."""

    left_epoch, left_upstream, left_revision = _split_version(left)
    right_epoch, right_upstream, right_revision = _split_version(right)
    if left_epoch != right_epoch:
        return -1 if left_epoch < right_epoch else 1
    upstream_result = _compare_part(left_upstream, right_upstream)
    if upstream_result:
        return upstream_result
    return _compare_part(left_revision, right_revision)


def newest(records: Iterable[dict[str, object]]) -> dict[str, object]:
    """Return the record with the newest ``version`` field."""

    values = list(records)
    if not values:
        raise ValueError("newest() requires at least one record")
    return sorted(
        values,
        key=cmp_to_key(
            lambda left, right: compare_versions(
                str(left.get("version", "")), str(right.get("version", ""))
            )
        ),
    )[-1]
