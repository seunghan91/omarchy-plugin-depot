# Changelog

Notable changes to Plugin Depot. The version here is the one in
[`manifest.json`](manifest.json), which is what the marketplace listing shows.

This project follows [semantic versioning](https://semver.org):

| | when it goes up |
|---|---|
| **major** | something that was working stops working: a setting is removed, the plugin id changes, a documented entry point or command disappears |
| **minor** | a new user-visible capability |
| **patch** | fixes, performance and internals, with no new capability |

## Unreleased

### Added

- **Display language.** Every string the panel draws now goes through a small
  translation table (`I18n.js`), with Korean as the first language. **Settings
  → Language** picks Auto, English or 한국어; Auto follows the system locale
  and anything without a translation stays in English. The English source text
  is the key, so a string reworded here simply shows in English until its
  translation catches up. `node test-i18n.js` fails when a string in the code
  has no translation or a translation drops a placeholder.

## 1.1.1

### Fixed

- **The panel and the installed list could be empty on newer Omarchy.** The
  shell now strips `__sourceDir` from the manifest before handing it to a
  third-party plugin, and the panel used that to find its own `bin/` directory.
  It resolved to nothing, every helper process was gated off, and the
  marketplace, the installed list and the bar badge all stayed empty with no
  error anywhere. The bar widget had the same problem by a second route: a
  third-party widget is given a shell API object that has no plugin registry on
  it at all, so it could not reach its manifest either. Both now fall back to
  the component's own file URL, which no host sanitising can take away. Thanks
  to JMThomas00 for the report and the diagnosis.
- **The bar badge counted updates the Updates view then refused to show.** The
  badge asked whether origin had moved, while the panel has asked whether the
  reviewed commit has moved since 1.1.0. A plugin sitting exactly on its
  reviewed commit is up to date, so a badge would appear over an empty Updates
  list whenever any installed plugin's branch head ran ahead of its reviewed
  commit. The update check now answers the same question the panel does, and
  falls back to origin only for a plugin the marketplace does not list.

## 1.1.0

### Added

- **Bar layout editor.** Omarchy can move and place bar widgets from the command
  line but shows the arrangement nowhere. The new **Bar layout** view draws the
  three sections the way the bar is laid out, left to right, with every placed
  widget in order and everything installed but unplaced below it. Widgets can be
  dragged, or moved with the keyboard. **Undo my changes** puts the bar back the
  way it was when the view opened.
- **Keyboard navigation across the whole app**, not just the bar editor. Arrows
  and `hjkl` move the cursor, `Tab` steps between views, `Ctrl` chords go
  straight to a view, `Ctrl+Enter` runs whatever action the selected plugin is
  offering, and `Esc` steps back out of whatever is covering the list.
- **Drag and drop** for arranging the bar, alongside the keyboard.

### Changed

- **Every key now means the same thing in every view.** Four of them did not.
  `Ctrl+B` went to the bar from the list and back to the list from the bar, so
  the hint footer had to label one chord two ways. `Ctrl+,` was a toggle for the
  same reason. `Esc` stepped out of settings and out of the detail pane but had
  no rung for the bar editor, so from there it closed the whole window instead
  of going back. `Tab` changed the view from the list but did nothing from the
  bar or from settings. Destinations are now always destinations, `Esc` is the
  only key that goes back, and the model is written down rather than left to be
  inferred.
- The hint footer wraps instead of eliding, and names only the keys that do
  something in the view you are standing in.
- The update check is cached for fifteen minutes, with `--refresh` to force a
  live check. It had no cache at all and was costing 811ms of every open, all of
  it network. The same call now takes 14ms.
- The reduced catalogue index dropped from 2.7MB to 2.1MB. The install note was
  repeated across all 3,124 listings for six distinct strings, so the notes are
  interned and each listing carries an index into them. `observedCommit` was
  written into every record and read by nothing, so it is gone.
- The manifest now declares its license, so the marketplace listing names MIT
  rather than pointing at the repository.

### Fixed

- **The advertised single-key shortcuts did nothing.** The panel focuses the
  search field when it opens and the shell's key dispatcher is blocked while
  that field has focus, so every bare letter typed into the box and filtered the
  list. Pressing `b` did not go back, it searched for the letter b. Global
  actions moved onto `Ctrl` chords, which fire regardless of focus.
- The confirmation dialog had no keyboard handling at all, and the panel's
  dispatcher is deliberately blocked behind it, so every action that changes the
  system needed the mouse to finish or to back out of. `Enter` and `Esc` now
  work there.
- Clicking a bar widget could displace it onto the first widget in its column
  until something else was moved.
- The header status line rendered as a truncated fragment. The rest of that row
  is fixed width, so at the width Hyprland hands this panel there was no slack
  left for it at all.

## 1.0.0

First release. Browse the marketplace, install pinned to the reviewed commit,
update with a read-only diff first, enable, disable and remove, plus a bar
widget that carries a count when updates are waiting.
