"""Checks the App Store texts in listing.md against App Store Connect's character limits."""
import pathlib
import re

text = pathlib.Path(__file__).with_name("listing.md").read_text(encoding="utf-8")
ok = True
for match in re.finditer(r"\*\*([^*\n]+?)\*\* \[(\d+)\]\n(.*?)(?=\n\*\*|\n---|\Z)", text, re.S):
    label, limit, value = match.group(1), int(match.group(2)), match.group(3).strip()
    status = "ok" if len(value) <= limit else "TOO LONG"
    ok &= len(value) <= limit
    print(f"{status:8} {len(value):4}/{limit:<4} {label}")
raise SystemExit(0 if ok else 1)
