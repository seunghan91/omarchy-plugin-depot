#!/usr/bin/env node
// Tests for Model.js, run against this machine's REAL data rather than
// fixtures: the live marketplace index, the real installed inventory, and the
// real update check. A fixture would keep passing after the feed changes shape;
// this stops.
//
//   node test-model.js
//
// Model.js is a QML .js library, so it is loaded by stripping the .pragma line
// and evaluating it — the same source the shell loads, with no build step.

const fs = require("fs")
const path = require("path")
const { execFileSync } = require("child_process")

const dir = __dirname
// Model.js imports I18n.js; under node that import line is dropped and the
// same file is evaluated and handed in under the name the import gives it.
const i18nSrc = fs.readFileSync(path.join(dir, "I18n.js"), "utf8").replace(/^\.pragma library\s*/, "")
const I18n = new Function(i18nSrc + "\nreturn { tables: tables, resolve: resolve, tr: tr, trn: trn, later: later, raw: raw }")()
const src = fs.readFileSync(path.join(dir, "Model.js"), "utf8")
  .replace(/^\.pragma library\s*/, "")
  .replace(/^\.import .*$/gm, "")
const Model = {}
new Function(
  "exports", "I18n",
  src + `
  exports.normalizeRepo = normalizeRepo
  exports.mergeState = mergeState
  exports.filterAndSort = filterAndSort
  exports.categoriesOf = categoriesOf
  exports.countsOf = countsOf
  exports.scoreMatch = scoreMatch
  exports.initialsFor = initialsFor
  exports.kindsFromCatalogKind = kindsFromCatalogKind
  exports.formatStars = formatStars
  exports.formatCount = formatCount
  exports.sortOptions = sortOptions
  exports.isSort = isSort
  exports.relativeDate = relativeDate
  exports.truncate = truncate
  exports.kindLabelText = kindLabelText
`
)(Model, I18n)

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

function run(script, args = []) {
  return JSON.parse(execFileSync(path.join(dir, "bin", script), args, {
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
  }))
}

console.log("Loading real data from bin/ helpers...")
const catalog = run("pm-catalog")
const local = run("pm-local")
const updates = run("pm-updates")
const stats = run("pm-stats")
console.log(
  `  catalog: ${catalog.plugins.length} listed (online=${catalog.online}, stale=${catalog.stale})\n` +
  `  local:   ${local.counts.total} present, ${local.counts.installed} third-party\n` +
  `  updates: ${updates.checked} checked, ${updates.available} behind\n` +
  `  stats:   ${stats.count} with engagement counts (online=${stats.online})\n`
)

// ---------------------------------------------------------------- unit

console.log("normalizeRepo")
check("strips .git", Model.normalizeRepo("https://github.com/a/b.git") === "github.com/a/b")
check("strips trailing slash", Model.normalizeRepo("https://github.com/a/b/") === "github.com/a/b")
check("http and https agree",
  Model.normalizeRepo("http://github.com/A/B") === Model.normalizeRepo("https://github.com/a/b.git"))
check("scp form joins", Model.normalizeRepo("git@github.com:a/b.git") === "github.com/a/b")
check("empty stays empty", Model.normalizeRepo("") === "" && Model.normalizeRepo(null) === "")

console.log("initialsFor / kinds / formatting")
check("two words", Model.initialsFor("System Monitor") === "SM")
check("one word", Model.initialsFor("Okomart") === "OK")
check("junk", Model.initialsFor("") === "??")
check("kind split", JSON.stringify(Model.kindsFromCatalogKind("Service + Bar widget")) ===
  JSON.stringify(["service", "bar-widget"]))
check("stars 1200", Model.formatStars(1200) === "1.2k")
check("stars 20", Model.formatStars(20) === "20")
check("stars 0", Model.formatStars(0) === "")
const now = Date.parse("2026-09-03T00:00:00Z")
check("relative today", Model.relativeDate("2026-09-03T05:00:00Z", now) === "today")
check("relative days", Model.relativeDate("2026-08-29T00:00:00Z", now) === "5d ago")
check("relative months", Model.relativeDate("2026-05-01T00:00:00Z", now) === "4mo ago")
check("relative junk", Model.relativeDate("not-a-date", now) === "")
check("truncate", Model.truncate("abcdefghij", 5) === "abcd…")

// ---------------------------------------------------------------- merge

console.log("mergeState against real data")
const records = Model.mergeState(catalog, local, updates, stats)
const byId = Object.fromEntries(records.map(r => [r.id, r]))

check("every record has an id", records.every(r => r.id))
check("no duplicate ids", new Set(records.map(r => r.id)).size === records.length,
  `${records.length} records, ${new Set(records.map(r => r.id)).size} unique`)
check("every locally installed plugin appears",
  local.plugins.every(p => byId[p.id]),
  local.plugins.filter(p => !byId[p.id]).map(p => p.id).join(","))
check("record count >= catalog count", records.length >= catalog.plugins.length)

const thirdParty = local.plugins.filter(p => !p.firstParty)
for (const p of thirdParty) {
  const r = byId[p.id]
  check(`${p.id}: installed`, r && r.installed === true)
  check(`${p.id}: version from manifest`, r && r.version === p.version, r && r.version)
  check(`${p.id}: enabled matches`, r && r.enabled === p.enabled)
  check(`${p.id}: not first-party`, r && r.firstParty === false)
  check(`${p.id}: git tracked`, r && r.gitManaged === p.git.managed)
}

const firstParty = local.plugins.filter(p => p.firstParty)
check("first-party plugins are marked", firstParty.every(p => byId[p.id] && byId[p.id].firstParty))
check("first-party are never offered an install",
  firstParty.every(p => !byId[p.id].installable || byId[p.id].installed))

const listedAndInstalled = records.filter(r => r.listed && r.installed && !r.firstParty)
console.log(`  ${listedAndInstalled.length} installed plugin(s) matched a marketplace listing`)
check("at least one id-join worked", listedAndInstalled.length >= 1)
check("joined records carry catalog fields",
  listedAndInstalled.every(r => r.repo && r.category))

// "An update is available" must mean the same thing the Update button does.
// The button installs the commit the marketplace reviewed, so detection has to
// compare against that commit — not the repository's branch head, which may
// have moved past it. Comparing against the head left an already-updated
// plugin sitting in the Updates list forever.
const listedInstalled = records.filter(r => r.installed && r.listed && r.reviewedCommit && r.gitHead)
for (const r of listedInstalled) {
  const expected = r.gitHead !== r.reviewedCommit
  check(`${r.id}: update flag follows the reviewed commit, not the branch head`,
    r.updateAvailable === expected,
    `flag=${r.updateAvailable} head=${r.gitHead.slice(0, 7)} reviewed=${r.reviewedCommit.slice(0, 7)}`)
}
check("a plugin pinned to its reviewed commit is never listed as needing an update",
  listedInstalled.filter(r => r.gitHead === r.reviewedCommit).every(r => !r.updateAvailable))

// Anything the marketplace does not list has no reviewed commit, so those still
// fall back to the git check.
const unlistedInstalled = records.filter(r => r.installed && !r.reviewedCommit)
const gitBehind = new Set((updates.updates || []).filter(u => u.behind).map(u => u.id))
check("unlisted plugins still fall back to the git check",
  unlistedInstalled.every(r => r.updateAvailable === gitBehind.has(r.id)))

check("the Update button's target is the reviewed commit",
  listedInstalled.filter(r => r.updateAvailable)
    .every(r => r.updateTo === r.reviewedCommit.slice(0, 7)))

// ---------------------------------------------------------------- engagement

console.log("engagement counts (hearts / views / installs)")
const statIds = Object.keys(stats.plugins)
check("stats returned something", statIds.length > 100, String(statIds.length))

let joinedStats = 0
for (const id of statIds) {
  const r = byId[id]
  if (!r) continue
  joinedStats++
  const s = stats.plugins[id]
  if (r.hearts !== s.hearts || r.views !== s.views || r.copies !== s.copies) {
    check(`${id}: counts match the API`, false,
      `record ${r.hearts}/${r.views}/${r.copies} vs api ${s.hearts}/${s.views}/${s.copies}`)
    break
  }
}
check("every stats row that matched a record was carried through verbatim", joinedStats > 100,
  `${joinedStats} joined`)

check("records with no stats row report hasStats false, not zero-interest",
  records.filter(r => !r.hasStats).every(r => r.hearts === 0 && r.views === 0 && r.copies === 0))
check("at least one record has hearts", records.some(r => r.hearts > 0))

for (const p of thirdParty) {
  const r = byId[p.id]
  const s = stats.plugins[p.id]
  if (s) check(`${p.id}: hearts joined`, r.hearts === s.hearts, `${r.hearts} vs ${s.hearts}`)
}

console.log("marketplace links")
const listed = records.filter(r => r.listed)
check("every listed plugin gets a marketplace URL", listed.every(r => r.marketplaceUrl !== ""))
check("marketplace URL is the plugin page with an encoded id",
  listed.every(r => r.marketplaceUrl === "https://plugins.omarchy.org/plugin.html?id=" +
    encodeURIComponent(r.id)))
check("unlisted plugins get no marketplace URL",
  records.filter(r => !r.listed).every(r => r.marketplaceUrl === ""))

check("formatCount 1200", Model.formatCount(1200) === "1.2k")
check("formatCount 0 is empty", Model.formatCount(0) === "")

console.log("sort options")
const opts = Model.sortOptions()
check("every offered sort has a value and a label",
  opts.length >= 6 && opts.every(o => o.value && o.label))
check("isSort accepts every offered value", opts.every(o => Model.isSort(o.value)))
check("isSort rejects anything else", !Model.isSort("nonsense") && !Model.isSort(""))

// Every offered sort must actually order the list by the field it names,
// otherwise the dropdown is decorative.
const orderedBy = {
  stars: r => r.stars,
  hearts: r => r.hearts,
  views: r => r.views,
  installs: r => r.copies,
}
for (const [sort, key] of Object.entries(orderedBy)) {
  const list = Model.filterAndSort(records, { scope: "browse", sort })
  check(`${sort}: descending`, list.every((r, i) => i === 0 || key(list[i - 1]) >= key(r)),
    `first few: ${list.slice(0, 3).map(key).join(", ")}`)
  check(`${sort}: top entry is non-zero`, list.length > 0 && key(list[0]) > 0,
    String(list.length ? key(list[0]) : "empty"))
}

const byUpdated = Model.filterAndSort(records, { scope: "browse", sort: "updated" })
check("updated: newest first",
  byUpdated.every((r, i) => i === 0 || (byUpdated[i - 1].repoUpdatedAt || "") >= (r.repoUpdatedAt || "")))

// The four count-based sorts must not all produce the same order, or one of
// them is silently falling through to another.
const tops = Object.keys(orderedBy).map(
  s => Model.filterAndSort(records, { scope: "browse", sort: s })[0].id)
check("the count sorts differ from each other", new Set(tops).size > 1, tops.join(" / "))

console.log("relevance leads while searching")
const searched = Model.filterAndSort(records, { scope: "all", query: "spotify", sort: "name" })
check("a search still ranks matches by relevance, not the chosen sort",
  searched.length > 0 && searched[0].name.toLowerCase().includes("spotify"),
  searched.length ? searched[0].name : "no results")
check("the chosen sort still breaks ties within equal relevance",
  (() => {
    const q = Model.filterAndSort(records, { scope: "browse", query: "bar", sort: "stars" })
    for (let i = 1; i < q.length; i++) {
      if (q[i - 1]._score === q[i]._score && q[i - 1].stars < q[i].stars) return false
    }
    return true
  })())

// ---------------------------------------------------------------- metadata

console.log("metadata carried for installed plugins")
for (const p of thirdParty) {
  const r = byId[p.id]
  check(`${p.id}: entry points present`, Object.keys(r.entryPoints).length > 0,
    JSON.stringify(r.entryPoints))
  check(`${p.id}: git branch present`, r.gitBranch === p.git.branch, r.gitBranch)
  check(`${p.id}: git head present`, r.gitHead === p.git.head)
  check(`${p.id}: source dir present`, r.sourceDir.endsWith(p.id))
}

// ---------------------------------------------------------------- pinning

console.log("reviewed commits and preview paths")
const listedNow = records.filter(r => r.listed)
const withCommit = listedNow.filter(r => r.reviewedCommit)
console.log(`  ${withCommit.length} of ${listedNow.length} listings carry a reviewed commit`)
check("most listings carry a reviewed commit", withCommit.length > listedNow.length * 0.9,
  `${withCommit.length}/${listedNow.length}`)
check("every reviewed commit is a full 40-char sha",
  withCommit.every(r => /^[0-9a-f]{40}$/.test(r.reviewedCommit)),
  withCommit.filter(r => !/^[0-9a-f]{40}$/.test(r.reviewedCommit)).slice(0, 2).map(r => r.id).join(","))

// Preview paths must stay relative: the QML never builds a URL, and pm-preview
// refuses anything that tries to introduce a host or escape the asset tree.
const withThumb = records.filter(r => r.thumb)
check("preview paths are relative, never absolute URLs",
  withThumb.every(r => !/^https?:\/\//.test(r.thumb)),
  withThumb.filter(r => /^https?:\/\//.test(r.thumb)).slice(0, 2).map(r => r.thumb).join(","))
check("preview paths stay inside the asset tree",
  withThumb.every(r => /^assets\/img\//.test(r.thumb) && !r.thumb.includes("..")),
  withThumb.filter(r => !/^assets\/img\//.test(r.thumb)).slice(0, 2).map(r => r.thumb).join(","))
check("detail screenshots are relative too",
  records.filter(r => r.shot).every(r => !/^https?:\/\//.test(r.shot)))

// The installed copy of this plugin should itself be pinnable: its head is a
// real sha the metadata pane can compare against.
for (const p of thirdParty) {
  const r = byId[p.id]
  if (r.gitManaged) {
    check(`${p.id}: git head is a full sha`, /^[0-9a-f]{40}$/.test(r.gitHead), r.gitHead)
  }
}

// ---------------------------------------------------------------- filtering

console.log("filterAndSort")
const browse = Model.filterAndSort(records, { scope: "browse", sort: "stars" })
check("browse is non-empty", browse.length > 100, String(browse.length))
check("browse sorted by stars descending",
  browse.every((r, i) => i === 0 || browse[i - 1].stars >= r.stars))
check("browse only contains listed plugins", browse.every(r => r.listed))

const installedScope = Model.filterAndSort(records, { scope: "installed" })
check("installed scope excludes first-party", installedScope.every(r => !r.firstParty))
check("installed scope matches inventory", installedScope.length === thirdParty.length,
  `${installedScope.length} vs ${thirdParty.length}`)

const byName = Model.filterAndSort(records, { scope: "all", query: "system monitor" })
check("exact-ish name search ranks the real plugin first",
  byName.length > 0 && byName[0].name.toLowerCase().includes("system monitor"),
  byName.length ? byName[0].name : "no results")

const noMatch = Model.filterAndSort(records, { scope: "all", query: "zzzznotathingzzzz" })
check("nonsense query returns nothing", noMatch.length === 0)

const catFiltered = Model.filterAndSort(records, { scope: "browse", category: "Widgets" })
check("category filter holds", catFiltered.every(r => r.category === "Widgets"))
check("category filter is a real subset", catFiltered.length > 0 && catFiltered.length < browse.length)

const kindFiltered = Model.filterAndSort(records, { scope: "all", kind: "panel" })
check("kind filter holds", kindFiltered.every(r => r.kinds.indexOf("panel") !== -1))

const verifiedOnly = Model.filterAndSort(records, { scope: "browse", verifiedOnly: true })
check("verified filter holds", verifiedOnly.every(r => r.verified || r.firstParty))
check("verified is a strict subset", verifiedOnly.length < browse.length)

const sortedByName = Model.filterAndSort(records, { scope: "browse", sort: "name" })
check("name sort is alphabetical",
  sortedByName.every((r, i) => i === 0 ||
    sortedByName[i - 1].name.toLowerCase() <= r.name.toLowerCase()))

console.log("categoriesOf / countsOf")
const cats = Model.categoriesOf(records, "browse")
check("categories found", cats.length > 3)
check("categories sorted by count", cats.every((c, i) => i === 0 || cats[i - 1].count >= c.count))
check("category counts sum to browse size",
  cats.reduce((a, c) => a + c.count, 0) === browse.length)

const counts = Model.countsOf(records)
check("counts.installed matches", counts.installed === thirdParty.length)
check("counts.updates matches the per-record flags",
  counts.updates === records.filter(r => r.updateAvailable).length)
check("counts.builtin matches", counts.builtin === firstParty.length)

// ---------------------------------------------------------------- perf

console.log("performance (search must keep up with typing)")
const t0 = process.hrtime.bigint()
for (const q of ["a", "ba", "bar", "batt", "batte", "battery"]) {
  Model.filterAndSort(records, { scope: "browse", query: q })
}
const perKeystroke = Number(process.hrtime.bigint() - t0) / 1e6 / 6
console.log(`  ${perKeystroke.toFixed(2)}ms per keystroke over ${records.length} records`)
check("search is under 20ms per keystroke", perKeystroke < 20, `${perKeystroke.toFixed(2)}ms`)

// ---------------------------------------------------------------- report

console.log(`\n${passed} passed, ${failed} failed`)
process.exit(failed === 0 ? 0 : 1)
