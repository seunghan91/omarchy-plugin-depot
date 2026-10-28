import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "Model.js" as Model
import "I18n.js" as I18n

// Plugin manager: browse the Omarchy marketplace, install, update, enable,
// disable and remove shell plugins.
//
// Summon it with:
//   omarchy-shell shell toggle io.github.seunghan91.plugin-depot-ko
//
// Notes for anyone editing this:
//
// 1. THIS PANEL IS DESTROYED BY ITS OWN ACTIONS. Every omarchy plugin command
//    ends in `omarchy-shell shell rescanPlugins`, and that reload sets
//    `panelEntries = []` in shell.qml, destroying every panel delegate --
//    `keepLoaded` does not help, because an empty model has no delegate left to
//    evaluate it. Enabling a panel-kind plugin destroys it a second time, by
//    growing the array. So no QML property here may be treated as durable
//    across an action: nothing survives but the window.
//
//    Everything that must outlive a mutation is written to $XDG_RUNTIME_DIR by
//    bin/pm-job, which runs detached (a Quickshell Process would be killed with
//    its parent, and Process has no detach property). When the job finishes it
//    re-summons this panel with {"resume": "<jobId>"}, and open() rehydrates
//    from disk. saveUi()/restoreUi() carry the scroll position and selection
//    across that gap so the round-trip is invisible.
//
// 2. All parsing and filtering lives in Model.js and is tested under node
//    (`node test-model.js`, run against this machine's real catalog and real
//    installed plugins). This file is wiring and layout only.
//
// 3. Theme values are read declaratively (Color.*, Style.*). A theme switch
//    reassigns those singleton properties and every binding re-evaluates; a
//    value copied into a var in a function would freeze at the old theme.
//
// 4. The window is tiled by Hyprland at an arbitrary size unless the user adds
//    the window rule from the README, so the layout reflows: the sidebar and
//    the detail pane drop out as it narrows.
Item {
  id: root

  // ─────────────────────────────────────────────── plugin lifecycle
  // Injected by the host after construction (shell.qml:629-637), so these are
  // still null in Component.onCompleted. First use happens in open().
  property var shell: null
  property var manifest: null
  property bool closingFromHost: false

  // shell.qml reads `loader.item.opened` to decide what toggle does.
  readonly property bool opened: window.visible

  readonly property string pluginId: "io.github.seunghan91.plugin-depot-ko"
  // Newer Omarchy strips __sourceDir, __isFirstParty and __hostCapabilities
  // from the manifest before handing it to a third-party plugin, so this used
  // to resolve to "" there and every Process below was gated off, leaving the
  // catalogue, the installed list and the bar badge permanently empty. The
  // component's own file URL says where it lives and no host sanitising of the
  // manifest can take that away, so it is the fallback.
  readonly property string sourceDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir)
    : decodeURIComponent(String(Qt.resolvedUrl("."))
      .replace(/^file:\/\//, "")).replace(/\/$/, "")
  readonly property string binDir: sourceDir === "" ? "" : sourceDir + "/bin"
  readonly property string jobDir: Quickshell.env("XDG_RUNTIME_DIR") + "/io.github.seunghan91.plugin-depot-ko"

  function setting(name, fallback) {
    var d = manifest && manifest.panel && manifest.panel.defaults ? manifest.panel.defaults : null
    var v = d ? d[name] : undefined
    return v === undefined || v === null ? fallback : v
  }

  // Display language: the choice made in Settings, or the system locale on
  // "auto". Passed down to every child component as `lang`.
  readonly property string lang: I18n.resolve(settingsView.language, Qt.locale().name)
  onLangChanged: if (root.query !== "") root.applyFilter()
  function tr(s) { return I18n.tr.apply(null, [lang].concat(Array.prototype.slice.call(arguments))) }
  function trn(n, one, many) { return I18n.trn.apply(null, [lang].concat(Array.prototype.slice.call(arguments))) }

  function open(payloadJson) {
    closingFromHost = false

    var payload = {}
    try {
      payload = JSON.parse(payloadJson || "{}") || {}
    } catch (e) {
      payload = {}
    }

    // A resume means a job we started finished while we were dead. Adopt it so
    // the result is shown instead of silently vanishing.
    var resume = String(payload.resume || "")
    if (resume !== "") {
      root.jobId = resume
      root.restoreOnLoad = true
    }

    // Deep link: `omarchy-shell shell summon io.github.seunghan91.plugin-depot-ko '{"select":"<id>"}'`
    // opens straight to one plugin, so other tooling can hand the user off to
    // the thing they were reading about.
    var select = String(payload.select || "")
    if (select !== "") {
      root.selectedId = select
      root.scope = "all"
      root.restoreOnLoad = false
      root.scrollToSelected = true
    }

    // `{"view":"settings"}` opens straight into Settings, so the Omarchy menu
    // or a keybinding can go there directly.
    var view = String(payload.view || "")
    if (view !== "") {
      root.showSettings = (view === "settings")
      if (view === "bar")
        root.setScope("bar")
    }

    // The drawer is a narrow-window affordance; it should never be found
    // already open on a fresh summon.
    root.sidebarOpen = false
    window.visible = true
    root.reload(false)
    Qt.callLater(function () {
      if (!root.restoreOnLoad)
        root.focusForView()
    })
  }

  // Host-initiated close: flip visibility without telling the host, which
  // already knows.
  function close() {
    closingFromHost = true
    window.visible = false
    closingFromHost = false
  }

  // User-initiated close: tell the shell so its open-panel map stays
  // consistent and the next toggle behaves.
  function requestClose() {
    saveUi()
    if (shell && typeof shell.hide === "function")
      shell.hide(root.pluginId)
    else
      window.visible = false
  }

  // Probed by bin/pm-job over `omarchy-shell shell call` to find out whether
  // its re-summon actually landed. While this panel is unloaded the shell
  // answers the literal string "unknown" on our behalf.
  function resumeStatus(wantJobId) {
    if (String(wantJobId || "") !== root.jobId)
      return "miss"
    return window.visible ? "shown" : "hidden"
  }

  // ─────────────────────────────────────────────── data
  property var catalog: null
  property var localState: null
  property var updateState: null
  property var statsState: null
  property var records: []
  property var rows: []

  property bool loadingCatalog: false
  property bool loadingLocal: false
  property bool checkingUpdates: false
  property bool loadingStats: false
  readonly property bool busy: loadingCatalog || loadingLocal || checkingUpdates
  property string loadError: ""

  // ─────────────────────────────────────────────── view state
  property string scope: "browse"
  property string query: ""
  property string category: ""
  property string sortBy: "stars"
  property bool verifiedOnly: false
  property string selectedId: ""
  property bool restoreOnLoad: false
  property bool scrollToSelected: false
  property bool showSettings: false
  // Only meaningful while the window is too narrow for the inline column.
  property bool sidebarOpen: false

  readonly property var selected: {
    if (root.selectedId === "")
      return null
    for (var i = 0; i < root.rows.length; i++)
      if (root.rows[i].id === root.selectedId)
        return root.rows[i]
    // Still show a selection that the current filter excludes -- e.g. after
    // installing something while the Browse filter is on Updates.
    for (var j = 0; j < root.records.length; j++)
      if (root.records[j].id === root.selectedId)
        return root.records[j]
    return null
  }

  readonly property var counts: root.records.length ? Model.countsOf(root.records) : ({
    installed: 0, updates: 0, enabled: 0, builtin: 0, browse: 0
  })

  readonly property var scopes: [
    { key: "browse", label: root.tr("Browse"), count: root.counts.browse },
    { key: "installed", label: root.tr("Installed"), count: root.counts.installed },
    { key: "updates", label: root.tr("Updates"), count: root.counts.updates },
    { key: "enabled", label: root.tr("Enabled"), count: root.counts.enabled },
    { key: "builtin", label: root.tr("Built-in"), count: root.counts.builtin },
    { key: "all", label: root.tr("Everything"), count: root.records.length },
    { key: "bar", label: root.tr("Bar layout"), count: 0 }
  ]

  readonly property var categories: root.records.length
    ? Model.categoriesOf(root.records, root.scope) : []

  // ─────────────────────────────────────────────── previews
  // No Image in this plugin ever points at a remote URL. Rows ask for a
  // catalogue-relative path, bin/pm-preview fetches it from the fixed origin
  // under byte, time, dimension and concurrency limits, and only the validated
  // local file is displayed. Requests are batched on a short timer so scrolling
  // does not spawn a process per row.
  property var previewCache: ({})
  property var previewPending: ({})
  property var previewQueue: []
  property int previewRevision: 0

  function requestPreview(rel) {
    if (!rel || root.binDir === "")
      return
    if (root.previewCache[rel] !== undefined || root.previewPending[rel] === true)
      return
    root.previewPending[rel] = true
    root.previewQueue.push(rel)
    previewTimer.restart()
  }

  // previewRevision is passed in by callers purely so the binding re-evaluates
  // when a batch lands; the value itself is unused.
  function previewSource(rel, revision) {
    if (!rel)
      return ""
    var local = root.previewCache[rel]
    return local ? "file://" + local : ""
  }

  Timer {
    id: previewTimer
    interval: 200
    onTriggered: root.flushPreviews()
  }

  Process {
    id: previewProc
    property var batch: []
    command: root.binDir === "" || batch.length === 0
      ? [] : [root.binDir + "/pm-preview"].concat(batch)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = ({})
        for (var k in root.previewCache)
          next[k] = root.previewCache[k]
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          if (!lines[i])
            continue
          var parts = lines[i].split("\t")
          if (parts.length === 2 && parts[1])
            next[parts[0]] = parts[1]
        }
        root.previewCache = next
        root.previewRevision++
      }
    }
    onExited: {
      // Anything the helper declined stays out of the cache; clearing it from
      // pending would only make the row ask again on every scroll.
      previewProc.batch = []
      if (root.previewQueue.length > 0)
        previewTimer.restart()
    }
  }

  function flushPreviews() {
    if (previewProc.running || root.previewQueue.length === 0 || root.binDir === "")
      return
    previewProc.batch = root.previewQueue.splice(0, 40)
    previewProc.running = true
  }

  // ─────────────────────────────────────────────── bar layout
  property var barState: null
  property bool loadingBar: false
  property bool barBusy: false
  property string barError: ""

  property bool barSnapshotTaken: false

  function reloadBar() {
    if (root.binDir === "")
      return
    root.loadingBar = true
    // The first read of the session also records the arrangement, so Undo
    // means "the bar as I found it" however many moves have happened since.
    barProc.snapshot = !root.barSnapshotTaken
    root.barSnapshotTaken = true
    barProc.running = true
  }

  // Bar edits are applied one at a time and the layout is read back after each
  // one, because the shell rewrites shell.json itself and the result of a move
  // is its business, not something to be predicted here.
  function runBarAction(args) {
    if (root.binDir === "" || root.barBusy)
      return
    root.barError = ""
    root.barBusy = true
    barActionProc.pending = args
    barActionProc.running = true
  }

  Process {
    id: barProc
    property bool snapshot: false
    command: root.binDir === "" ? []
      : (snapshot ? [root.binDir + "/pm-bar", "--snapshot"] : [root.binDir + "/pm-bar"])
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.loadingBar = false
        try {
          root.barState = JSON.parse(text || "null")
        } catch (e) {
          root.barState = null
        }
      }
    }
    onExited: root.loadingBar = false
  }

  Process {
    id: barActionProc
    property var pending: []
    command: root.binDir === "" || pending.length === 0
      ? [] : [root.binDir + "/pm-act"].concat(pending)
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var msg = String(text || "").trim()
        if (msg !== "")
          root.barError = I18n.raw(msg)
      }
    }
    onExited: function (exitCode) {
      if (exitCode !== 0 && root.barError === "")
        root.barError = I18n.later("That change could not be applied (exit %1).", exitCode)
      barActionProc.pending = []
      root.barBusy = false
      barReloadDelay.restart()
    }
  }

  Timer {
    id: barReloadDelay
    interval: 350
    onTriggered: {
      root.reloadBar()
      // A widget coming off the bar changes what is installed and enabled, so
      // the plugin list has to catch up too.
      root.refreshLocal()
    }
  }

  // ─────────────────────────────────────────────── job state
  property string jobId: ""
  property var job: null
  property string jobLog: ""
  property var pendingAction: null

  readonly property bool jobRunning: root.job !== null && root.job.state === "running"

  function reload(force) {
    if (root.binDir === "")
      return
    root.loadError = ""
    root.loadingCatalog = true
    catalogProc.forceRefresh = force === true
    root.forceUpdateCheck = force === true
    catalogProc.running = true
    root.loadingStats = true
    statsProc.forceRefresh = force === true
    statsProc.running = true
    root.refreshLocal()
  }

  // Local inventory and the update check are cheap and independent of the
  // catalog, so they are not sequenced behind it.
  function refreshLocal() {
    if (root.binDir === "")
      return
    root.loadingLocal = true
    localProc.running = true
    root.checkingUpdates = true
    updatesProc.running = true
  }

  // Pressing refresh means "ask upstream again", so the cached update check is
  // bypassed. Merely opening the panel is not a reason to hit the network once
  // per installed plugin.
  property bool forceUpdateCheck: false

  function rebuild() {
    root.records = Model.mergeState(root.catalog, root.localState, root.updateState, root.statsState)
    root.applyFilter()
    if (root.restoreOnLoad) {
      root.restoreOnLoad = false
      root.restoreUi()
    }
  }

  function applyFilter() {
    root.rows = Model.filterAndSort(root.records, {
      query: root.query,
      scope: root.scope,
      category: root.category,
      // Always the chosen sort: Model.filterAndSort puts relevance ahead of it
      // on its own while a query is present, so the control keeps working
      // during a search rather than being quietly ignored.
      sort: root.sortBy,
      verifiedOnly: root.verifiedOnly,
      // Search also matches a category by the name the sidebar shows.
      lang: root.lang
    })
    // Clamp rather than reset: a filter change that keeps the selection
    // visible should not throw the user back to the top.
    if (list.contentY > list.contentHeight)
      list.contentY = 0

    if (root.scrollToSelected && root.selectedId !== "") {
      for (var i = 0; i < root.rows.length; i++) {
        if (root.rows[i].id === root.selectedId) {
          root.scrollToSelected = false
          list.currentIndex = i
          // Deferred: positioning straight out of a model swap runs against
          // the view's old geometry.
          Qt.callLater(function () { list.positionViewAtIndex(i, ListView.Center) })
          break
        }
      }
    }
  }

  function chooseCategory(name) {
    root.category = root.category === name ? "" : name
    root.applyFilter()
    list.contentY = 0
    root.sidebarOpen = false
  }

  readonly property bool barView: root.scope === "bar"

  // Walk the scope list without reaching for the sidebar.
  function stepScope(direction) {
    var keys = []
    for (var i = 0; i < root.scopes.length; i++)
      keys.push(root.scopes[i].key)
    var at = keys.indexOf(root.scope)
    if (at < 0)
      at = 0
    var next = at + (direction > 0 ? 1 : -1)
    if (next < 0 || next >= keys.length)
      return
    root.setScope(keys[next])
  }

  // Where the keyboard should be pointing depends on what is on screen.
  //
  // The list is a search-first view, so the field takes focus and typing
  // filters, which is how the rest of Omarchy behaves. That also means bare
  // letters cannot be shortcuts there: PanelKeyCatcher is blocked while the
  // field has focus, so a letter types rather than acting. Global actions are
  // on Ctrl chords, which work either way.
  //
  // The bar view has nothing to type into, so focus goes to the content and
  // the bare keys hjkl, HJKL and x drive it.
  function focusForView() {
    if (root.barView || root.showSettings)
      content.forceActiveFocus()
    else
      searchField.forceActiveFocus()
  }

  onBarViewChanged: Qt.callLater(root.focusForView)
  onShowSettingsChanged: Qt.callLater(root.focusForView)

  function setScope(next) {
    // Settings is an overlay over the views, not one of them, so arriving
    // anywhere leaves it. Without this a destination chord pressed from
    // settings changed the view behind the overlay and looked like a dead key.
    root.showSettings = false
    if (next === "bar" && root.barState === null)
      root.reloadBar()
    if (root.scope === next)
      return
    root.scope = next
    root.category = ""
    root.applyFilter()
    list.contentY = 0
    root.sidebarOpen = false
  }

  function selectIndex(i) {
    if (i < 0 || i >= root.rows.length)
      return
    root.selectedId = root.rows[i].id
    list.currentIndex = i
    list.positionViewAtIndex(i, ListView.Contain)
  }

  // The one action the selected row is actually offering, or "" when it offers
  // none. Ctrl+Enter runs it, which is what finally makes install and update
  // reachable without the mouse. It still opens the confirmation, so the
  // modifier buys a step, never the commitment.
  function primaryVerb(r) {
    if (!r)
      return ""
    if (!r.installed)
      return r.installable ? "install" : ""
    return r.updateAvailable ? "update" : ""
  }

  function moveSelection(delta) {
    if (root.rows.length === 0)
      return
    // Starting from -1 means the first press lands on the first row rather
    // than on nothing.
    var i = (list.currentIndex < 0 ? (delta > 0 ? -1 : 0) : list.currentIndex) + delta
    if (i < 0)
      i = 0
    if (i >= root.rows.length)
      i = root.rows.length - 1
    root.selectIndex(i)
  }

  // ─────────────────────────────────────────────── actions

  // Nothing from the marketplace feed is ever executed. The catalog ships an
  // `installCommand` string and it is deliberately ignored: only the verb and
  // the repository URL cross into bin/pm-act, which rebuilds the argv itself.
  // Taking a widget off the bar deletes its layout entry, and that entry is
  // also what marks a plugin enabled. For a widget-only plugin that is simply
  // "remove from the bar". For one that also owns a panel it stops the panel
  // being summonable, so that case asks first.
  function confirmBarRemoval(id) {
    var widget = null
    if (root.barState && root.barState.sections) {
      for (var i = 0; i < root.barState.sections.length; i++) {
        var list = root.barState.sections[i].widgets
        for (var j = 0; j < list.length; j++)
          if (list[j].id === id)
            widget = list[j]
      }
    }
    if (!widget)
      return
    if (!widget.alsoDisablesPanel) {
      root.runBarAction(["bar-remove", id])
      return
    }
    root.pendingAction = {
      verb: "bar-remove",
      record: {
        id: id,
        name: widget.name,
        reviewedCommit: "",
        repo: "",
        verified: false,
        kinds: widget.kinds
      }
    }
  }

  // One place that decides what Esc means, so the key catcher, the search
  // field and the header button cannot disagree about it.
  // One ladder, climbed the same way from every view: leave whatever is
  // covering the list, innermost first, and close the window only when nothing
  // is. Escape used to skip the bar editor entirely, so the same key that
  // stepped out of settings closed the whole app from the bar.
  function dismiss() {
    if (root.pendingAction)
      root.pendingAction = null
    else if (root.sidebarOpen)
      root.sidebarOpen = false
    else if (root.showSettings)
      root.showSettings = false
    else if (window.detailTakesOver)
      root.selectedId = ""
    else if (root.barView)
      root.setScope("browse")
    else
      root.requestClose()
  }

  // Single-key shortcuts. Deliberately none of them change the system: the
  // destructive verbs stay behind a button and a confirmation, because a
  // stray keypress must never install or remove anything.
  function handleTextKey(t) {
    // Only reached when the search field does not have focus, which in practice
    // means the bar view. Everything global lives on a Ctrl chord instead, so
    // it keeps working while you are typing a search.
    if (!root.barView)
      return
    if (t === "H") barEditor.shiftSelected(-1, 0)
    else if (t === "L") barEditor.shiftSelected(1, 0)
    else if (t === "K") barEditor.shiftSelected(0, -1)
    else if (t === "J") barEditor.shiftSelected(0, 1)
  }

  function requestAction(verb, record) {
    if (root.jobRunning)
      return
    root.pendingAction = { verb: verb, record: record }
  }

  function confirmAction() {
    var pending = root.pendingAction
    if (!pending)
      return

    // Read the dialog's choice BEFORE dismissing it. `Confirm.action` is bound
    // to pendingAction, so clearing it first collapses chosenSha to "" and the
    // install is dropped on the floor with no error anywhere -- which is
    // exactly the silent no-op this used to produce.
    var chosen = confirmSheet.chosenSha
    root.pendingAction = null

    var record = pending.record
    var args = []
    if (pending.verb === "install") {
      // The sha the dialog settled on: the reviewed commit, or the current head
      // if the user explicitly chose it after being told it is unreviewed.
      var sha = chosen || record.reviewedCommit
      if (!sha) {
        root.loadError = I18n.later("No reviewed commit is published for %1, so it cannot be installed safely.",
          record.name)
        return
      }
      args = ["install", record.repo, record.id, sha]
    } else if (pending.verb === "update") {
      var target = chosen || record.reviewedCommit
      if (!target) {
        root.loadError = I18n.later("No reviewed commit is published for %1.", record.name)
        return
      }
      args = ["update", record.id, target]
    } else if (pending.verb === "bar-remove") {
      // Not a plugin install, so it does not go through the detached job
      // runner: nothing here destroys the panel mid-flight.
      root.runBarAction(["bar-remove", record.id])
      return
    } else {
      args = [pending.verb, record.id]
    }

    root.startJob(pending.verb, record.id, args)
  }

  function startJob(verb, subjectId, args) {
    if (root.binDir === "" || root.jobRunning)
      return

    // No Date.now(): a monotonic counter persisted in the job dir would be
    // nicer, but the id only has to be unique among live jobs, and the panel's
    // own object address is not stable across the destruction this job causes.
    root.jobSeq = root.jobSeq + 1
    var id = "job-" + root.jobSeq + "-" + verb + "-" + subjectId.replace(/[^A-Za-z0-9_-]/g, "")

    root.selectedId = subjectId
    root.saveUi()
    root.jobId = id
    root.job = { id: id, verb: verb, state: "running", exit: null }
    root.jobLog = ""

    // Detached on purpose: this panel is about to be destroyed by the very
    // command it is starting.
    Quickshell.execDetached(["bash", "-lc", 'exec "$@"', "bash",
      root.binDir + "/pm-job", root.pluginId, root.jobDir, id].concat(args))
  }

  property int jobSeq: 0

  function dismissJob() {
    root.jobId = ""
    root.job = null
    root.jobLog = ""
    root.refreshLocal()
  }

  // ─────────────────────────────────────────────── ui state across a restart

  function saveUi() {
    if (root.jobDir === "")
      return
    uiFile.setText(JSON.stringify({
      scope: root.scope,
      query: root.query,
      category: root.category,
      sortBy: root.sortBy,
      verifiedOnly: root.verifiedOnly,
      selectedId: root.selectedId,
      contentY: list.contentY,
      jobSeq: root.jobSeq
    }))
  }

  // Set while restoreUi() is writing state back, so handlers can tell a
  // restored value from something the user just did.
  property bool restoring: false

  function restoreUi() {
    var saved = null
    try {
      saved = JSON.parse(uiFile.text() || "null")
    } catch (e) {
      saved = null
    }
    if (!saved)
      return
    root.restoring = true
    root.scope = String(saved.scope || "browse")
    root.query = String(saved.query || "")
    root.category = String(saved.category || "")
    root.sortBy = String(saved.sortBy || "stars")
    root.verifiedOnly = saved.verifiedOnly === true
    root.selectedId = String(saved.selectedId || "")
    root.jobSeq = Number(saved.jobSeq || 0)
    searchField.text = root.query
    root.applyFilter()
    if (saved.contentY !== undefined)
      Qt.callLater(function () { list.contentY = Number(saved.contentY) || 0 })
    root.restoring = false
  }

  // ─────────────────────────────────────────────── processes (read-only)

  Process {
    id: catalogProc
    property bool forceRefresh: false
    command: root.binDir === "" ? []
      : (forceRefresh ? [root.binDir + "/pm-catalog", "--refresh"] : [root.binDir + "/pm-catalog"])
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.loadingCatalog = false
        try {
          root.catalog = JSON.parse(text || "null")
        } catch (e) {
          root.catalog = null
          root.loadError = I18n.later("The marketplace catalog could not be parsed.")
        }
        if (root.catalog && root.catalog.ok === false)
          root.loadError = root.catalog.error
            ? I18n.raw(String(root.catalog.error)) : I18n.later("The marketplace is unreachable.")
        root.rebuild()
      }
    }
    onExited: function (exitCode) {
      root.loadingCatalog = false
      if (exitCode !== 0 && root.loadError === "")
        root.loadError = I18n.later("Could not read the marketplace catalog (exit %1).", exitCode)
    }
  }

  Process {
    id: statsProc
    property bool forceRefresh: false
    command: root.binDir === "" ? []
      : (forceRefresh ? [root.binDir + "/pm-stats", "--refresh"] : [root.binDir + "/pm-stats"])
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.loadingStats = false
        try {
          root.statsState = JSON.parse(text || "null")
        } catch (e) {
          root.statsState = null
        }
        root.rebuild()
      }
    }
    // Hearts are decoration. If the engagement API is unreachable the panel
    // must still browse and install, so a failure here is not a load error.
    onExited: root.loadingStats = false
  }

  Process {
    id: localProc
    command: root.binDir === "" ? [] : [root.binDir + "/pm-local"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.loadingLocal = false
        try {
          root.localState = JSON.parse(text || "null")
        } catch (e) {
          root.localState = null
        }
        root.rebuild()
      }
    }
    onExited: root.loadingLocal = false
  }

  Process {
    id: updatesProc
    command: root.binDir === "" ? []
      : (root.forceUpdateCheck ? [root.binDir + "/pm-updates", "--refresh"]
                               : [root.binDir + "/pm-updates"])
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.checkingUpdates = false
        try {
          root.updateState = JSON.parse(text || "null")
        } catch (e) {
          root.updateState = null
        }
        root.rebuild()
      }
    }
    onExited: root.checkingUpdates = false
  }

  // ─────────────────────────────────────────────── job files

  FileView {
    id: uiFile
    path: root.jobDir === "" ? "" : root.jobDir + "/ui.json"
    printErrors: false
    atomicWrites: false
  }

  FileView {
    id: jobFile
    path: root.jobId === "" ? "" : root.jobDir + "/" + root.jobId + ".json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var next = null
      try {
        next = JSON.parse(text() || "null")
      } catch (e) {
        next = null
      }
      if (next) {
        var wasRunning = root.job && root.job.state === "running"
        root.job = next
        // The plugin list only reflects the change once the job is finished.
        if (wasRunning && next.state !== "running")
          root.refreshLocal()
      }
    }
    onLoadFailed: {
      // Normal at the very start of a job: pm-job has not written the file yet.
    }
  }

  FileView {
    id: logFile
    path: root.jobId === "" ? "" : root.jobDir + "/" + root.jobId + ".log"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.jobLog = text() || ""
    onLoadFailed: root.jobLog = root.jobLog
  }

  // watchChanges is an accelerator, not a guarantee -- the poll is the
  // authority while a job is in flight, which is what omarchy's own CLIs do.
  Timer {
    running: root.jobId !== "" && root.jobRunning
    interval: 250
    repeat: true
    onTriggered: {
      jobFile.reload()
      logFile.reload()
    }
  }

  // ─────────────────────────────────────────────── window

  FloatingWindow {
    id: window

    // Stable and unique: a Quickshell toplevel always reports class
    // org.quickshell, so the title is the only thing a Hyprland window rule can
    // match on. Never put dynamic content here.
    title: "Plugin Depot"
    color: Color.background

    implicitWidth: 1180
    implicitHeight: 820
    // No maximumSize: it makes Hyprland float the window unpredictably
    // depending on the user's current tiling. No maximized: Omarchy suppresses
    // client maximize for every window (default/hypr/windows.lua).
    minimumSize: Qt.size(420, 360)

    onVisibleChanged: {
      if (!visible && !root.closingFromHost)
        root.requestClose()
    }

    // Above `wide` the detail sits beside the list. Below it there is no room
    // for two columns, so selecting a plugin swaps the list out for the detail
    // and the detail grows a Back button -- master-detail, rather than a click
    // that appears to do nothing because the pane it fills is off-layout.
    readonly property bool wide: width >= 900
    readonly property bool showSidebar: width >= 700
    readonly property bool detailTakesOver: !wide && root.selectedId !== ""

    // Omarchy is keyboard-first, so the panel is too. PanelKeyCatcher is the
    // shell's own dispatcher: it takes keys before descendants (Keys.priority
    // BeforeItem), which is what lets arrows drive a cursor instead of being
    // eaten by the list's own scrolling. `blocked` hands keys back to the
    // search field while it has focus, so typing still types.
    //
    // The rule every binding below follows: a key means the same thing in
    // every view. Earlier it did not, and the footer had to label the same
    // chord two different ways depending on where you stood.
    //
    //   arrows, hjkl   move the cursor inside this view, never between views
    //   enter          activate what the cursor is on
    //   ctrl+enter     run the action that item offers, if it offers one
    //   tab, shift+tab next and previous view, from every view
    //   ctrl+b u i ,   destinations: always the same place, never a toggle
    //   ctrl+g         show or hide the sidebar, which is a panel not a place
    //   esc            leave whatever is covering the list, innermost first,
    //                  and close the window only when nothing is
    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: searchField.activeFocus || root.pendingAction !== null

      // No Keys.onPressed here. PanelKeyCatcher declares that handler on its
      // own root, and declaring it again at the use site REPLACES it, killing
      // every signal below. Modifiers are not available through those signals,
      // so a widget is moved with uppercase HJKL, which arrives as textKey.

      onMoveRequested: function (dx, dy) {
        if (root.showSettings)
          return
        if (root.barView) {
          barEditor.moveCursor(dx, dy)
          return
        }
        // Left and right walk the sidebar's scopes when it is on screen, so the
        // whole app is reachable without touching the list.
        // Arrows move the cursor inside the current view and never between
        // views, which is what Tab is for. Left is the one spatial exception:
        // on a narrow window the detail has replaced the list, so left walks
        // back out of it to where the list was.
        if (dx < 0 && window.detailTakesOver) {
          root.selectedId = ""
          return
        }
        if (dy !== 0)
          root.moveSelection(dy)
      }
      onActivateRequested: {
        if (root.barView) {
          barEditor.activateCursor()
          return
        }
        // Enter on a row is "show me this", never "install this". An action
        // that changes the system stays behind its own button and dialog.
        if (root.rows.length > 0 && list.currentIndex >= 0)
          root.selectedId = root.rows[list.currentIndex].id
      }
      onTabRequested: function (direction) { root.stepScope(direction) }
      onDeleteRequested: {
        if (root.barView)
          barEditor.removeCursorWidget()
      }
      onCloseRequested: root.dismiss()
      onTextKey: function (t) { root.handleTextKey(t) }

    // Ctrl chords rather than bare letters. A Shortcut fires regardless of
    // which item has focus, so these keep working while a search is being
    // typed -- which bare letters cannot, because the text field swallows them.
    // Destinations, never toggles. Ctrl+B used to mean "bar" from the list and
    // "back" from the bar, so one key had two meanings depending on where it
    // was pressed, and the hint footer had to label it two different ways.
    // Each of these now lands in the same place from everywhere, and Escape is
    // the only key that goes back.
    Shortcut { sequences: ["Ctrl+B"]; onActivated: root.setScope("bar") }
    Shortcut { sequences: ["Ctrl+G"]; onActivated: root.sidebarOpen = !root.sidebarOpen }
    Shortcut { sequences: ["Ctrl+U"]; onActivated: root.setScope("updates") }
    Shortcut { sequences: ["Ctrl+I"]; onActivated: root.setScope("installed") }
    Shortcut { sequences: ["Ctrl+,"]; onActivated: root.showSettings = true }
    Shortcut {
      sequences: ["Ctrl+Return", "Ctrl+Enter"]
      enabled: !root.barView && !root.showSettings && root.pendingAction === null
      onActivated: {
        var verb = root.primaryVerb(root.selected)
        if (verb !== "")
          root.requestAction(verb, root.selected)
      }
    }
    Shortcut {
      sequences: ["Ctrl+R", "F5"]
      onActivated: {
        root.reload(true)
        if (root.barView)
          root.reloadBar()
      }
    }
    Shortcut {
      sequences: ["Ctrl+F", "Ctrl+L"]
      onActivated: {
        if (root.barView)
          root.setScope("browse")
        searchField.forceActiveFocus()
        searchField.selectAll()
      }
    }

    Item {
      id: content
      anchors.fill: parent
      focus: true

      // Only what PanelKeyCatcher does not already cover. Esc, the arrows,
      // Enter, Space, x and every plain letter arrive through its signals, so
      // handling them again here would fire them twice.
      Keys.onPressed: function (event) {
        if (event.key === Qt.Key_F5
            || (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier))) {
          root.reload(true)
          if (root.barView)
            root.reloadBar()
          event.accepted = true
        } else if (event.key === Qt.Key_F11) {
          window.fullscreen = !window.fullscreen
          event.accepted = true
        } else if (event.key === Qt.Key_PageDown) {
          root.moveSelection(10)
          event.accepted = true
        } else if (event.key === Qt.Key_PageUp) {
          root.moveSelection(-10)
          event.accepted = true
        }
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.spacing.panelPadding
        spacing: Style.spacing.lg

        // ───────────────────────────────── header
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.controlGap

          Button {
            // Only when the inline column cannot fit. Opens the same switcher
            // as a drawer over the list.
            visible: !window.showSidebar && !root.showSettings
            iconText: "\u2630"
            tooltipText: root.tr("Views and categories")
            selected: root.sidebarOpen
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.spacing.controlGap
            onClicked: root.sidebarOpen = !root.sidebarOpen
          }

          Text {
            text: "Plugin Depot"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            textFormat: Text.PlainText
          }

          Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            textFormat: Text.PlainText
            // The rest of this row is fixed width: the title, a 320px search
            // field and two buttons. At the width Hyprland hands this panel
            // there is no slack left at all, so this text elided to "312..."
            // and read as a rendering fault. It appears only where it fits,
            // and none of what it says is unavailable elsewhere: the counts
            // are in the sidebar and a load error also fills the detail pane.
            visible: window.width >= 980 && text !== ""
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            text: {
              if (root.loadError !== "")
                return root.tr(root.loadError)
              if (root.busy)
                return root.tr("Loading...")
              var bits = []
              if (root.counts.updates > 0)
                bits.push(root.trn(root.counts.updates, "%1 update available", "%1 updates available"))
              if (root.catalog && root.catalog.stale)
                bits.push(root.tr("offline copy"))
              return bits.join("  ·  ")
            }
          }

          TextField {
            id: searchField
            Layout.preferredWidth: Math.min(Style.space(320), window.width * 0.4)
            placeholderText: root.tr("Search plugins")
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            foreground: Color.foreground
            onTextChanged: {
              root.query = text
              // On a narrow window the detail has replaced the list, so a
              // search the user cannot see is filtering a hidden view. Drop
              // back to the results. Guarded, because restoreUi() also sets
              // this text and must not throw away the selection it just
              // restored.
              if (!root.restoring && window.detailTakesOver)
                root.selectedId = ""
              root.applyFilter()
            }
            // The field keeps focus so typing continues to filter; only the
            // selection moves. That is what a search box over a list should do.
            Keys.onDownPressed: root.moveSelection(1)
            Keys.onUpPressed: root.moveSelection(-1)
            Keys.onReturnPressed: {
              if (root.rows.length > 0 && list.currentIndex >= 0)
                root.selectedId = root.rows[list.currentIndex].id
            }
            Keys.onEscapePressed: {
              // Clearing a search is the first thing Esc does while typing;
              // beyond that it unwinds like everywhere else.
              if (text !== "") {
                text = ""
              } else {
                content.forceActiveFocus()
                root.dismiss()
              }
            }
          }

          Button {
            text: root.busy ? "..." : root.tr("Refresh")
            tooltipText: root.tr("Re-fetch the marketplace catalog and re-check for updates (F5)")
            fontSize: Style.font.bodySmall
            enabled: !root.busy
            onClicked: root.reload(true)
          }

          Button {
            text: root.showSettings ? root.tr("Done") : root.tr("Settings")
            tooltipText: root.showSettings
              ? root.tr("Back to the plugin list") : root.tr("Where this sits in the bar, and how often it checks for updates")
            fontSize: Style.font.bodySmall
            selected: root.showSettings
            onClicked: root.showSettings = !root.showSettings
          }

        }

        // ───────────────────────────────── body
        RowLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: Style.spacing.lg

          // sidebar, inline when there is room for a column
          Sidebar {
            lang: root.lang
            Layout.preferredWidth: Style.space(180)
            Layout.fillHeight: true
            visible: window.showSidebar && !window.detailTakesOver && !root.showSettings
            scopes: root.scopes
            categories: root.categories
            scope: root.scope
            category: root.category
            onScopeChosen: function (key) { root.setScope(key) }
            onCategoryChosen: function (name) { root.chooseCategory(name) }
          }

          // list
          ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumWidth: Style.space(260)
            spacing: Style.spacing.sm
            visible: !window.detailTakesOver && !root.showSettings && !root.barView

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.controlGap
              visible: !root.barView

              // The sidebar carries the scope switcher, but it needs 700px and
              // the window is tiled at whatever Hyprland gives it — commonly
              //621px, where the sidebar is hidden and every scope but Browse
              // became unreachable. This is the same switcher in the space that
              // is always on screen.
              Dropdown {
                Layout.preferredWidth: Math.min(Style.space(190), window.width * 0.32)
                Layout.alignment: Qt.AlignVCenter
                visible: !window.showSidebar
                showLabel: false
                label: root.tr("View")
                fontFamily: Style.font.family
                options: root.scopes.map(function (s) {
                  return {
                    value: s.key,
                    label: s.count > 0 ? s.label + "  " + s.count : s.label
                  }
                })
                value: root.scope
                onChanged: function (v) { root.setScope(v) }
              }

              Text {
                // The scope dropdown next to this already shows the view and
                // its count when the sidebar is hidden, so this would only
                // repeat it into a row that has no space to spare.
                visible: window.showSidebar || root.category !== ""
                text: root.category !== ""
                  ? root.trn(root.rows.length, "%1 plugin in %2", "%1 plugins in %2", root.tr(root.category))
                  : root.trn(root.rows.length, "%1 plugin", "%1 plugins")
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                textFormat: Text.PlainText
                Layout.fillWidth: true
                elide: Text.ElideRight
              }

              Button {
                visible: root.scope === "browse" || root.scope === "all"
                text: root.verifiedOnly ? root.tr("Verified only") : root.tr("All listings")
                tooltipText: root.tr("The marketplace marks a listing verified once its source has been reviewed")
                fontSize: Style.font.caption
                selected: root.verifiedOnly
                onClicked: {
                  root.verifiedOnly = !root.verifiedOnly
                  root.applyFilter()
                }
              }

              Dropdown {
                Layout.preferredWidth: Math.min(Style.space(200), window.width * 0.3)
                Layout.alignment: Qt.AlignVCenter
                showLabel: false
                label: root.tr("Sort")
                options: Model.sortOptions().map(function (o) { return { value: o.value, label: root.tr(o.label) } })
                value: root.sortBy
                fontFamily: Style.font.family
                onChanged: function (v) {
                  if (!Model.isSort(v))
                    return
                  root.sortBy = v
                  root.applyFilter()
                  list.contentY = 0
                }
              }
            }

            ListView {
              id: list
              Layout.fillWidth: true
              Layout.fillHeight: true
              clip: true
              // Mandatory at this row count: without it, scrolling the catalog
              // constructs a delegate per row (measured 2198 vs 9) and restarts
              // a network request for every thumbnail it throws away.
              reuseItems: true
              cacheBuffer: 400
              model: root.rows
              spacing: Style.spacing.xxs
              currentIndex: -1
              boundsBehavior: Flickable.StopAtBounds

              delegate: PluginRow {
                lang: root.lang
                required property var modelData
                required property int index
                width: ListView.view.width
                record: modelData
                previewFile: root.previewSource(modelData.thumb, root.previewRevision)
                onRecordChanged: root.requestPreview(record ? record.thumb : "")
                selected: root.selectedId === modelData.id
                onClicked: {
                  root.selectedId = modelData.id
                  list.currentIndex = index
                }
              }

              Text {
                anchors.centerIn: parent
                width: parent.width - Style.space(40)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: root.rows.length === 0 && !root.busy
                textFormat: Text.PlainText
                color: Color.muted
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
                text: {
                  if (root.loadError !== "")
                    return root.tr(root.loadError)
                  if (root.query !== "")
                    return root.tr("Nothing matches “%1”", root.query)
                  if (root.scope === "updates")
                    return root.tr("Every installed plugin is up to date.")
                  if (root.scope === "installed")
                    return root.tr("No third-party plugins installed yet.\nBrowse the marketplace to add one.")
                  return root.tr("Nothing to show.")
                }
              }
            }
          }

          // detail
          Detail {
            lang: root.lang
            Layout.fillWidth: window.detailTakesOver
            Layout.preferredWidth: window.detailTakesOver
              ? -1 : Math.min(Style.space(400), window.width * 0.38)
            Layout.fillHeight: true
            visible: (window.wide || window.detailTakesOver) && !root.showSettings && !root.barView
            record: root.selected
            jobRunning: root.jobRunning
            previewFile: root.previewSource(root.selected ? root.selected.shot : "", root.previewRevision)
            onRecordChanged: root.requestPreview(record ? record.shot : "")
            showBack: window.detailTakesOver
            onBack: root.selectedId = ""
            onAct: function (verb) { root.requestAction(verb, root.selected) }
          }

          BarLayout {
            id: barEditor
            lang: root.lang
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.barView && !root.showSettings
            barData: root.barState
            busy: root.barBusy
            onMoveWidget: function (id, section, index) {
              root.runBarAction(["bar-move", id, section, String(index)])
            }
            onPutWidget: function (id, section, index) {
              root.runBarAction(["bar-put", id, section, String(index)])
            }
            onRemoveWidget: function (id) { root.confirmBarRemoval(id) }
            onRevertLayout: root.runBarAction(["bar-restore"])
            // Keep the cursor on something real when the view first opens.
            onBarDataChanged: if (barEditor.selectedId === "") barEditor.moveCursor(0, 0)
          }

          // Settings replaces the whole body rather than sitting beside it:
          // on a narrow window there is no room for a fourth column, and it is
          // a mode you leave, not a pane you glance at.
          Settings {
            id: settingsView
            lang: root.lang
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.showSettings
            binDir: root.binDir
            cacheDir: root.jobDir
            pluginId: root.pluginId
          }
        }

        // ───────────────────────────────── key hints
        Text {
          Layout.fillWidth: true
          // Wrapped, not elided: a truncated list of shortcuts is worse than
          // one that takes two lines, and at a tiled width it always truncated.
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          maximumLineCount: 3
          color: Util.alpha(Color.foreground, 0.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          // Only the keys that do something here, and the action key only when
          // the selected row is actually offering one. A hint for a key that
          // does nothing is what made the old footer read as broken.
          text: {
            if (root.barView)
              return root.tr("hjkl or arrows move the cursor   HJKL move the widget   enter place   x remove   tab change view   ctrl+r refresh   esc back")
            if (root.showSettings)
              return root.tr("tab change view   esc back")
            var verb = root.primaryVerb(root.selected)
            return root.tr("type to search   \u2191\u2193 select   enter open")
              + (verb === "" ? "" : "   " + root.tr("ctrl+enter %1", root.tr(verb)))
              + "   " + root.tr("tab change view   ctrl+b bar   ctrl+u updates   ctrl+i installed   ctrl+g sidebar   ctrl+, settings   ctrl+r refresh   esc close")
          }
        }

        // ───────────────────────────────── job strip
        JobStrip {
          lang: root.lang
          Layout.fillWidth: true
          visible: root.job !== null
          job: root.job
          log: root.jobLog
          onDismiss: root.dismissJob()
        }
      }

      // ───────────────────────────────── views drawer
      // The inline column needs 180px it does not have on a tiled window, so
      // below that threshold the same switcher opens over the list instead.
      Item {
        anchors.fill: parent
        visible: root.sidebarOpen && !window.showSidebar && !root.showSettings

        Rectangle {
          anchors.fill: parent
          color: Color.menu.scrim
          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: root.sidebarOpen = false
          }
        }

        Rectangle {
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: Math.min(Style.space(230), parent.width * 0.7)
          color: Color.menu.background
          border.width: Style.normalBorderWidth
          border.color: Util.alpha(Color.menu.border, Style.normalBorderAlpha)

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {}
          }

          Sidebar {
            lang: root.lang
            anchors.fill: parent
            anchors.margins: Style.spacing.panelPadding
            scopes: root.scopes
            categories: root.categories
            scope: root.scope
            category: root.category
            onScopeChosen: function (key) { root.setScope(key) }
            onCategoryChosen: function (name) { root.chooseCategory(name) }
          }
        }
      }

      // ───────────────────────────────── confirmation
      Confirm {
        id: confirmSheet
        lang: root.lang
        anchors.fill: parent
        visible: root.pendingAction !== null
        action: root.pendingAction
        binDir: root.binDir
        onConfirmed: root.confirmAction()
        onCancelled: root.pendingAction = null
      }
    }
    }
  }
}
