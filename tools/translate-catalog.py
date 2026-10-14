#!/usr/bin/env python3
"""Translate Plugin Depot catalog descriptions to Korean.

Reads the marketplace catalog (URL or file) and writes i18n/catalog.ko.json:

  {"version":1,"source":...,"generatedAt":...,
  "notes":{"<English installNote>":"<Korean>", ...},
  "plugins":{"<id>":{"src":"<English description>","description":"<Korean>"}, ...}}

One note or plugin per line, keys sorted, so a catalog refresh produces a
small diff. Install notes are a handful of shared sentences, so they live in
one table keyed by the English text. The UI shows the Korean description only
while `src` equals the live catalog string, so a stale translation falls back
to English by itself; a note without a table entry does the same.
Entries whose sources are unchanged are kept; translations of identical
source text are reused across ids. Ids that left the catalog are dropped.

Translation engines (--engine):
  claude (default)  headless `claude -p --model sonnet`, no tools, no MCP
  glm               Z.ai GLM chat completions. The key comes from $ZAI_API_KEY,
                    then the macOS Keychain (service "zai-api-key"); it is
                    never printed.

Usage:
  tools/translate-catalog.py                         # official catalog URL
  tools/translate-catalog.py --catalog catalog.json  # local copy
  tools/translate-catalog.py --limit 50              # trial run
  tools/translate-catalog.py --retranslate-ids bad.txt
  tools/translate-catalog.py --retranslate-notes
"""

import argparse
import concurrent.futures
import datetime
import hashlib
import json
import os
import random
import re
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request

DEFAULT_SOURCE = "https://plugins.omarchy.org/catalog.json"
BASE_URL = os.environ.get("ZAI_BASE_URL") or "https://api.z.ai/api/coding/paas/v4"
MODEL = os.environ.get("ZAI_MODEL") or "glm-5.3"
KEYCHAIN_SERVICE = "zai-api-key"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_OUT = os.path.join(ROOT, "i18n", "catalog.ko.json")

SYSTEM_PROMPT = """\
You translate plugin descriptions from the Omarchy plugin catalog into Korean.
Omarchy is a Linux desktop (Arch + Hyprland). Readers are Korean Linux users.

Input: a JSON object mapping keys to source strings.
Output: a JSON object with exactly the same keys, each mapped to its Korean
translation. Output only the JSON object, no commentary, no code fences.

Rules:
1. Keep the sentence type of the source.
   - Noun phrase stays a noun phrase:
     "Pomodoro timer for the Omarchy bar" -> "Omarchy 바용 뽀모도로 타이머"
     "Simple OpenVPN toggle switch, profile selector, and live stats in the Omarchy bar."
       -> "Omarchy 바의 간단한 OpenVPN 토글 스위치, 프로필 선택기, 실시간 통계."
     "Today and overdue TickTick tasks in the Omarchy bar."
       -> "Omarchy 바의 오늘 할 일과 기한 지난 TickTick 작업."
     Do not turn a noun phrase into a sentence by adding a verb like "표시합니다".
   - Full sentences end in the polite "~합니다" form:
     "Shows CPU usage in the bar." -> "바에 CPU 사용량을 표시합니다."
   - Instructions to the reader end in "~하세요":
     "Follow the upstream installation instructions." -> "업스트림 설치 안내를 따르세요."
2. Keep verbatim: proper nouns, product and project names, plugin names,
   commands, CLI flags, key combinations (Super+Space, Ctrl + Z), file paths,
   URLs, domains, environment variables, and anything inside backticks or
   <angle brackets>. Do not transliterate product names into Hangul
   (Hyprland, Waybar, Quickshell, Spotify, Claude Code, Omarchy, Omarchy Quattro stay as is).
3. Natural Korean. Avoid translationese: never write "~를 통해"/"~을 통해"
   (use "~로", "~에서", "~를 거쳐", or rephrase), "~에 대해" (use "~를"), "~되어지다",
   or double passives. Prefer active voice.
   "Send messages through your iPhone" -> "iPhone으로 메시지를 보냅니다"
   Write in Hangul. Never add Hanja or Japanese kanji that are not in the source
   ("modifier keys" -> "보조 키", not "修飾 키").
4. Do not exaggerate, do not add or drop information, do not explain.
   Keep emoji and punctuation such as parentheses as in the source.
5. Terminology: plugin=플러그인, bar=바, widget=위젯, panel=패널,
   workspace=워크스페이스, theme=테마, wallpaper=배경화면,
   notification=알림, launcher=런처, shortcut=단축키, popup=팝업,
   toggle=토글, overlay=오버레이, menu=메뉴, monitor=모니터.
6. If the source is not English (Chinese, Portuguese, Spanish, ...),
   translate it into Korean the same way. If it is already Korean, return it unchanged.
7. If the whole source is only a name or a code token, return it unchanged.
"""


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def sha16(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def memo_key(text):
    """Translations are keyed by the trimmed source; outer whitespace never reaches the prompt."""
    return sha16(text.strip())


# ---------------------------------------------------------------- catalog io

def load_catalog(src):
    if re.match(r"^https?://", src):
        req = urllib.request.Request(src, headers={"User-Agent": "plugin-depot-ko/1"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    else:
        with open(src, encoding="utf-8") as f:
            data = json.load(f)
    plugins = data["plugins"] if isinstance(data, dict) else data
    out = {}
    for p in plugins:
        pid = p.get("id")
        if not pid:
            continue
        out[pid] = {
            # Verbatim: `src` and the notes keys must equal the catalog strings exactly,
            # because the UI matches them with jq string equality.
            "description": p.get("description") or "",
            "installNote": p.get("installNote") or "",
        }
    return out


def load_existing(path):
    """-> (plugins, notes)"""
    if not os.path.exists(path):
        return {}, {}
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    return data.get("plugins", {}), data.get("notes", {})


def json_table(name, table):
    lines = [f"{json.dumps(name)}:{{"]
    keys = sorted(table)
    for i, k in enumerate(keys):
        v = json.dumps(table[k], ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        lines.append(f"{json.dumps(k, ensure_ascii=False)}:{v}" + ("," if i < len(keys) - 1 else ""))
    lines.append("}")
    return lines


def write_output(path, source, plugins, notes):
    """One entry per line, sorted keys: refreshes diff line by line."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    stamp = datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0)
    head = {"version": 1, "source": source,
            "generatedAt": stamp.isoformat().replace("+00:00", "Z")}
    lines = ["{"]
    for k in ("version", "source", "generatedAt"):
        lines.append(f"{json.dumps(k)}:{json.dumps(head[k], ensure_ascii=False)},")
    notes_lines = json_table("notes", notes)
    notes_lines[-1] += ","
    lines += notes_lines + json_table("plugins", plugins)
    lines.append("}")
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    os.replace(tmp, path)


# ---------------------------------------------------------------- partial memo

class Memo:
    """source-text hash -> Korean, persisted after every batch so a rerun resumes."""

    def __init__(self, path):
        self.path = path
        self.lock = threading.Lock()
        self.data = {}
        if os.path.exists(path):
            with open(path, encoding="utf-8") as f:
                self.data = json.load(f)

    def get(self, text):
        return self.data.get(memo_key(text))

    def put_many(self, pairs):
        with self.lock:
            for text, ko in pairs:
                self.data[memo_key(text)] = ko
            tmp = self.path + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(self.data, f, ensure_ascii=False)
            os.replace(tmp, self.path)


# ---------------------------------------------------------------- api

def keychain_key():
    try:
        out = subprocess.run(
            ["security", "find-generic-password", "-a", os.environ.get("USER", ""),
             "-s", KEYCHAIN_SERVICE, "-w"],
            capture_output=True, text=True, timeout=10)
        if out.returncode == 0:
            return out.stdout.strip()
    except Exception:  # noqa: BLE001 — no keychain on this host
        pass
    return ""


def api_keys():
    keys = []
    for k in (os.environ.get("ZAI_API_KEY", "").strip(), keychain_key()):
        if k and k not in keys:
            keys.append(k)
    if not keys:
        sys.exit("translate-catalog: no API key. Set $ZAI_API_KEY or the "
                 f"Keychain item '{KEYCHAIN_SERVICE}'.")
    return keys


class ApiError(Exception):
    pass


class FatalApiError(Exception):
    """Retrying cannot help (no balance, bad key): stop the whole run."""


# Z.ai error codes that mean the account, not the request, is the problem.
FATAL_CODES = {"1113"}  # insufficient balance / no resource package


class ClaudeClient:
    """Headless Claude Code (`claude -p`) with tools, MCP and settings turned off."""

    def __init__(self, model, timeout):
        self.model = model
        self.timeout = timeout
        self.lock = threading.Lock()
        self.calls = 0
        self.failures = 0
        self.prompt_tokens = 0
        self.completion_tokens = 0
        self.cost_usd = 0.0
        self.workdir = tempfile.mkdtemp(prefix="translate-catalog-")

    def chat(self, user):
        cmd = ["claude", "-p", "--model", self.model, "--output-format", "json",
               "--tools", "", "--strict-mcp-config", "--setting-sources", "",
               "--no-session-persistence", "--system-prompt", SYSTEM_PROMPT]
        with self.lock:
            self.calls += 1
        try:
            out = subprocess.run(cmd, input=user, capture_output=True, text=True,
                                 timeout=self.timeout, cwd=self.workdir)
        except subprocess.TimeoutExpired:
            with self.lock:
                self.failures += 1
            raise ApiError(f"claude timed out after {self.timeout}s") from None
        try:
            body = json.loads(out.stdout)
        except json.JSONDecodeError:
            with self.lock:
                self.failures += 1
            detail = (out.stderr or out.stdout)[-300:]
            if out.returncode == 127 or "not logged in" in detail.lower():
                raise FatalApiError(f"claude unusable: {detail}") from None
            raise ApiError(f"claude exit {out.returncode}: {detail}") from None
        usage = body.get("usage") or {}
        with self.lock:
            self.prompt_tokens += (usage.get("input_tokens", 0)
                                   + usage.get("cache_creation_input_tokens", 0)
                                   + usage.get("cache_read_input_tokens", 0))
            self.completion_tokens += usage.get("output_tokens", 0)
            self.cost_usd += body.get("total_cost_usd") or 0.0
        text = (body.get("result") or "").strip()
        if body.get("is_error") or not text:
            with self.lock:
                self.failures += 1
            raise ApiError(f"claude error: {text[:300] or body.get('subtype')}")
        return text


class GlmClient:
    """Z.ai GLM chat completions (OpenAI compatible)."""

    def __init__(self, keys, model, effort, timeout):
        self.keys = keys
        self.key_index = 0
        self.model = model
        self.effort = effort
        self.timeout = timeout
        self.lock = threading.Lock()
        self.calls = 0
        self.failures = 0
        self.prompt_tokens = 0
        self.completion_tokens = 0
        self.cost_usd = 0.0

    def chat(self, user):
        payload = {
            "model": self.model,
            "messages": [{"role": "system", "content": SYSTEM_PROMPT},
                         {"role": "user", "content": user}],
            "max_tokens": 16384,
            "temperature": 0.2,
            "reasoning_effort": self.effort,
            "stream": False,
        }
        while True:
            key = self.keys[self.key_index]
            req = urllib.request.Request(
                f"{BASE_URL}/chat/completions",
                data=json.dumps(payload).encode("utf-8"),
                headers={"Authorization": f"Bearer {key}",
                         "Content-Type": "application/json"},
                method="POST")
            with self.lock:
                self.calls += 1
            try:
                with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                    body = json.loads(resp.read().decode("utf-8"))
            except urllib.error.HTTPError as e:
                detail = e.read().decode("utf-8", "replace")[:300]
                with self.lock:
                    self.failures += 1
                    if e.code in (401, 403) and self.key_index < len(self.keys) - 1:
                        self.key_index += 1
                        log(f"  auth failed with key #{self.key_index}, trying next key")
                        continue
                if e.code in (401, 403) or any(f'"code":"{c}"' in detail.replace(" ", "") for c in FATAL_CODES):
                    raise FatalApiError(f"HTTP {e.code}: {detail}") from None
                raise ApiError(f"HTTP {e.code}: {detail}") from None
            except Exception as e:  # noqa: BLE001 — timeouts and resets are retried by the caller
                with self.lock:
                    self.failures += 1
                raise ApiError(f"request failed: {e}") from None
            usage = body.get("usage") or {}
            with self.lock:
                self.prompt_tokens += usage.get("prompt_tokens", 0)
                self.completion_tokens += usage.get("completion_tokens", 0)
            choice = (body.get("choices") or [{}])[0]
            text = ((choice.get("message") or {}).get("content") or "").strip()
            if not text:
                with self.lock:
                    self.failures += 1
                raise ApiError(f"empty content (finish_reason={choice.get('finish_reason')})")
            return text


def parse_json_object(text):
    text = re.sub(r"^```(?:json)?\s*|\s*```$", "", text.strip())
    start, end = text.find("{"), text.rfind("}")
    if start < 0 or end < start:
        raise ApiError("no JSON object in response")
    try:
        return json.loads(text[start:end + 1])
    except json.JSONDecodeError as e:
        raise ApiError(f"bad JSON: {e}") from None


def translate_batch(client, texts):
    """texts: list[str] -> list[str]. Raises ApiError on any mismatch."""
    keys = [f"t{i}" for i in range(len(texts))]
    user = json.dumps(dict(zip(keys, texts)), ensure_ascii=False, indent=0)
    result = parse_json_object(client.chat(user))
    if set(result) != set(keys):
        missing = sorted(set(keys) - set(result))
        extra = sorted(set(result) - set(keys))
        raise ApiError(f"key mismatch missing={missing[:5]} extra={extra[:5]}")
    out = []
    for k in keys:
        v = result[k]
        if not isinstance(v, str) or not v.strip():
            raise ApiError(f"empty translation for {k}")
        out.append(v.strip())
    return out


def translate_with_retry(client, texts, memo, attempts, failed):
    for attempt in range(attempts):
        try:
            out = translate_batch(client, texts)
            memo.put_many(zip(texts, out))
            return
        except ApiError as e:
            wait = min(60, 2 ** (attempt + 1)) + random.random()
            if "HTTP 429" in str(e):
                wait += 10
            log(f"  batch of {len(texts)} failed ({e}); retry in {wait:.0f}s")
            time.sleep(wait)
    if len(texts) == 1:
        failed.append(texts[0])
        log(f"  giving up on: {texts[0][:80]!r}")
        return
    mid = len(texts) // 2
    log(f"  splitting batch of {len(texts)}")
    translate_with_retry(client, texts[:mid], memo, attempts, failed)
    translate_with_retry(client, texts[mid:], memo, attempts, failed)


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--catalog", default=DEFAULT_SOURCE, help="catalog URL or file path")
    ap.add_argument("--source-url", default=DEFAULT_SOURCE,
                    help="value written to the 'source' field")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--limit", type=int, default=0,
                    help="only translate the first N plugins (trial run)")
    ap.add_argument("--batch", type=int, default=35)
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--attempts", type=int, default=3)
    ap.add_argument("--engine", choices=["claude", "glm"], default="claude")
    ap.add_argument("--effort", default="low", help="glm reasoning effort")
    ap.add_argument("--model", help="default: sonnet (claude) / $ZAI_MODEL or glm-5.3 (glm)")
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--retranslate-ids", help="file with plugin ids (one per line) to translate again")
    ap.add_argument("--retranslate-notes", action="store_true", help="translate the install notes again")
    args = ap.parse_args()

    started = time.time()
    catalog = load_catalog(args.catalog)
    ids = sorted(catalog)
    if args.limit:
        ids = ids[:args.limit]
    existing, existing_notes = load_existing(args.out)
    force = set()
    if args.retranslate_ids:
        with open(args.retranslate_ids, encoding="utf-8") as f:
            force = {line.strip() for line in f if line.strip()}

    memo = Memo(os.path.join(os.path.dirname(args.out), ".catalog.ko.partial.json"))
    # Forced sources lose their memoized translation, and no other id with the
    # same text may seed it back.
    forced = {memo_key(catalog[pid]["description"]) for pid in force & set(catalog)}
    if args.retranslate_notes:
        forced |= {memo_key(p["installNote"]) for p in catalog.values() if p["installNote"]}
        existing_notes = {}
    for key in forced:
        memo.data.pop(key, None)

    # Every other existing translation seeds the memo, so identical text is never sent twice.
    seeds = [(old.get("src"), old.get("description")) for old in existing.values()]
    seeds += list(existing_notes.items())
    for src_text, ko in seeds:
        if src_text and src_text.strip() and ko and memo_key(src_text) not in forced:
            memo.data.setdefault(memo_key(src_text), ko)

    result = {}
    todo = []
    for pid in ids:
        old = existing.get(pid)
        if old and pid not in force and old.get("src", "") == catalog[pid]["description"]:
            result[pid] = old
        else:
            todo.append(pid)
    note_texts = sorted({catalog[pid]["installNote"] for pid in ids if catalog[pid]["installNote"].strip()})

    pending = []
    seen = set()
    for text in [catalog[pid]["description"] for pid in todo] + note_texts:
        text = text.strip()
        if text and memo.get(text) is None and text not in seen:
            seen.add(text)
            pending.append(text)

    kept = len(result)
    log(f"catalog {len(catalog)} plugins, scope {len(ids)}, unchanged {kept}, "
        f"to build {len(todo)}, unique strings to translate {len(pending)}")

    if args.engine == "claude":
        client = ClaudeClient(args.model or "sonnet", args.timeout)
    else:
        client = GlmClient(api_keys(), args.model or MODEL, args.effort, args.timeout)
    failed = []
    batches = [pending[i:i + args.batch] for i in range(0, len(pending), args.batch)]
    done = [0]
    done_lock = threading.Lock()

    def run(batch):
        translate_with_retry(client, batch, memo, args.attempts, failed)
        with done_lock:
            done[0] += 1
            log(f"[{done[0]}/{len(batches)}] batches done, {time.time() - started:.0f}s")

    fatal = None
    if batches:
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
            futures = [pool.submit(run, b) for b in batches]
            for fut in futures:
                try:
                    fut.result()
                except FatalApiError as e:
                    fatal = e
                    for f in futures:
                        f.cancel()
                    break
    if fatal:
        # Batches already saved stay in the partial memo; the next run resumes from there.
        log(f"translate-catalog: stopping, the API refuses all requests: {fatal}")
        return 2

    missing = []
    for pid in todo:
        src = catalog[pid]
        desc = memo.get(src["description"]) if src["description"].strip() else ""
        if desc is None:
            missing.append(pid)
            continue
        result[pid] = {"src": src["description"], "description": desc}
    notes = {t: memo.get(t) for t in note_texts if memo.get(t) is not None}
    missing += [f"note: {t[:60]}" for t in note_texts if t not in notes]

    # A trial run (--limit) keeps entries outside its scope; a full run drops vanished ids.
    if args.limit:
        for pid, row in existing.items():
            if pid in catalog and pid not in result:
                result[pid] = row
        live_notes = {p["installNote"] for p in catalog.values()}
        for t, ko in existing_notes.items():
            if t in live_notes and t not in notes:
                notes[t] = ko
    if result != existing or notes != existing_notes:
        write_output(args.out, args.source_url, result, notes)
    else:
        log("no changes; output left untouched")
    if not missing and not args.limit and os.path.exists(memo.path):
        os.remove(memo.path)

    elapsed = time.time() - started
    stats = {
        "plugins": len(result), "notes": len(notes), "kept": kept, "built": len(todo) - len(missing),
        "uniqueStrings": len(pending), "batches": len(batches),
        "apiCalls": client.calls, "apiFailures": client.failures,
        "engine": args.engine, "model": client.model,
        "promptTokens": client.prompt_tokens, "completionTokens": client.completion_tokens,
        "costUsd": round(client.cost_usd, 2),
        "failedStrings": len(failed), "missingPlugins": len(missing),
        "seconds": round(elapsed, 1),
    }
    print(json.dumps(stats))
    if missing:
        log(f"{len(missing)} plugins left untranslated; rerun to resume: {missing[:10]}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
