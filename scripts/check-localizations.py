#!/usr/bin/env python3
"""Check catalog coverage and printf argument types (no third-party packages)."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LANGUAGES = {"en", "es", "fr", "de", "pt-BR", "ja"}
TOKEN = re.compile(r"%(?:(\d+)\$)?(lld|ld|llu|lu|@|d|u|f)")


def arguments(value):
    """Compare numbered/reordered substitutions by their argument position."""
    result = {}
    for index, token in enumerate(TOKEN.finditer(value.replace("%%", "")), 1):
        position = int(token[1]) if token[1] else index
        kind = token[2]
        if position in result:
            assert result[position] == kind, value
        result[position] = kind
    return result


def units(node):
    if "stringUnit" in node:
        yield node["stringUnit"]
    for value in node.values():
        if isinstance(value, dict):
            yield from units(value)


count = 0
for name in ("Localizable", "InfoPlist"):
    path = ROOT / "HeroDirt" / f"{name}.xcstrings"
    catalog = json.loads(path.read_text())
    assert catalog["sourceLanguage"] == "en"
    for key, entry in catalog["strings"].items():
        if entry.get("shouldTranslate") is False:
            continue
        localized = entry.get("localizations", {})
        assert set(localized) == LANGUAGES, (key, set(localized))
        expected = arguments(key) if name == "Localizable" else {}
        for language, translation in localized.items():
            values = list(units(translation))
            assert values, (key, language)
            for unit in values:
                assert unit["state"] == "translated", (key, language)
                assert unit["value"].strip(), (key, language)
                assert arguments(unit["value"]) == expected, (key, language, unit["value"])
        count += 1
print(f"Validated {count} catalog entries in {len(LANGUAGES)} languages.")
