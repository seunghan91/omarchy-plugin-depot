# Plugin Depot

A plugin manager for Omarchy, as a shell panel: browse the marketplace,
install, update, enable, disable and remove, without a terminal.

- **Browse** the official marketplace catalog with previews, search, categories,
  verification status, and how people are actually using each plugin: hearts,
  GitHub stars, views and installs. Sort by most starred, most loved, most
  viewed, most installed, recently updated or by name.

  While you are searching, relevance leads whatever sort is chosen. An exact
  name match should not sit below a 2k-star plugin that merely mentions the
  word. The chosen sort then orders everything of equal relevance, so the
  control still does something instead of being quietly overridden.
- **Install the exact commit the marketplace reviewed**, not whatever the branch
  head has since become. The confirmation names the repository, the reviewed
  commit, and whether it has moved since, checked live against the repository
  rather than taken on the feed's word. Only that one commit is fetched, so if the
  repository has moved on, the unreviewed code is never downloaded at all.
- **Update** with a read-only preview of the incoming commits and changed files
  *before* anything is applied.
- **Enable / disable / remove** anything installed.
- **Arrange the bar.** Omarchy can move and place bar widgets from the command
  line but shows the arrangement nowhere. The Bar layout view draws the three
  sections the way the bar is laid out, left to right, with every placed widget
  in order and everything installed but unplaced below. Drag a widget where you
  want it, or move the cursor with the arrows and press uppercase H, J, K or L
  to move the widget itself. **Undo my changes** puts the bar back the way it
  was when the view opened.
- **Keyboard first**, like the rest of Omarchy, and a key means the same thing
  in every view. Arrows and `hjkl` move the cursor inside the view you are in,
  `Tab` steps between views, the `Ctrl` chords are destinations rather than
  toggles, and `Esc` leaves whatever is covering the list before it closes the
  window. The footer names the keys that do something where you are standing.
  No action that changes the system is bound to a bare keypress.
- **Metadata** for what is on disk: kinds, entry points, settings, install
  path, and the git branch, commit and working-tree state, plus links out to
  the repository and to the plugin's marketplace page.
- A **bar widget** that opens the manager and carries a count when updates are
  waiting, or stays out of the bar entirely, from **Settings**.

## Opening it

Three ways in, so hiding the bar icon never strands it:

- the puzzle glyph in the bar (unless Settings has it hidden),
- **Omarchy menu → Setup → Plugins → Plugin Depot**, or just type "plugin
  manager" or "marketplace" into the menu's search,
- the shell directly:

```bash
omarchy-shell shell toggle io.github.omarcodehub.plugin-manager                            # open / close
omarchy-shell shell summon io.github.omarcodehub.plugin-manager '{"select":"acme.thing"}'  # deep link
omarchy-shell shell summon io.github.omarcodehub.plugin-manager '{"view":"settings"}'      # open Settings
```

The menu row lives in `~/.config/omarchy/extensions/omarchy-menu.jsonc`, which
is outside this plugin's directory, so `omarchy plugin remove` leaves it behind.
Delete it by hand if you uninstall.

`Esc` leaves whatever is covering the list first and closes the window only when
nothing is, so from the bar editor or from a detail pane it steps back rather
than quitting. Your window manager's close binding (`Super+W` under Omarchy's
defaults) always closes it outright. There is no close button in the header.

## Settings

**Settings** in the header covers where this plugin sits in your bar and how
often it looks for updates:

| | |
|---|---|
| **Show in the bar** | Always · only while updates are waiting · never |
| **Position** | Left · centre · right |
| **Check for updates** | Hourly · 3 hours · 12 hours · never |
| **Language** | Auto · English · 한국어 |

Choosing **Never** is safe because the app is still reachable from the Omarchy
menu. It hides the icon rather than taking the plugin out of the bar layout. That layout entry is also what marks the plugin *enabled*, and the shell
refuses to summon a plugin it thinks is disabled, so removing the entry would
hide the icon by making the app unreachable. An invisible widget collapses its bar
slot to zero width instead (verified: `debugBarGeometry` reports `w=0` against
`w=27` when shown), which costs nothing and keeps the app openable from the
menu, a keybinding, or `omarchy-shell shell toggle io.github.omarcodehub.plugin-manager`.

**Auto** follows the system locale. A language without a translation falls back
to English. Translations live in [`I18n.js`](I18n.js), keyed by the English
text, and `node test-i18n.js` checks that none is missing.

Text that comes from outside, such as plugin descriptions, git output and
command errors, is shown as it arrives. The one exception is the catalogue's
categories and plugin kinds: those with an entry in the table are shown
translated, and searching finds a category by either name.

Everything is stored inline on this plugin's entry in `shell.json` and written
through the `omarchy bar` commands, never by editing that file. The shell owns
it and rewrites it whenever the bar changes.

## Make the window float

Hyprland tiles this like any other window, and Omarchy makes every window
slightly transparent, which is unkind to a dense list. Both are fixed with
window rules. A Quickshell toplevel always reports `class = org.quickshell`,
so the title is the only usable selector. In `~/.config/hypr/hyprland.lua`:

```lua
o.window({ class = "^org\\.quickshell$", title = "^Plugin Depot$" }, { tag = "+plugin-depot-window" })
o.window({ tag = "plugin-depot-window" }, { float = true })
o.window({ tag = "plugin-depot-window" }, { center = true })
o.window({ tag = "plugin-depot-window" }, { size = { 1180, 760 } })
o.window({ tag = "plugin-depot-window" }, { tag = "-default-opacity" })
o.window({ tag = "plugin-depot-window" }, { opacity = "1 1" })
```

Without them the panel still works. It reflows instead: the sidebar drops below
700px, and below 900px there is no room for two columns, so selecting a plugin
swaps the list out for its details and the pane grows a **‹ All plugins**
button. `Esc`, or typing a new search, goes back.

## How it is put together

```
Panel.qml       the app: layout, state, and the four read-only loaders
PluginRow.qml   list delegate            Detail.qml   the right-hand pane
Confirm.qml     the confirmation dialog  JobStrip.qml the running-action strip
Settings.qml    bar placement + update-check preferences
BarLayout.qml   the bar arrangement editor
BarWidget.qml   bar launcher + update count
Model.js        all joining, searching, sorting  (pure, tested under node)
bin/            everything that touches the system
```

### The data

Seven helpers back the panel. Four are joined by plugin id, falling back to the repository URL:

| | |
|---|---|
| `bin/pm-catalog` | The official feed at `plugins.omarchy.org/catalog.json`, about 5.4MB, reduced to the ~2.1MB the UI reads. Cached under `$XDG_CACHE_HOME/io.github.omarcodehub.plugin-manager` with a conditional GET, so a refresh inside the feed's 10-minute `max-age` costs one 304. Falls back to the cached copy offline and says so. |
| `bin/pm-local` | What is actually installed: `omarchy plugin list --json` plus `omarchy-plugin-catalog` plus each plugin's own manifest (for version and author, which neither command reports) plus its git remote. |
| `bin/pm-updates` | `git ls-remote origin HEAD` per plugin, in parallel: one ref lookup each, no objects downloaded, nothing written to the checkout. Safe to run on a timer. Cached for 15 minutes, with `--refresh` to force a live check, because uncached this was the largest single cost of opening the panel. |
| `bin/pm-probe` | Read-only. Asks the repository, with `git ls-remote`, what it points at *now*, so the panel can compare that against the commit the catalogue says was reviewed. Two independent sources: the feed cannot quietly claim a repository has not moved. |
| `bin/pm-preview` | Fetches preview images from the marketplace's fixed origin into a local cache, under limits: no redirects, HTTPS only, a deadline, an announced-size rejection, a hard cap on bytes reaching disk, a real-image-and-sane-dimensions check, and bounded concurrency. The UI displays only the validated local file, and no `Image` in this plugin ever points at a remote URL. |
| `bin/pm-bar` | The bar as it is actually laid out: the three sections in order, what is installed but unplaced, and which widgets would take a panel down with them if removed. Read from the running shell rather than parsed from `shell.json` behind its writer. |
| `bin/pm-stats` | Hearts, views and installs from the marketplace's engagement API (`api.omarchyplugins.com/v1/stats`), which is where those live. They are not in the catalog file. It sends `no-store` and no ETag, so this caches locally on a short TTL instead. Decoration only: if it is down, everything else still works. |

Everything installed shows up whether or not the marketplace lists it, and
everything listed shows up whether or not it is installed.

### The part that looks over-engineered but is not

**This panel is destroyed by its own actions.** Every `omarchy plugin`
command ends by calling `omarchy-shell shell rescanPlugins`, and that reload
sets `panelEntries = []` in the shell, which destroys every panel. `keepLoaded`
does not save you, because an empty model has no delegate left to consult it.
Enabling a panel-kind plugin destroys it a second time by growing the array. A
Quickshell `Process` owned by the panel dies with its parent, and `Process` has
no detach property, so running an install directly from the panel would kill the
install halfway through and lose its output.

So mutations go out through `Quickshell.execDetached` to `bin/pm-job`, which
outlives the panel:

1. writes `$XDG_RUNTIME_DIR/io.github.omarcodehub.plugin-manager/<job>.json` and `<job>.log` as it goes,
   in place, never a temp file and a rename, which would swap the inode and
   drop the `FileView` watch,
2. runs the action through `bin/pm-act`,
3. re-summons the panel with `{"resume": "<job>"}` and keeps retrying until the
   live panel confirms via `resumeStatus`, because a summon that lands inside
   the reload window is silently dropped.

The panel saves its scope, search, selection and scroll position before starting
a job and restores them on the way back, so the round trip is close to
invisible. Nothing in the QML object is treated as durable across an action.

### Pinned installs

A repository can change after the marketplace reviews it, so approving a URL is
not approving code. Every install and update therefore names a full
40-character commit:

| Repository state | What happens |
|---|---|
| still at the reviewed commit | it is installed, no friction |
| moved past the review | both commits are shown. The reviewed one is the default, and taking the newer, unreviewed one is a separate, labelled choice |
| reviewed commit rewritten away | refused, because `git fetch` of that object fails, and a rewritten history is a red flag rather than a warning |
| no reviewed commit in the feed | install is not offered |

The fetch is `git fetch --depth 1 origin <sha>`, so only that object arrives.
Newer code is never downloaded. After checkout, `rev-parse HEAD` must equal the
requested sha before anything is validated or activated, and the whole thing is
staged in a dot-prefixed directory the registry ignores until it is verified.

An update moves to the newly reviewed commit and rolls back to the previous one
if the new tree fails validation. The detail pane's **Pinned** row says whether
what is on disk is still the reviewed commit.

This does not interfere with `omarchy plugin update` run from a terminal: a
shallow detached checkout still fast-forwards normally.

### Talking to the system

`bin/pm-act` is the only thing here that changes anything, and it takes a verb
plus validated arguments, never a command string. The marketplace feed ships an
`installCommand`, and it is deliberately ignored: only the repository URL is
taken from the feed, and the argv is rebuilt locally. A feed that is wrong or
compromised can therefore name a bad repository, which you still have to
approve with the URL in front of you, but it cannot name a command.

URLs are checked before use: `https://` only, no git options, no `ext::` or
other transport helpers, no scp-form, no local paths, and then handed to
Omarchy's own `omarchy-git-url-check`. Plugin ids must look like plugin ids and
must already exist under `~/.config/omarchy/plugins`. Every `omarchy` call gets
`--yes`, because there is no terminal for `gum` to prompt in and those commands
refuse rather than hang without it. The confirmation you actually see is the
dialog in the panel.

None of this makes a plugin safe. A plugin is arbitrary QML running unsandboxed
inside your long-lived shell process. The dialog shows the repository and the
marketplace's verdict so the decision is an informed one. It is still yours.

## Working on it

```bash
node test-model.js                       # 113 assertions against real live data
qmllint -I /usr/share/omarchy/shell *.qml
omarchy plugin validate .
```

`test-model.js` runs against this machine's real catalog and real installed
plugins rather than fixtures, so it fails when the upstream feed changes shape
instead of passing forever against a stale copy.

**After editing any `.qml` here, run `omarchy restart shell`.** Saving reloads
the plugin and closes the panel, but the shell can go on serving the previously
compiled component. You will otherwise chase a bug you have already fixed.

Two constraints worth knowing before changing the UI:

- The list delegate is deliberately anchor-based, not built from
  `RowLayout`/`ColumnLayout`. It is recycled (`reuseItems`) in a list whose model
  is reassigned several times per open, and with nested layouts a record swap
  changes children's implicit sizes mid-rearrange, so Qt floods the shell log
  with "Detected recursive rearrange".
- Thumbnails must keep `asynchronous: true` (the default is synchronous, which
  blocks the shell's UI thread on every fetch) and must not set `cache: false`
  (with recycling that re-downloads the same image every time it scrolls back
  into view).

## Installing it

```bash
omarchy plugin add https://github.com/OmarCodeHub/omarchy-marketplace.git --enable
```

## Removing it

```bash
omarchy plugin remove io.github.omarcodehub.plugin-manager
```

That leaves the menu row behind, because it lives outside the plugin directory.
Delete the `setup.plugin.manager` row from
`~/.config/omarchy/extensions/omarchy-menu.jsonc`.

## Versioning

The version in [`manifest.json`](manifest.json) is what the marketplace listing
shows, and it follows [semantic versioning](https://semver.org). Major for
something that used to work and no longer does, minor for a new user-visible
capability, patch for fixes and internals. What changed in each release is in
[CHANGELOG.md](CHANGELOG.md).

## Contributing

`main` is protected: work on a branch and open a pull request. See
[CONTRIBUTING.md](CONTRIBUTING.md) for the checks a change has to pass and for
the handful of constraints that are load-bearing rather than stylistic.

## License

MIT. See [LICENSE](LICENSE).
