.pragma library
.import "I18n.js" as I18n

// Pure data logic for the plugin manager: joining the marketplace catalog to
// what is installed, searching, filtering and sorting. No QML types are touched
// here so the whole file runs under node, which is how it is tested
// (`node test-model.js`). Panel.qml is wiring and layout only.

var MARKETPLACE_PAGE = "https://plugins.omarchy.org/plugin.html?id="

// ---------------------------------------------------------------- joining

// Repo URLs are the fallback join key when ids disagree, so they need to
// compare equal across the forms the same repository is written in:
// trailing .git, a trailing slash, http vs https, and case in the host.
function normalizeRepo(url) {
  if (!url || typeof url !== "string") return ""
  var s = url.trim().toLowerCase()
  s = s.replace(/^git\+/, "")
  s = s.replace(/^https?:\/\//, "")
  s = s.replace(/^git@([^:]+):/, "$1/")
  s = s.replace(/\.git$/, "")
  s = s.replace(/\/+$/, "")
  return s
}

// Builds the single list the UI renders from three inputs that each know only
// part of the story: the marketplace catalog (everything published), the local
// inventory (everything on this machine), and the update check (what is behind
// its origin). Every installed plugin appears whether or not it is listed, and
// every listed plugin appears whether or not it is installed.
function mergeState(catalog, local, updates, stats) {
  var catalogPlugins = (catalog && catalog.plugins) || []
  var localPlugins = (local && local.plugins) || []
  var updateList = (updates && updates.updates) || []
  // Engagement counts are keyed by plugin id and come from a separate API, so
  // they are simply absent for anything unlisted. Never let that read as zero
  // interest -- buildRecord keeps `hasStats` so the UI can say nothing at all.
  var statsById = (stats && stats.plugins) || {}
  // installNote is interned in the index: a handful of distinct strings and a
  // position per plugin, rather than the same sentence repeated 3000 times.
  var notes = (catalog && catalog.notes) || []

  var updateById = {}
  for (var u = 0; u < updateList.length; u++) updateById[updateList[u].id] = updateList[u]

  var localById = {}
  var localByRepo = {}
  for (var l = 0; l < localPlugins.length; l++) {
    var lp = localPlugins[l]
    localById[lp.id] = lp
    var lrepo = normalizeRepo(lp.git && lp.git.remote)
    if (lrepo) localByRepo[lrepo] = lp
  }

  var records = []
  var claimed = {}

  for (var c = 0; c < catalogPlugins.length; c++) {
    var cp = catalogPlugins[c]
    var match = localById[cp.id]
    if (!match) {
      var crepo = normalizeRepo(cp.repo)
      if (crepo && localByRepo[crepo]) match = localByRepo[crepo]
    }
    if (match) claimed[match.id] = true
    records.push(buildRecord(cp, match, match ? updateById[match.id] : null, statsById[cp.id], notes))
  }

  // Anything installed that the marketplace does not list: sideloaded plugins,
  // local clones of first-party widgets, and the first-party set itself.
  for (var k = 0; k < localPlugins.length; k++) {
    if (!claimed[localPlugins[k].id])
      records.push(buildRecord(null, localPlugins[k], updateById[localPlugins[k].id],
                               statsById[localPlugins[k].id], notes))
  }

  return records
}

function buildRecord(cat, local, update, stat, notes) {
  var installed = !!local
  var firstParty = installed ? !!local.firstParty : false

  // What counts as "an update is available" has to mean the same thing the
  // Update button does. The button installs the commit the marketplace
  // reviewed, so detection compares against that commit -- not against the
  // repository's branch head, which may have moved well past it. Comparing
  // against the head made an updated plugin sit in the Updates list forever,
  // because the head is exactly what we deliberately do not install.
  //
  // Anything the marketplace does not list has no reviewed commit to compare
  // with, so those fall back to the git check in bin/pm-updates.
  var reviewedCommit = (cat && cat.reviewedCommit) || ""
  var localHead = (local && local.git && local.git.head) || ""
  var behind
  if (installed && reviewedCommit && localHead)
    behind = localHead !== reviewedCommit
  else
    behind = !!(update && update.behind)

  var kinds = installed && local.kinds && local.kinds.length
    ? local.kinds.slice()
    : (cat && cat.kind ? kindsFromCatalogKind(cat.kind) : [])

  return {
    id: (local && local.id) || (cat && cat.id) || "",
    name: (cat && cat.name) || (local && local.name) || (local && local.id) || "",
    description: (local && local.description) || (cat && cat.description) || "",
    author: (local && local.author) || (cat && cat.author) || "",
    version: (local && local.version) || (cat && cat.version) || "",
    catalogVersion: (cat && cat.version) || "",
    // Categories come from the marketplace. Anything on disk the marketplace
    // does not list still needs one, and it must not reuse a scope's name or
    // the sidebar reads as though it has two "Installed" filters.
    category: (cat && cat.category) || (firstParty ? "Omarchy" : "Unlisted"),
    kinds: kinds,
    kindLabel: (cat && cat.kind) || kindLabelFromKinds(kinds),
    tags: (cat && cat.tags) || [],
    repo: (cat && cat.repo) || (local && local.git && local.git.remote) || (local && local.homepage) || "",
    // The marketplace's own page for this listing, which carries the full
    // description, screenshots and publisher notes.
    marketplaceUrl: cat && cat.id ? MARKETPLACE_PAGE + encodeURIComponent(cat.id) : "",
    stars: (cat && cat.stars) || 0,
    hearts: stat ? Number(stat.hearts || 0) : 0,
    views: stat ? Number(stat.views || 0) : 0,
    copies: stat ? Number(stat.copies || 0) : 0,
    hasStats: !!stat,
    verified: !!(cat && cat.verified),
    listed: !!cat,
    installable: !!(cat && cat.installable),
    builtIn: !!(cat && cat.builtIn) || firstParty,
    initials: (cat && cat.initials) || initialsFor((cat && cat.name) || (local && local.name) || "?"),
    accent: (cat && cat.accent) || "",
    // Relative paths, deliberately. Nothing here builds a remote URL: bin/pm-preview
    // owns the origin, fetches under limits and hands back a local file, and the
    // UI only ever displays that file.
    thumb: (cat && cat.thumb) || "",
    shot: (cat && cat.shot) || "",
    // The commit the marketplace actually reviewed. Installs and updates pin to
    // this rather than to whatever the branch head has since become.
    reviewedCommit: reviewedCommit,
    license: (cat && cat.license) || "",
    installNote: (cat && notes && cat.note !== undefined && cat.note !== null
      && notes[cat.note] !== undefined) ? notes[cat.note] : "",
    repoUpdatedAt: (cat && cat.repoUpdatedAt) || "",

    installed: installed,
    enabled: installed ? !!local.enabled : false,
    active: installed ? !!local.active : false,
    canDisable: installed ? !!local.canDisable : false,
    firstParty: firstParty,
    clonedFrom: (local && local.clonedFrom) || "",
    sourceDir: (local && local.sourceDir) || "",
    entryPoints: (local && local.entryPoints) || {},
    settingsSchema: (local && local.settingsSchema) || [],
    gitManaged: !!(local && local.git && local.git.managed),
    gitRemote: (local && local.git && local.git.remote) || "",
    gitBranch: (local && local.git && local.git.branch) || "",
    gitHead: (local && local.git && local.git.head) || "",
    gitDirty: !!(local && local.git && local.git.dirty),
    updateAvailable: behind,
    updateFrom: localHead ? localHead.substring(0, 7) : (update ? update.current : ""),
    // Where the Update button would actually take you.
    updateTo: reviewedCommit ? reviewedCommit.substring(0, 7) : (update ? update.remote : ""),
    updateStatus: update ? update.status : "",

    // Precomputed once so filtering 2200 records per keystroke stays cheap.
    haystack: [
      (cat && cat.name) || (local && local.name) || "",
      (local && local.id) || (cat && cat.id) || "",
      (local && local.author) || (cat && cat.author) || "",
      (local && local.description) || (cat && cat.description) || "",
      ((cat && cat.tags) || []).join(" "),
      (cat && cat.category) || ""
    ].join("   ").toLowerCase()
  }
}

function kindsFromCatalogKind(kind) {
  if (!kind) return []
  return String(kind).toLowerCase().split("+").map(function (k) {
    return k.trim().replace(/\s+/g, "-")
  }).filter(function (k) { return k.length > 0 })
}

// A kind label as shown, translated part by part so "Service + Bar widget"
// still finds "Service" and "Bar widget" in the table.
function kindLabelText(label, lang) {
  if (!label) return ""
  return String(label).split(" + ").map(function (k) {
    return I18n.tr(lang || "en", k)
  }).join(" + ")
}

// A manifest entry point is named in camelCase ("barWidget") where the kind it
// serves is kebab-case ("bar-widget"), so it is shown under the kind's label.
function entryPointKind(name) {
  return String(name || "").replace(/([a-z0-9])([A-Z])/g, "$1-$2").toLowerCase()
}

function kindLabelFromKinds(kinds) {
  if (!kinds || !kinds.length) return ""
  return kinds.map(function (k) {
    return k === "bar-widget" ? "Bar widget" : k.charAt(0).toUpperCase() + k.slice(1)
  }).join(" + ")
}

function initialsFor(name) {
  var parts = String(name || "?").replace(/[^A-Za-z0-9 ]/g, " ").trim().split(/\s+/)
  if (!parts.length || !parts[0]) return "??"
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase()
  return (parts[0][0] + parts[1][0]).toUpperCase()
}

// ---------------------------------------------------------------- searching

// Ranked rather than boolean: with 2200 plugins, an exact name match has to
// beat a description that merely mentions the word, or search is unusable.
function scoreMatch(record, needle, lang) {
  if (!needle) return 1
  var name = record.name.toLowerCase()
  var id = record.id.toLowerCase()
  if (name === needle || id === needle) return 1000
  if (name.indexOf(needle) === 0 || id.indexOf(needle) === 0) return 500
  if (name.indexOf(needle) !== -1) return 250
  if (record.author.toLowerCase().indexOf(needle) === 0) return 120
  for (var t = 0; t < record.tags.length; t++)
    if (String(record.tags[t]).toLowerCase() === needle) return 100
  if (record.haystack.indexOf(needle) !== -1) return 40
  // The sidebar shows a known category in the panel's language, so that name
  // has to find it as well as the catalogue's own.
  if (lang && record.category
    && I18n.tr(lang, record.category).toLowerCase().indexOf(needle) !== -1) return 40
  return 0
}

var SCOPES = {
  installed: function (r) { return r.installed && !r.firstParty },
  updates: function (r) { return r.updateAvailable },
  enabled: function (r) { return r.installed && r.enabled },
  builtin: function (r) { return r.firstParty },
  browse: function (r) { return r.listed },
  all: function () { return true }
}

function filterAndSort(records, opts) {
  opts = opts || {}
  var needle = String(opts.query || "").trim().toLowerCase()
  var scope = SCOPES[opts.scope] ? opts.scope : "browse"
  var inScope = SCOPES[scope]
  var category = opts.category || ""
  var kind = opts.kind || ""
  var verifiedOnly = !!opts.verifiedOnly
  var sort = opts.sort || "stars"

  var out = []
  for (var i = 0; i < records.length; i++) {
    var r = records[i]
    if (!inScope(r)) continue
    if (category && r.category !== category) continue
    if (kind && r.kinds.indexOf(kind) === -1) continue
    if (verifiedOnly && !r.verified && !r.firstParty) continue
    var score = scoreMatch(r, needle, opts.lang)
    if (score === 0) continue
    r._score = score
    out.push(r)
  }

  out.sort(function (a, b) {
    // While searching, relevance always leads, whatever sort is chosen: an
    // exact name match must not sit below a 2k-star plugin that merely mentions
    // the word. The chosen sort then orders everything of equal relevance, so
    // the control still does something useful during a search instead of being
    // silently overridden.
    if (needle && a._score !== b._score) return b._score - a._score

    if (sort === "stars" && a.stars !== b.stars) return b.stars - a.stars
    if (sort === "hearts" && a.hearts !== b.hearts) return b.hearts - a.hearts
    if (sort === "views" && a.views !== b.views) return b.views - a.views
    if (sort === "installs" && a.copies !== b.copies) return b.copies - a.copies
    if (sort === "updated") {
      var au = a.repoUpdatedAt || "", bu = b.repoUpdatedAt || ""
      if (au !== bu) return au < bu ? 1 : -1
    }
    var an = a.name.toLowerCase(), bn = b.name.toLowerCase()
    if (an !== bn) return an < bn ? -1 : 1
    return 0
  })
  return out
}

// The sort options the UI offers, defined here so the list and the comparator
// above cannot drift apart.
var SORTS = [
  { value: "stars", label: "Most starred" },
  { value: "hearts", label: "Most loved" },
  { value: "views", label: "Most viewed" },
  { value: "installs", label: "Most installed" },
  { value: "updated", label: "Recently updated" },
  { value: "name", label: "By name" }
]

// English labels; the view translates them where it draws them.
function sortOptions() {
  return SORTS.map(function (s) {
    return { value: s.value, label: s.label }
  })
}

// Every verb a job runs under. JobStrip builds its status line from the verb,
// so test-i18n.js builds the same strings from this list and checks that each
// has a translation, and checks that every verb the views start is listed.
var JOB_VERBS = ["install", "update", "remove", "enable", "disable", "bar-remove"]

// phase: "running" | "failed" | "finished". The key, untranslated; "failed"
// takes the exit code as %1.
function jobStatusKey(verb, phase) {
  var v = String(verb || "")
  var name = v.charAt(0).toUpperCase() + v.slice(1)
  if (phase === "running")
    return name.replace(/e$/, "") + "ing..."
  if (phase === "failed")
    return name + " failed (exit %1)"
  return name + " finished"
}

function isSort(value) {
  for (var i = 0; i < SORTS.length; i++)
    if (SORTS[i].value === value) return true
  return false
}

function categoriesOf(records, scope) {
  var inScope = SCOPES[scope] || SCOPES.all
  var seen = {}
  for (var i = 0; i < records.length; i++) {
    if (!inScope(records[i])) continue
    var c = records[i].category
    if (c) seen[c] = (seen[c] || 0) + 1
  }
  var out = []
  for (var key in seen) out.push({ name: key, count: seen[key] })
  out.sort(function (a, b) { return b.count - a.count || (a.name < b.name ? -1 : 1) })
  return out
}

function countsOf(records) {
  var c = { installed: 0, updates: 0, enabled: 0, builtin: 0, browse: 0 }
  for (var i = 0; i < records.length; i++) {
    var r = records[i]
    if (r.installed && !r.firstParty) c.installed++
    if (r.updateAvailable) c.updates++
    if (r.installed && r.enabled) c.enabled++
    if (r.firstParty) c.builtin++
    if (r.listed) c.browse++
  }
  return c
}

// ---------------------------------------------------------------- display

// Compact counts: 1200 -> "1.2k". Returns "" for zero so a caller can bind
// `visible` straight to the result being non-empty.
function formatCount(n) {
  if (!n) return ""
  if (n >= 1000) return (n / 1000).toFixed(n >= 10000 ? 0 : 1).replace(/\.0$/, "") + "k"
  return String(n)
}

function formatStars(n) {
  return formatCount(n)
}

// `now` is passed in rather than read from the clock so the result is a pure
// function of its inputs and can be tested.
function relativeDate(iso, now, lang) {
  if (!iso) return ""
  var then = Date.parse(iso)
  if (isNaN(then)) return ""
  var days = Math.floor((now - then) / 86400000)
  lang = lang || "en"
  if (days <= 0) return I18n.tr(lang, "today")
  if (days === 1) return I18n.tr(lang, "yesterday")
  if (days < 30) return I18n.tr(lang, "%1d ago", days)
  if (days < 365) return I18n.tr(lang, "%1mo ago", Math.floor(days / 30))
  return I18n.tr(lang, "%1y ago", Math.floor(days / 365))
}

function truncate(s, n) {
  s = String(s || "")
  return s.length > n ? s.slice(0, n - 1) + "…" : s
}
