#!/usr/bin/env node
// Checks the translation tables against the code that uses them.
//
//   node test-i18n.js            fail (exit 1) on any untranslated string
//   node test-i18n.js --report   list what is missing, never fail on it
//
// Every string literal passed to tr(), trn() or I18n.tr() in the QML files and
// Model.js must have a Korean entry with the same %N placeholders. Entries the
// code no longer uses are only warned about: catalog values (categories, kinds)
// reach tr() at runtime and never appear as literals.
//
// I18n.js is a QML .js library, loaded the same way test-model.js loads
// Model.js: strip the .pragma line and evaluate it.

const fs = require("fs")
const path = require("path")

const dir = __dirname
const reportOnly = process.argv.includes("--report")

function loadI18n() {
  const src = fs.readFileSync(path.join(dir, "I18n.js"), "utf8").replace(/^\.pragma library\s*/, "")
  return new Function(src + "\nreturn { languages: languages, tables: tables, resolve: resolve, tr: tr, trn: trn, later: later, raw: raw, fallbackLanguage: fallbackLanguage }")()
}

const I18n = loadI18n()

let passed = 0
let failed = 0

function check(label, cond, detail) {
  if (cond) {
    passed++
  } else {
    failed++
    console.error(`  FAIL  ${label}${detail ? "  ->  " + detail : ""}`)
  }
}

// ---------------------------------------------------------------- extraction

// Splits the argument list that starts just after `open` (the index of "(")
// into raw top-level argument strings, skipping over strings, comments and
// nested brackets.
function splitArgs(text, open) {
  const args = []
  let depth = 0
  let start = open + 1
  for (let i = open + 1; i < text.length; i++) {
    const ch = text[i]
    if (ch === '"' || ch === "'" || ch === "`") {
      for (i++; i < text.length && text[i] !== ch; i++)
        if (text[i] === "\\") i++
      continue
    }
    if (ch === "/" && text[i + 1] === "/") {
      while (i < text.length && text[i] !== "\n") i++
      continue
    }
    if (ch === "(" || ch === "[" || ch === "{") depth++
    else if (ch === ")" || ch === "]" || ch === "}") {
      if (depth === 0) {
        args.push(text.slice(start, i).trim())
        return args
      }
      depth--
    } else if (ch === "," && depth === 0) {
      args.push(text.slice(start, i).trim())
      start = i + 1
    }
  }
  return null
}

// A whole argument that is one plain string literal, or several joined with
// `+` across lines, decoded; otherwise null.
const LIT = String.raw`(?:"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')`
const LITERAL_EXPR = new RegExp(`^${LIT}(?:\\s*\\+\\s*${LIT})*$`)
function literal(arg) {
  if (!arg) return null
  const a = arg.trim()
  if (!LITERAL_EXPR.test(a)) return null
  return new Function("return " + a)()
}

function lineOf(text, index) {
  return text.slice(0, index).split("\n").length
}

function sourceFiles() {
  return fs.readdirSync(dir)
    .filter(f => f.endsWith(".qml") || f === "Model.js")
    .sort()
}

// Returns [{ key, where }] for every translatable literal in the code.
function extract() {
  const found = []
  const re = /\b(tr|trn|later)\s*\(/g
  for (const file of sourceFiles()) {
    const text = fs.readFileSync(path.join(dir, file), "utf8")
    let m
    while ((m = re.exec(text))) {
      // Skip the definitions themselves: `function tr(s)`.
      if (/function\s+$/.test(text.slice(Math.max(0, m.index - 12), m.index))) continue
      const args = splitArgs(text, m.index + m[0].length - 1)
      if (!args) continue
      const viaI18n = text.slice(Math.max(0, m.index - 5), m.index) === "I18n."
      const where = `${file}:${lineOf(text, m.index)}`
      // I18n.tr(lang, s, ...) and I18n.trn(lang, n, one, many, ...) carry the
      // language first; the component wrappers tr(s, ...) / trn(n, one, many) do not.
      // I18n.later(s, ...) holds a message to translate when it is shown; no language.
      const rest = viaI18n && m[1] !== "later" ? args.slice(1) : args
      const keys = m[1] === "trn" ? [rest[1], rest[2]] : [rest[0]]
      for (const k of keys) {
        const s = literal(k)
        if (s !== null) found.push({ key: s, where })
      }
    }
  }
  return found
}

// Strings Model.js translates through a variable rather than a literal.
function modelDynamicKeys() {
  const src = fs.readFileSync(path.join(dir, "Model.js"), "utf8")
  const keys = []
  const sorts = /var SORTS = \[([\s\S]*?)\]/.exec(src)
  if (sorts) {
    const re = /label:\s*("(?:\\.|[^"\\])*")/g
    let m
    while ((m = re.exec(sorts[1]))) keys.push({ key: JSON.parse(m[1]), where: "Model.js:SORTS" })
  }
  return keys
}

function placeholders(s) {
  return Array.from(new Set(String(s).match(/%\d+/g) || [])).sort().join(",")
}

// ---------------------------------------------------------------- unit

console.log("I18n.resolve")
check("auto + ko_KR -> ko", I18n.resolve("auto", "ko_KR") === "ko")
check("auto + ko-KR -> ko", I18n.resolve("auto", "ko-KR") === "ko")
// What Auto lands on without a matching table; "en" here, a distribution may
// change it.
const fb = I18n.fallbackLanguage
check("explicit en stays en", I18n.resolve("en", "ko_KR") === "en")
check("auto + en_US -> fallback", I18n.resolve("auto", "en_US") === fb)
check("auto + unsupported -> fallback", I18n.resolve("auto", "fr_FR") === fb)
check("auto + empty locale -> fallback", I18n.resolve("auto", "") === fb)
check("empty setting means auto", I18n.resolve("", "ko_KR") === "ko")
check("explicit ko", I18n.resolve("ko", "en_US") === "ko")
check("explicit en beats a ko locale", I18n.resolve("en", "ko_KR") === "en")
check("unsupported setting -> fallback", I18n.resolve("xx", "ko_KR") === fb)
check("prefix is not a match", I18n.resolve("auto", "kok_IN") === fb)

console.log("I18n.tr / trn")
// Work on a probe key added to the loaded copy, never to the file.
const probe = "__probe %1 of %2"
const probeOne = "__probe %1 item"
const probeMany = "__probe %1 items"
I18n.tables.ko[probe] = "__프로브 %2 중 %1"
I18n.tables.ko[probeOne] = "__프로브 항목 %1개(단수)"
I18n.tables.ko[probeMany] = "__프로브 항목 %1개"
check("en is the source", I18n.tr("en", "Install") === "Install")
check("missing key falls back to English", I18n.tr("ko", "__no such key") === "__no such key")
check("unknown language falls back to English", I18n.tr("xx", "Install") === "Install")
check("en substitutes in order", I18n.tr("en", probe, 3, 9) === "__probe 3 of 9")
check("ko keeps its own order", I18n.tr("ko", probe, 3, 9) === "__프로브 9 중 3")
check("missing argument leaves the marker", I18n.tr("en", probe, 3) === "__probe 3 of %2")
check("substitution is not recursive", I18n.tr("en", "%1", "%2", "x") === "%2")
check("trn en singular", I18n.trn("en", 1, probeOne, probeMany) === "__probe 1 item")
check("trn en plural", I18n.trn("en", 2, probeOne, probeMany) === "__probe 2 items")
check("trn en zero is plural", I18n.trn("en", 0, probeOne, probeMany) === "__probe 0 items")
check("trn ko singular form", I18n.trn("ko", 1, probeOne, probeMany) === "__프로브 항목 1개(단수)")
check("trn ko plural form", I18n.trn("ko", 5, probeOne, probeMany) === "__프로브 항목 5개")
check("trn passes extra arguments as %2",
  I18n.trn("en", 2, "%1 plugin in %2", "%1 plugins in %2", "Widgets") === "2 plugins in Widgets")
const held = I18n.later(probe, 3, 9)
check("later is a non-empty string", typeof held === "string" && held !== "")
check("later translates when shown, en", I18n.tr("en", held) === "__probe 3 of 9")
check("later follows a language change", I18n.tr("ko", held) === "__프로브 9 중 3")
check("plain text passes through tr unchanged", I18n.tr("ko", "exit 1: %1 not found") === "exit 1: %1 not found")
check("%0 is left alone", I18n.tr("en", "error %0") === "error %0")
check("a passed undefined prints like concatenation", I18n.tr("en", "exit %1", undefined) === "exit undefined")
check("raw keeps empty empty", I18n.raw("") === "")
check("raw text is shown verbatim, even if it is a key", I18n.tr("ko", I18n.raw("Install")) === "Install")
const lookalike = "\u0001[\"%1\",\"changed\"]"
check("raw text that looks held is shown verbatim", I18n.tr("en", I18n.raw(lookalike)) === lookalike)
check("literal() reads a joined literal", literal('"a b " +\n   "c"') === "a b c")
check("literal() rejects a variable", literal('"a" + x') === null)
delete I18n.tables.ko[probe]
delete I18n.tables.ko[probeOne]
delete I18n.tables.ko[probeMany]

const unitFailed = failed

// ---------------------------------------------------------------- coverage

console.log("Coverage of tables.ko")
const used = extract().concat(modelDynamicKeys())
const ko = I18n.tables.ko
const usedKeys = new Set(used.map(u => u.key))

const missing = []
const seenMissing = new Set()
for (const u of used) {
  if (Object.prototype.hasOwnProperty.call(ko, u.key)) continue
  if (seenMissing.has(u.key)) continue
  seenMissing.add(u.key)
  missing.push(u)
}

const badPlaceholders = []
for (const key of Object.keys(ko)) {
  if (placeholders(key) !== placeholders(ko[key]))
    badPlaceholders.push(`${JSON.stringify(key)} [${placeholders(key)}] -> ${JSON.stringify(ko[key])} [${placeholders(ko[key])}]`)
}

// A key no literal uses may still arrive at runtime (catalog categories,
// kinds, statuses), so this is a warning. Keys that at least appear quoted
// somewhere in the code are not even worth a warning.
const allCode = sourceFiles().map(f => fs.readFileSync(path.join(dir, f), "utf8")).join("\n")
const dead = Object.keys(ko).filter(k => !usedKeys.has(k)
  && allCode.indexOf(JSON.stringify(k)) === -1 && allCode.indexOf("'" + k + "'") === -1)

console.log(`  ${usedKeys.size} distinct strings in code, ${Object.keys(ko).length} in tables.ko`)
if (missing.length) {
  console.log(`  ${missing.length} untranslated:`)
  for (const u of missing) console.log(`    ${u.where}  ${JSON.stringify(u.key)}`)
}
if (badPlaceholders.length) {
  console.log(`  ${badPlaceholders.length} placeholder mismatches:`)
  for (const b of badPlaceholders) console.log(`    ${b}`)
}
if (dead.length) {
  console.log(`  WARN  ${dead.length} ko keys not used as literals (fine if they are catalog values):`)
  for (const k of dead) console.log(`    ${JSON.stringify(k)}`)
}

if (!reportOnly) {
  check("every translatable string has a ko entry", missing.length === 0, `${missing.length} missing`)
  check("ko placeholders match their source", badPlaceholders.length === 0, `${badPlaceholders.length} mismatched`)
} else if (badPlaceholders.length) {
  // A wrong placeholder renders a broken sentence; that fails even in report mode.
  check("ko placeholders match their source", false, `${badPlaceholders.length} mismatched`)
}

console.log(`\n${passed} passed, ${failed} failed (unit: ${unitFailed} failed)`)
process.exit(failed ? 1 : 0)
