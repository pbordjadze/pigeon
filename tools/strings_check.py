#!/usr/bin/env python3
"""Fails when the app's sources and its string catalog drift apart.

    tools/strings_check.py [--self-test]

Xcode extracts nothing here (STRING_CATALOG_GENERATE_SYMBOLS = NO and no Xcode on the
developers' machines), so a string missing from `Localizable.xcstrings` silently stays English on
a device. This reads every localizable literal in `App/Pigeon` (CLAUDE.md › Localization: a
SwiftUI literal with no interpolation, or `String(localized: "key", …)`) and checks:
  - every one has a catalog entry, and every catalog entry is used;
  - every entry has a comment, and an explicit key (`defaultValue:`) has its English value;
  - no SwiftUI literal interpolates (`Text("\\(x) routes")`): use `String(localized:defaultValue:)`.
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = os.path.join(ROOT, "App", "Pigeon")
CATALOG = os.path.join(SOURCES, "Resources", "Localizable.xcstrings")

STRING = r'"((?:[^"\\\n]|\\.)*)"'
# Initializers and modifiers whose first string literal is a LocalizedStringKey.
SWIFTUI = re.compile(
    r'(?<![\w.])(?:Text|Button|Label|Toggle|Section|NavigationLink|Picker|LabeledContent|ContentUnavailableView|Stepper|Annotation)\(\s*'
    + STRING
    + r'|\.(?:navigationTitle|accessibilityLabel|accessibilityHint|accessibilityValue|alert|confirmationDialog|help)\(\s*'
    + STRING)
LOCALIZED = re.compile(r'String\(localized:\s*' + STRING + r'(\s*,\s*defaultValue:\s*' + STRING + r')?')


def strip_comments(text):
    """Line comments out, string literals kept (a // inside a literal stays)."""
    return re.sub(r'("(?:[^"\\\n]|\\.)*")|//[^\n]*', lambda m: m.group(1) or "", text)


def scan(text):
    """(keys used, explicit keys with a default value, problems) of one Swift file's text."""
    text = strip_comments(text)
    keys, explicit, problems = set(), set(), []
    for m in SWIFTUI.finditer(text):
        literal = m.group(1) if m.group(1) is not None else m.group(2)
        if "\\(" in literal:
            problems.append(f"interpolation in a SwiftUI literal: \"{literal}\" (use String(localized:defaultValue:))")
        else:
            keys.add(literal)
    for m in LOCALIZED.finditer(text):
        keys.add(m.group(1))
        if m.group(2):
            explicit.add(m.group(1))
    return keys, explicit, problems


def check(sources, catalog):
    """Problems, given {path: text} and the catalog's JSON."""
    used, explicit, problems = set(), set(), []
    for path, text in sorted(sources.items()):
        k, e, p = scan(text)
        used |= k
        explicit |= e
        problems += [f"{path}: {line}" for line in p]
    entries = catalog.get("strings", {})
    for key in sorted(used - entries.keys()):
        problems.append(f"missing from Localizable.xcstrings: \"{key}\"")
    for key in sorted(entries.keys() - used):
        problems.append(f"in Localizable.xcstrings but not used: \"{key}\"")
    for key in sorted(entries.keys() & used):
        entry = entries[key]
        if not entry.get("comment"):
            problems.append(f"no comment for \"{key}\"")
        if key in explicit and "en" not in (entry.get("localizations") or {}):
            problems.append(f"explicit key \"{key}\" has no English value (localizations.en)")
    return problems, len(used)


def main():
    sources = {}
    for folder, _, files in os.walk(SOURCES):
        for name in files:
            if name.endswith(".swift"):
                path = os.path.join(folder, name)
                with open(path, encoding="utf-8") as f:
                    sources[os.path.relpath(path, ROOT)] = f.read()
    with open(CATALOG, encoding="utf-8") as f:
        catalog = json.load(f)
    problems, count = check(sources, catalog)
    for line in problems:
        print(line)
    if problems:
        print(f"strings: {len(problems)} problem(s)")
        return 1
    print(f"strings: {count} keys, catalog in step")
    return 0


def self_test():
    source = '''
        Text("Routes")  // Text("Commented out")
        Button("Start Drive") { }
        Label("No Routes Yet", systemImage: "x")
        .navigationTitle("Routes")
        Text(verbatim: "not a key")
        Text(name)
        let s = String(localized: "drive.count", defaultValue: "\\(n) drives", comment: "c")
        let t = String(localized: "Plain")
        Text("\\(n) routes")
    '''
    keys, explicit, problems = scan(source)
    assert keys == {"Routes", "Start Drive", "No Routes Yet", "drive.count", "Plain"}, keys
    assert explicit == {"drive.count"}, explicit
    assert len(problems) == 1 and "interpolation" in problems[0], problems
    catalog = {"strings": {
        "Routes": {"comment": "c"}, "Start Drive": {"comment": "c"}, "No Routes Yet": {},
        "drive.count": {"comment": "c"}, "Unused": {"comment": "c"},
    }}
    found, _ = check({"a.swift": source}, catalog)
    assert any('missing from Localizable.xcstrings: "Plain"' in p for p in found), found
    assert any('not used: "Unused"' in p for p in found), found
    assert any('no comment for "No Routes Yet"' in p for p in found), found
    assert any('"drive.count" has no English value' in p for p in found), found
    print("strings_check: self-test ok")
    return 0


if __name__ == "__main__":
    sys.exit(self_test() if sys.argv[1:] == ["--self-test"] else main())
