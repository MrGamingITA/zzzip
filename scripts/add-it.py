#!/usr/bin/env python3
"""Merge English→Italian pairs from a JSON file (arg 1) into Localizable.xcstrings (or arg 2)."""
import json, sys
pairs = json.load(open(sys.argv[1]))
path = sys.argv[2] if len(sys.argv) > 2 else "Zzzip/Resources/Localizable.xcstrings"
cat = json.load(open(path))
for k, v in pairs.items():
    cat["strings"].setdefault(k, {})["localizations"] = {"it": {"stringUnit": {"state": "translated", "value": v}}}
json.dump(cat, open(path, "w"), ensure_ascii=False, indent=2, sort_keys=True)
print(f"{len(pairs)} keys merged, {len(cat['strings'])} total")
