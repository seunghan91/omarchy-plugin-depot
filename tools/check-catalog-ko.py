#!/usr/bin/env python3
"""Check i18n/catalog.ko.json against the catalog it was translated from.

Flags, per plugin id (descriptions) and per install note (the shared
"notes" table, reported as "note: <first words>"):
  missing      id or note in the catalog but not in the translation
  stale        src differs from the current catalog description
  extra        id or note no longer in the catalog
  empty        empty translated field
  untranslated mostly non-Hangul although the source is a real sentence
  foreign-script  Hanja/kana in the Korean text that the source does not have
  translationese  ~를 통해, ~에 대해, ~되어지다
  lost-token   a URL, backtick span, path or key combo from the source is gone
  length       translated/source length ratio outside the expected band

Usage:
  tools/check-catalog-ko.py [--catalog URL|FILE] [--ko FILE] [--ids-out bad.txt]

Exit status 1 when anything is flagged. Feed --ids-out to
`tools/translate-catalog.py --retranslate-ids` (and use --retranslate-notes
for flagged notes), then check again.
"""

import argparse
import json
import os
import re
import sys
import urllib.request

DEFAULT_SOURCE = "https://plugins.omarchy.org/catalog.json"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_KO = os.path.join(ROOT, "i18n", "catalog.ko.json")

HANGUL = re.compile(r"[가-힣]")
LETTER = re.compile(r"[^\W\d_]")
TOKEN_PATTERNS = [
    re.compile(r"https?://[^\s)\]>\"']+"),
    re.compile(r"`[^`]+`"),
    re.compile(r"(?<![\w.])(?:~|\$HOME)?/(?:[\w.-]+/)+[\w.-]*"),
    # Key combos up to the final key; a trailing word such as "click" may be translated.
    re.compile(r"\b(?:Super|Ctrl|Alt|Shift|Mod|Meta)(?:\s*\+\s*(?:Super|Ctrl|Alt|Shift|Mod|Meta))*"
               r"\s*\+\s*(?:[A-Za-z0-9/]|F\d{1,2}|Tab|Esc|Enter|Return|Space)(?![\w-])", re.I),
]
# Chinese/Japanese left in the output means a non-English source was not translated.
FOREIGN = re.compile(r"[\u3040-\u30ff\u4e00-\u9fff]")
# Phrases the translation guide forbids.
TRANSLATIONESE = re.compile(r"[을를] 통해|에 대해|되어지|되어진")


def load_catalog(src):
    if re.match(r"^https?://", src):
        req = urllib.request.Request(src, headers={"User-Agent": "plugin-depot-ko/1"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    else:
        with open(src, encoding="utf-8") as f:
            data = json.load(f)
    plugins = data["plugins"] if isinstance(data, dict) else data
    # Verbatim, like the UI's jq comparison.
    return {p["id"]: {"description": p.get("description") or "",
                      "installNote": p.get("installNote") or ""}
            for p in plugins if p.get("id")}


def norm(s):
    return re.sub(r"\s+", "", s).rstrip(".,;:").lower()


def lost_tokens(src, ko):
    k = norm(ko)
    lost = []
    for pat in TOKEN_PATTERNS:
        for m in pat.finditer(src):
            tok = m.group(0).strip("`")
            if norm(tok) not in k:
                lost.append(m.group(0))
    return lost


def looks_like_prose(src):
    """A source worth translating: several lowercase words, not just a name."""
    words = re.findall(r"[A-Za-z]+", src)
    return len([w for w in words if w.islower() and len(w) > 2]) >= 3


def check_field(src, ko):
    if not ko.strip():
        return ["empty"]
    issues = []
    # Names are kept verbatim, so judge only the words that are not copied from the source.
    words = re.compile(r"[\uac00-\ud7a3]+|[^\W\d_\uac00-\ud7a3]+")
    src_words = set(words.findall(src.lower()))
    own = [w for w in words.findall(ko) if w.lower() not in src_words]
    hangul = HANGUL.findall("".join(own))
    letters = LETTER.findall("".join(own))
    if looks_like_prose(src) and (not hangul or len(hangul) / len(letters) < 0.5):
        issues.append("untranslated")
    added = set(FOREIGN.findall(ko)) - set(FOREIGN.findall(src))
    if added:
        issues.append("foreign-script " + "".join(sorted(added)))
    m = TRANSLATIONESE.search(ko)
    if m:
        issues.append("translationese " + m.group(0))
    lost = lost_tokens(src, ko)
    if lost:
        issues.append("lost-token " + ", ".join(lost[:3]))
    if len(src) >= 40 and not FOREIGN.search(src):
        ratio = len(ko) / len(src)
        if ratio < 0.25 or ratio > 1.6:
            issues.append(f"length {ratio:.2f}")
    return issues


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--catalog", default=DEFAULT_SOURCE)
    ap.add_argument("--ko", default=DEFAULT_KO)
    ap.add_argument("--ids-out", help="write flagged ids here, one per line")
    ap.add_argument("--json", action="store_true", help="print findings as JSON")
    args = ap.parse_args()

    catalog = load_catalog(args.catalog)
    with open(args.ko, encoding="utf-8") as f:
        data = json.load(f)
    ko, notes = data["plugins"], data.get("notes", {})

    findings = {}
    for pid in sorted(catalog):
        src = catalog[pid]
        row = ko.get(pid)
        if row is None:
            findings[pid] = ["missing"]
            continue
        issues = []
        if row.get("src", "") != src["description"]:
            issues.append("stale")
        if src["description"].strip():
            issues += [f"description: {i}" for i in check_field(src["description"], row.get("description") or "")]
        if issues:
            findings[pid] = issues
    extra = sorted(set(ko) - set(catalog))
    for pid in extra:
        findings[pid] = ["extra (not in catalog)"]

    note_keys = []
    live_notes = sorted({p["installNote"] for p in catalog.values() if p["installNote"].strip()})
    for text in live_notes:
        key = "note: " + " ".join(text.split()[:6])
        issues = ["missing"] if text not in notes else check_field(text, notes[text])
        if issues:
            findings[key] = issues
            note_keys.append(key)
    for text in sorted(set(notes) - set(live_notes)):
        key = "note: " + " ".join(text.split()[:6])
        findings[key] = ["extra (not in catalog)"]
        note_keys.append(key)

    if args.json:
        print(json.dumps(findings, ensure_ascii=False, indent=1))
    else:
        for pid, issues in findings.items():
            print(f"{pid}\t{'; '.join(issues)}")
        kinds = {}
        for issues in findings.values():
            for i in issues:
                key = i.split(" ")[0] if ":" not in i else i.split(":")[0] + ":" + i.split(":")[1].split()[0]
                kinds[key] = kinds.get(key, 0) + 1
        print(f"\n{len(catalog)} catalog ids, {len(ko)} translated, "
              f"{len(live_notes)} notes, {len(notes)} translated, {len(findings)} flagged", file=sys.stderr)
        for k, v in sorted(kinds.items()):
            print(f"  {k}: {v}", file=sys.stderr)
    if args.ids_out:
        with open(args.ids_out, "w", encoding="utf-8") as f:
            f.write("".join(pid + "\n" for pid in findings if pid not in extra and pid not in note_keys))
        if note_keys:
            print("notes flagged: rerun translate-catalog.py with --retranslate-notes", file=sys.stderr)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
