#!/usr/bin/env python3
"""List localizable keys emitted by the compiler (build/**/Zzzip.build/**/*.stringsdata) that lack an Italian translation."""
import json, glob, sys
cat = json.load(open("Zzzip/Resources/Localizable.xcstrings"))["strings"]
keys = set()
for f in glob.glob("build/Build/Intermediates.noindex/Zzzip.build/Debug/Zzzip.build/**/*.stringsdata", recursive=True):
    d = json.load(open(f))
    for table, entries in d.get("tables", {}).items():
        if table == "Localizable":
            for e in entries: keys.add(e["key"])
missing = sorted(k for k in keys if k not in cat or "it" not in cat[k].get("localizations", {}))
json.dump({k: "" for k in missing}, sys.stdout, ensure_ascii=False, indent=1)
