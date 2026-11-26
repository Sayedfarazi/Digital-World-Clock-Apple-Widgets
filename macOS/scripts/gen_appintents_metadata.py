#!/usr/bin/env python3
"""Generate Metadata.appintents for the widget extension (what Xcode's appintentsmetadataprocessor does).

The system (linkd / chronod / the "Edit Widget" UI) never looks at Swift code: it learns about intents and
their parameters from <appex>/Contents/Resources/Metadata.appintents/.
Xcode generates that at build time; this project is built with the Command Line Tools only, so this
script writes it from the declarative SPEC below, in exactly the format Apple's own widgets ship
(templates: HomeWidget.appex RecommendedItemIntent, FindMyWidgetPeople.appex, JournalWidgetsSecure.appex).

Mangled Swift type names are NOT computed here (Swift compresses repeated words, e.g. ClockStyleOption
-> "12ClockWidgets0A11StyleOptionO"); they are read from the compiled binary's nominal type descriptors.

Parameters are Bools and Strings only. A String parameter gets its choices from a DynamicOptionsProvider.
No AppEnum or AppEntity types: the AppIntents runtime decodes those with metadata it asks linkd for, and linkd
refuses processes without a Team ID ("requiresValidatedBundle"), so in this ad-hoc signed extension every
enum or entity value arrived empty (ARCHITECTURE §5).

usage: gen_appintents_metadata.py <widget-binary> <module-name> <output-Metadata.appintents-dir>
       gen_appintents_metadata.py check <Intents.swift> <output-check.swift>

!! Keep SPEC in sync with Shared/Widget/Intents.swift. build.sh checks it three ways before it signs:
!!  - "check" (before compiling) compares SPEC with the declarations in Intents.swift: intents, parameters in
!!    order, types, optionality, titles, descriptions, defaults and options providers;
!!  - the Swift file "check" writes is compiled into the widget, so the compiler rejects a parameter whose type
!!    (or optionality) differs from SPEC, and an options provider that doesn't return Strings;
!!  - macOS/scripts/verify_metadata.py checks the generated metadata against the compiled binary.
"""
import json
import os
import re
import subprocess
import sys

TOOLS_VERSION = "27A225b"  # matches the OS's own widgets (macOS 27); older/newer readers accept it

# ---------------------------------------------------------------------------------------------------
# SPEC — mirror of Shared/Widget/Intents.swift
# ---------------------------------------------------------------------------------------------------
# Option lists: DynamicOptionsProvider types in Intents.swift whose results are Strings.
PROVIDERS = ["StyleOptionsProvider", "TimeFormatOptionsProvider", "CityOptionsProvider"]

CITY_PARAM = {"name": "city", "kind": "string", "optional": True, "options": "CityOptionsProvider", "title": "City",
              "description": "Leave empty to use the City Widget city set in the Digital World-Clock Widgets app (normally the city of your time zone)."}
# World Clock: Edit Widget shows exactly this many city rows per widget size, like Apple's World Clock widget.
# Metadata only (for a [String] parameter, Swift's @Parameter can't take both size: and optionsProvider:).
# "check" compares it with ClockFamily.worldClockCapacity in Shared/Core/ClockStyle.swift.
WORLD_CLOCK_ROWS = {"systemSmall": 4, "systemMedium": 4, "systemLarge": 8, "systemExtraLarge": 12}
CITIES_PARAM = {"name": "cities", "kind": "stringArray", "options": "CityOptionsProvider", "title": "Cities",
                "description": "One row per clock. Rows left empty show the cities of the list in the Digital World-Clock Widgets app.",
                "rows": WORLD_CLOCK_ROWS}


def common_params(default_style):
    return [
        {"name": "style", "kind": "string", "options": "StyleOptionsProvider", "title": "Style",
         "default": default_style},
        {"name": "showsSeconds", "kind": "bool", "title": "Show Seconds",
         "description": "Digital clocks show the seconds under the time. Analog hands move once a minute.", "default": True},
        {"name": "timeFormat", "kind": "string", "options": "TimeFormatOptionsProvider", "title": "Time Format",
         "description": "Used by the digital style.", "default": "System Setting"},
    ]


INTENTS = {
    "CityAnalogIntent": {"title": "City", "description": "Check the time in a city of your choice.",
                         "params": [CITY_PARAM] + common_params("Analog")},
    "CityDigitalIntent": {"title": "City Digital", "description": "Check the time in a city of your choice.",
                          "params": [CITY_PARAM] + common_params("Digital")},
    "WorldClockAnalogIntent": {"title": "World Clock",
                               "description": "View the time in multiple cities around the world.",
                               "params": [CITIES_PARAM] + common_params("Analog")},
    "WorldClockDigitalIntent": {"title": "World Clock Digital",
                                "description": "View the time in multiple cities around the world.",
                                "params": [CITIES_PARAM] + common_params("Digital")},
}

# ---------------------------------------------------------------------------------------------------


def text(key):
    return {"alternatives": [], "key": key}


WILDCARD = {"LNPlatformNameWildcard": {"introducedVersion": "*"}}
VISIBLE = {"assistantOnly": False, "isDiscoverable": True}


def mangled_names(binary, module):
    """Map 'Module.TypeName' -> mangled type name, from nominal type descriptor symbols ($s...Mn)."""
    out = subprocess.run(["nm", binary], capture_output=True, text=True, check=True).stdout
    symbols = sorted({line.split()[-1] for line in out.splitlines()
                      if re.search(r"\s_?\$s\S+Mn$", line)})
    plain = [s.lstrip("_") for s in symbols]
    demangled = subprocess.run(["xcrun", "swift-demangle"], input="\n".join(plain),
                               capture_output=True, text=True, check=True).stdout.splitlines()
    result = {}
    for sym, dem in zip(plain, demangled):
        m = re.match(r"nominal type descriptor for (.+)$", dem.strip())
        if m:
            result[m.group(1)] = sym[2:-2]  # strip "$s" and "Mn"
    return result


STRING = {"primitive": {"wrapper": {"typeIdentifier": 0}}}
# What Xcode writes for a String parameter (e.g. its widget template's ConfigurationAppIntent.favoriteEmoji).
STRING_INPUTS = [{"kindValue": 0, "valueType": {"primitive": {"wrapper": {"typeIdentifier": 2}}}},
                 {"kindValue": 0, "valueType": STRING},
                 {"kindValue": 0, "valueType": {"array": {"wrapper": {
                     "capabilities": 3, "memberValueType": {"primitive": {"wrapper": {"typeIdentifier": 2}}}}}}}]
# capabilities is a bit set: 1 = static default, 4 = entity query, 8 = options provider (as in Apple's apps).
HAS_DEFAULT, HAS_OPTIONS = 1, 8


def parameter(p):
    base = {
        "inputConnectionBehavior": 0,
        "isInput": False,
        "name": p["name"],
        "title": text(p["title"]),
    }
    if p.get("description"):
        base["parameterDescription"] = text(p["description"])
    kind = p["kind"]
    options = HAS_OPTIONS if p.get("options") else 0
    if kind == "bool":
        vt = {"primitive": {"wrapper": {"typeIdentifier": 1}}}
        base.update(capabilities=HAS_DEFAULT, dynamicOptionsSupport=0, isOptional=False,
                    resolvableInputTypes=[{"kindValue": 0, "valueType": vt}],
                    typeSpecificMetadata=["LNValueTypeSpecificMetadataKeyDefaultValue",
                                          {"int": {"wrapper": 1 if p["default"] else 0}}],
                    valueType=vt)
    elif kind == "string":
        has_default = p.get("default") is not None
        base.update(capabilities=(HAS_DEFAULT if has_default else 0) | options,
                    dynamicOptionsSupport=1 if options else 0, isOptional=bool(p.get("optional")),
                    resolvableInputTypes=STRING_INPUTS,
                    typeSpecificMetadata=["LNValueTypeSpecificMetadataKeyDefaultValue",
                                          {"string": {"wrapper": p["default"]}}] if has_default else [],
                    valueType=STRING)
    elif kind == "stringArray":
        # Like Mail's MailFocusConfigurationAction.accounts: an optional array with an options provider.
        base.update(capabilities=options, dynamicOptionsSupport=1 if options else 0, isOptional=True,
                    resolvableInputTypes=[], typeSpecificMetadata=collection_sizes(p.get("rows")),
                    valueType={"array": {"wrapper": {"capabilities": 3, "memberValueType": STRING}}})
    else:
        raise ValueError(kind)
    return base


def collection_sizes(rows):
    """A fixed number of values per widget size, as for @Parameter(size: [.systemMedium: .init(exactly: 4), ...]).

    Format from HomeWidgetIntents.framework (HomeXLModuleConfigurationIntent.items: {"*": {"max": 16, "min": 0}}).
    The keys are LinkMetadata's LNActionConfigurationContextWidgetFamily* names ("*" = every size). With min ==
    max, WorkflowKit's Edit Widget shows a fixed list of rows (its "FixedSizeArray"), as in Apple's widget.
    """
    if not rows:
        return []
    return ["LNValueTypeMetadataKeyCollectionSizes",
            {"collectionSizes": {"sizes": {family: {"max": n, "min": n} for family, n in rows.items()}}}]


def build(binary, module):
    names = mangled_names(binary, module)

    def mangled(type_name):
        key = f"{module}.{type_name}"
        if key not in names:
            sys.exit(f"error: no type descriptor for {key} in {binary} (renamed in Swift but not in SPEC?)")
        return names[key]

    actions = {}
    for ident, spec in INTENTS.items():
        m = mangled(ident)
        actions[ident] = {
            "assistantDefinedSchemaTraits": [],
            "assistantDefinedSchemas": [],
            "authenticationPolicy": 0,
            "availabilityAnnotations": WILDCARD,
            "descriptionMetadata": {"descriptionText": text(spec["description"]), "searchKeywords": []},
            "effectiveBundleIdentifiers": [],
            "fullyQualifiedTypeName": f"{module}.{ident}",
            "identifier": ident,
            "isAuthPolExplicit": False,
            "isDiscoverable": False,
            "mangledTypeName": m,
            "mangledTypeNameByBundleIdentifier": {},
            "mangledTypeNameByBundleIdentifierV2": {},
            "mangledTypeNameV2": m,
            "openAppWhenRun": False,
            "outputFlags": 8,
            "parameters": [parameter(p) for p in spec["params"]],
            "presentationStyle": 0,
            "requiredCapabilities": [],
            "supportedModes": 1,
            "systemProtocolMetadata": ["com.apple.link.systemProtocol.WidgetConfiguration", {"empty": {}}],
            "systemProtocolMetadataV2": ["com.apple.link.systemProtocol.WidgetConfiguration", {"empty": {}}],
            "systemProtocols": ["com.apple.link.systemProtocol.WidgetConfiguration"],
            "title": text(spec["title"]),
            "typeSpecificMetadata": [],
            "visibilityMetadata": {"assistantOnly": False, "isDiscoverable": False},
        }

    return {
        "actions": actions,
        "assistantEntities": [],
        "assistantIntentNegativePhrases": [],
        "assistantIntents": [],
        "autoShortcuts": [],
        "entities": {},
        "enums": [],
        "generator": {"name": "xcode-tools", "version": TOOLS_VERSION},
        "negativePhrases": [],
        "queries": {},
        "shortcutTileColor": 14,
        "version": 1,
    }


# ---------------------------------------------------------------------------------------------------
# "check": SPEC <-> Intents.swift
# ---------------------------------------------------------------------------------------------------

SWIFT_TYPES = {"bool": "Bool", "string": "String", "stringArray": "[String]?"}


def swift_type(p):
    t = SWIFT_TYPES[p["kind"]]
    return t + "?" if p.get("optional") and not t.endswith("?") else t


def strip_swift_comments(src):
    """Removes // and /* */ comments, leaving string literals ("...") alone."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == '"':
            j = i + 1
            while j < n and src[j] != '"':
                j += 2 if src[j] == "\\" else 1
            out.append(src[i:j + 1])
            i = j + 1
        elif src.startswith("//", i):
            i = src.find("\n", i)
            i = n if i < 0 else i
        elif src.startswith("/*", i):
            i = src.find("*/", i)
            i = n if i < 0 else i + 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def swift_body(src, keyword, name):
    """The text between the braces of `<keyword> <name> ... { ... }` (braces inside strings ignored)."""
    m = re.search(rf"\b{keyword}\s+{name}\b[^{{]*\{{", src)
    if not m:
        return None
    i, depth, in_string = m.end(), 1, False
    while i < len(src) and depth:
        c = src[i]
        if in_string:
            if c == "\\":
                i += 1
            elif c == '"':
                in_string = False
        elif c == '"':
            in_string = True
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        i += 1
    return src[m.end():i - 1]


def top_level(body):
    """`body` without the contents of nested braces (e.g. a switch inside a computed property)."""
    out, depth, in_string, i = [], 0, False, 0
    while i < len(body):
        c = body[i]
        if in_string:
            if c == "\\":
                if depth == 0:
                    out.append(body[i:i + 2])
                i += 2
                continue
            if c == '"':
                in_string = False
        elif c == '"':
            in_string = True
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            i += 1
            continue
        if depth == 0:
            out.append(c)
        i += 1
    return "".join(out)


def swift_string(literal):
    return literal.replace('\\"', '"').replace("\\\\", "\\")


def check_source(path):
    """Compares SPEC with the declarations in Intents.swift. Returns a list of differences."""
    src = strip_swift_comments(open(path).read())
    errors = []

    def expect(what, swift_value, spec_value):
        if swift_value != spec_value:
            errors.append(f"{what}: Intents.swift has {swift_value!r}, SPEC has {spec_value!r}")

    declared = re.findall(r"\bstruct\s+(\w+)\s*:\s*[^{]*\bDynamicOptionsProvider\b", src)
    expect("options providers", sorted(declared), sorted(PROVIDERS))
    for kind in ("AppEnum", "AppEntity", "EntityQuery", "EntityStringQuery"):
        if re.search(rf":\s*[^{{]*\b{kind}\b", src):
            errors.append(f"Intents.swift declares an {kind}: ad-hoc signed builds can't decode its values; "
                          "use a String parameter with a DynamicOptionsProvider (ARCHITECTURE §5)")

    declared = set(re.findall(r"\bstruct\s+(\w+)\s*:\s*[^{]*\b(?:ClockConfigurationIntent|WidgetConfigurationIntent)\b", src))
    expect("configuration intents", sorted(declared), sorted(INTENTS))
    for ident, spec in INTENTS.items():
        body = swift_body(src, "struct", ident)
        if body is None:
            continue  # reported above
        m = re.search(r'static\s+var\s+title[^=]*=\s*"((?:[^"\\]|\\.)*)"', body)
        expect(f"{ident} title", m and swift_string(m.group(1)), spec["title"])
        m = re.search(r'IntentDescription\(\s*"((?:[^"\\]|\\.)*)"', body)
        expect(f"{ident} description", m and swift_string(m.group(1)), spec["description"])
        params = re.findall(r'@Parameter\((.*?)\)\s*var\s+(\w+)\s*:\s*([^\n=]+?)\s*$', body, re.S | re.M)
        expect(f"{ident} parameters (in order)", [name for _, name, _ in params], [p["name"] for p in spec["params"]])
        for (args, name, type_), p in zip(params, spec["params"]):
            if name != p["name"]:
                break
            what = f"{ident}.{name}"
            expect(f"{what} type", re.sub(r"\s+", "", type_), swift_type(p))
            m = re.search(r'title:\s*"((?:[^"\\]|\\.)*)"', args)
            expect(f"{what} title", m and swift_string(m.group(1)), p["title"])
            m = re.search(r'description:\s*"((?:[^"\\]|\\.)*)"', args)
            expect(f"{what} description", m and swift_string(m.group(1)), p.get("description"))
            m = re.search(r'default:\s*("(?:[^"\\]|\\.)*"|[^,)\s]+)', args)
            swift_default = m.group(1) if m else None
            if swift_default and swift_default.startswith('"'):
                swift_default = swift_string(swift_default[1:-1])
            elif swift_default in ("true", "false"):
                swift_default = swift_default == "true"
            expect(f"{what} default", swift_default, p.get("default"))
            m = re.search(r"optionsProvider:\s*(\w+)\s*\(", args)
            expect(f"{what} options provider", m and m.group(1), p.get("options"))
            if p.get("rows"):
                core = os.path.join(os.path.dirname(path), "..", "Core", "ClockStyle.swift")
                capacities = world_clock_capacities(core)
                if capacities != p["rows"]:
                    errors.append(f"{what} rows per widget size: ClockFamily.worldClockCapacity "
                                  f"(Shared/Core/ClockStyle.swift) is {capacities!r}, SPEC has {p['rows']!r}")
    return errors


# ClockFamily cases (Shared/Core/ClockStyle.swift) -> LinkMetadata's widget family names.
FAMILY_NAMES = {"small": "systemSmall", "medium": "systemMedium", "large": "systemLarge",
                "extraLarge": "systemExtraLarge"}


def world_clock_capacities(path):
    """{"systemSmall": 4, ...} from `var worldClockCapacity` (`case .small, .medium: return 4`, ...)."""
    if not os.path.exists(path):
        return f"(missing {path})"
    body = swift_body(strip_swift_comments(open(path).read()), "var", "worldClockCapacity")
    if body is None:
        return "(no var worldClockCapacity)"
    result = {}
    for cases, value in re.findall(r"case\s+([^:]+):\s*return\s+(\d+)", body):
        for case in re.findall(r"\.(\w+)", cases):
            result[FAMILY_NAMES.get(case, case)] = int(value)
    return result


def swift_check():
    """Swift source the widget is compiled with: it only type-checks if Intents.swift matches SPEC."""
    lines = [
        "// Generated by macOS/scripts/gen_appintents_metadata.py from its SPEC. Do not edit: build.sh rewrites it.",
        "// Compiled into the widget. If Shared/Widget/Intents.swift disagrees with the SPEC that",
        "// Metadata.appintents is generated from, this file doesn't compile.",
        "import AppIntents",
        "import WidgetKit",
        "",
        "private enum IntentsMatchMetadataSpec {",
        "    static func requireIntent<T: WidgetConfigurationIntent>(_: T.Type) {}",
        "",
        "    // Each options provider must offer Strings (a generic `where T.Result.Result == String` crashes swiftc).",
        "    static func providers() async throws {",
    ]
    lines += [f"        let _: [String] = try await {name}().results().items" for name in PROVIDERS]
    lines.append("    }")
    for ident, spec in INTENTS.items():
        lines += ["", f"    static func parameters(_ intent: {ident}) {{", f"        requireIntent({ident}.self)"]
        for p in spec["params"]:
            # IntentParameter is a generic class, so the type must match exactly, optionality included.
            lines.append(f"        let _: IntentParameter<{swift_type(p)}> = intent.${p['name']}")
        lines.append("    }")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "check":
        intents_swift, out_swift = sys.argv[2:]
        errors = check_source(intents_swift)
        if errors:
            sys.exit("error: SPEC in macOS/scripts/gen_appintents_metadata.py doesn't match "
                     f"{intents_swift}:\n  " + "\n  ".join(errors))
        os.makedirs(os.path.dirname(os.path.abspath(out_swift)), exist_ok=True)
        with open(out_swift, "w") as f:
            f.write(swift_check())
        print(f"SPEC matches {intents_swift}: {len(INTENTS)} intents, "
              f"{sum(len(i['params']) for i in INTENTS.values())} parameters, {len(PROVIDERS)} options providers; "
              f"wrote {out_swift}")
        return
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    binary, module, out_dir = sys.argv[1:]
    data = build(binary, module)
    os.makedirs(out_dir, exist_ok=True)
    with open(os.path.join(out_dir, "extract.actionsdata"), "w") as f:
        json.dump(data, f, sort_keys=True, separators=(",", ":"))
    with open(os.path.join(out_dir, "version.json"), "w") as f:
        f.write('{\n  "toolsVersion" : "%s",\n  "version" : "3.0"\n}' % TOOLS_VERSION)
    print(f"wrote {out_dir}: {len(data['actions'])} intents, "
          f"{sum(len(a['parameters']) for a in data['actions'].values())} parameters")


if __name__ == "__main__":
    main()
