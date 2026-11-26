#!/usr/bin/env python3
"""Checks the generated App Intents metadata before signing.

1. The system's own parser (LinkMetadata's LNBundleMetadata, via macOS/scripts/tools/ln_validate.swift) must load it
   and see every intent. There must be no entities, queries or enums: an ad-hoc signed extension can't decode
   their values (ARCHITECTURE §5).
   It must also have read every collection size (Edit Widget's fixed number of city rows).
2. Every intent parameter must exist in the compiled Swift type: @Parameter properties are stored as
   "_<name>" fields, whose names are in the binary's reflection strings (__swift5_reflstr).
3. Every display text (titles, descriptions) of 16+ UTF-8 bytes must appear in the binary: Swift keeps such
   string literals as plain bytes, so this catches a SPEC text that no longer matches Intents.swift.
   (Shorter literals are encoded inside instructions and cannot be checked this way.)

usage: verify_metadata.py <path/to/Widget.appex> <ln_validate tool>
"""
import json
import os
import re
import subprocess
import sys


def fail(msg):
    sys.exit(f"error: App Intents metadata check failed: {msg}")


def main():
    appex, validator = sys.argv[1:3]
    md_path = os.path.join(appex, "Contents/Resources/Metadata.appintents/extract.actionsdata")
    data = json.load(open(md_path))

    result = subprocess.run([validator, appex, "full"], capture_output=True, text=True)
    out = result.stdout
    if "PARSE: UNAVAILABLE" in out:
        print("warning: LinkMetadata parser unavailable on this macOS; skipped parse check")
        out = None
    if out is None:
        pass
    elif "PARSE: OK" not in out:
        fail("LNBundleMetadata could not parse it:\n" + out[:2000])
    for ident in data["actions"] if out else []:
        if f"identifier: {ident}," not in out:
            fail(f"parser did not load intent {ident}")
    # Fixed numbers of rows (the World Clock Cities): the parser must have read every size, and each size must
    # name a widget family LinkMetadata knows (it accepts any string; the Edit Widget UI looks these names up).
    m = re.search(r"^WIDGET FAMILIES: (.*)$", out or "", re.M)
    families = set(m.group(1).split()) if m else None
    if out and not families:
        print("warning: couldn't read LinkMetadata's widget family names; skipped that check")
    for ident, action in data["actions"].items() if out else []:
        for p in action["parameters"]:
            tsm = p.get("typeSpecificMetadata") or []
            for key, value in zip(tsm[0::2], tsm[1::2]):
                if key != "LNValueTypeMetadataKeyCollectionSizes":
                    continue
                for family, size in value["collectionSizes"]["sizes"].items():
                    if families and family not in families:
                        fail(f"{ident}.{p['name']} has a size for {family!r}, which isn't a widget family "
                             f"LinkMetadata knows ({' '.join(sorted(families))})")
                    pattern = (rf'{re.escape(family)} = \\*"?<LNIntentCollectionSize: 0x[0-9a-f]+, '
                               rf'min: {size["min"]} max: {size["max"]}>')
                    if not re.search(pattern, out):
                        fail(f"parser did not read {ident}.{p['name']} size {family} = {size}")
    for key in ("entities", "queries", "enums"):
        if data.get(key):
            fail(f"the metadata has {key}; an ad-hoc signed extension can't decode their values (ARCHITECTURE §5)")

    binary = os.path.join(appex, "Contents/MacOS", os.path.basename(appex)[: -len(".appex")])
    strings = set(subprocess.run(["strings", "-a", "-n", "3", binary], capture_output=True, text=True).stdout.split())
    for ident, action in data["actions"].items():
        for p in action["parameters"]:
            if "_" + p["name"] not in strings:
                fail(f"{ident}.{p['name']} is in the metadata but not a property of the Swift type")

    blob = open(binary, "rb").read()
    checked = 0
    for t in sorted(set(display_texts(data))):
        if len(t.encode()) < 16:
            continue
        checked += 1
        if t.encode() not in blob:
            fail(f'display text "{t}" is in the metadata but not in the Swift code — '
                 f"make macOS/scripts/gen_appintents_metadata.py SPEC match Shared/Widget/Intents.swift")

    params = sum(len(a["parameters"]) for a in data["actions"].values())
    print(f"metadata OK: {len(data['actions'])} intents, {params} parameters — parsed by LinkMetadata; "
          f"parameters and {checked} display texts match the Swift code")


def display_texts(obj):
    """Every localizable text in the metadata: objects shaped {"alternatives": [...], "key": "..."}."""
    if isinstance(obj, dict):
        if set(obj) == {"alternatives", "key"} and isinstance(obj["key"], str):
            yield obj["key"]
        for value in obj.values():
            yield from display_texts(value)
    elif isinstance(obj, list):
        for value in obj:
            yield from display_texts(value)


if __name__ == "__main__":
    main()
