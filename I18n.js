.pragma library

// Display-string translation.
//
// The English source string is the key: `tr(lang, "Install")`. English needs no
// table, a string with no entry falls back to English, and a string reworded
// upstream simply shows in English until its translation catches up, rather
// than breaking. Placeholders are %1, %2, ... so each language keeps its own
// word order.
//
// Components hold a `lang` property that Panel passes down, and call
// `I18n.tr(lang, ...)` from a local `tr()` so bindings re-evaluate when the
// language changes.

var languages = ["auto", "en", "ko"]

// Native names, shown untranslated in the language picker.
var languageNames = {
  "en": "English",
  "ko": "한국어"
}

// What "auto" lands on when the system locale has no table. A distribution that
// ships the panel to one audience can set this instead of patching resolve().
var fallbackLanguage = "ko"

var tables = {
  "ko": {
    "%1 option in shell.json": "shell.json 옵션 %1개",
    "%1 options in shell.json": "shell.json 옵션 %1개",
    "%1 plugin": "플러그인 %1개",
    "%1 plugin in %2": "%2 플러그인 %1개",
    "%1 plugins": "플러그인 %1개",
    "%1 plugins in %2": "%2 플러그인 %1개",
    "%1 update available": "업데이트 %1개 있음",
    "%1 updates available": "업데이트 %1개 있음",
    "%1d ago": "%1일 전",
    "%1mo ago": "%1개월 전",
    "%1y ago": "%1년 전",
    "12 hours": "12시간",
    "3 hours": "3시간",
    "ai": "AI",
    "All listings": "전체 목록",
    "All plugins": "전체 플러그인",
    "Always": "항상",
    "Appearance": "외관",
    "Auto": "자동",
    "Auto follows the system locale. Languages without a translation fall back to English.": "자동은 시스템 로캘을 따릅니다. 번역이 없는 언어는 영어로 표시합니다.",
    "Available": "설치 가능",
    "Back to the plugin list": "플러그인 목록으로 돌아갑니다",
    "Bar": "바",
    "bar": "바",
    "bar at the %1  ·  %2 placed  ·  %3 available": "바 위치 %1  ·  배치 %2  ·  미배치 %3",
    "Bar layout": "바 배치",
    "Bar widget": "바 위젯",
    "Bar widgets": "바 위젯",
    "Bar-remove failed (exit %1)": "바에서 빼기 실패 (종료 코드 %1)",
    "Bar-remove finished": "바에서 빼기 완료",
    "Bar-removing...": "바에서 빼는 중...",
    "bar-widget": "바 위젯",
    "Bars": "바",
    "bottom": "아래",
    "Browse": "둘러보기",
    "Built in": "기본 제공",
    "Built-in": "기본 제공",
    "built-in": "기본 제공",
    "builtin": "기본 제공",
    "by %1": "%1 제작",
    "By name": "이름순",
    "Cancel": "취소",
    "CATEGORIES": "카테고리",
    "Category": "카테고리",
    "CENTER": "가운데",
    "Centre": "가운데",
    "Check for updates": "업데이트 확인",
    "Checking what the repository points at now...": "저장소가 지금 가리키는 커밋을 확인하는 중...",
    "clean": "변경 없음",
    "Clone and enable this plugin": "이 플러그인을 복제하고 활성화",
    "Cloned from": "복제 원본",
    "community": "커뮤니티",
    "Compatibility failed": "호환성 실패",
    "Confirm": "확인",
    "Could not reach the repository: %1": "저장소에 연결할 수 없습니다: %1",
    "Could not reach this plugin's origin to check for updates.": "업데이트를 확인하려 했지만 이 플러그인의 origin에 연결할 수 없습니다.",
    "Could not read the current settings.": "현재 설정을 읽지 못했습니다.",
    "Could not read the marketplace catalog (exit %1).": "마켓 카탈로그를 읽지 못했습니다(종료 코드 %1).",
    "ctrl+enter %1": "ctrl+enter %1",
    "Delete this plugin from ~/.config/omarchy/plugins": "~/.config/omarchy/plugins에서 이 플러그인 삭제",
    "Desktop": "데스크톱",
    "Developer Tools": "개발 도구",
    "Disable": "끄기",
    "Disable %1?": "%1을(를) 끌까요?",
    "Disable failed (exit %1)": "끄기 실패 (종료 코드 %1)",
    "Disable finished": "끄기 완료",
    "disabled": "꺼짐",
    "Disabling...": "끄는 중...",
    "Dismiss": "닫기",
    "Done": "완료",
    "Drag a widget where you want it, or move the cursor with the arrows and press uppercase H, J, K or L to move the widget itself. x takes one off the bar.": "위젯을 원하는 곳으로 끌어 놓거나, 화살표로 커서를 옮긴 뒤 대문자 H, J, K, L로 위젯을 옮깁니다. x는 바에서 뺍니다.",
    "education": "교육",
    "empty": "비어 있음",
    "Enable": "켜기",
    "Enable %1?": "%1을(를) 켤까요?",
    "Enable failed (exit %1)": "켜기 실패 (종료 코드 %1)",
    "Enable finished": "켜기 완료",
    "Enabled": "켜짐",
    "Enabling...": "켜는 중...",
    "enter confirm    esc cancel": "enter 확인    esc 취소",
    "Entry points": "진입점",
    "esc cancel": "esc 취소",
    "Every installed plugin is up to date.": "설치한 플러그인이 모두 최신입니다.",
    "Everything": "전체",
    "Fetching the incoming changes...": "들어올 변경 사항을 가져오는 중...",
    "games": "게임",
    "Hardware": "하드웨어",
    "heart": "하트",
    "hearts": "하트",
    "hjkl or arrows move the cursor   HJKL move the widget   enter place   x remove   tab change view   ctrl+r refresh   esc back": "hjkl·화살표 커서 이동   HJKL 위젯 이동   enter 배치   x 제거   tab 보기 전환   ctrl+r 새로고침   esc 뒤로",
    "Hourly": "1시간",
    "How often the bar widget asks each installed plugin's origin whether it has moved. One lightweight ref lookup per plugin; nothing is downloaded.": "바 위젯이 설치한 플러그인마다 원본 저장소가 바뀌었는지 묻는 주기입니다. 플러그인당 가벼운 ref 조회 1회이며 아무것도 내려받지 않습니다.",
    "install": "설치",
    "Install": "설치",
    "Install %1?": "%1을(를) 설치할까요?",
    "Install failed (exit %1)": "설치 실패 (종료 코드 %1)",
    "Install finished": "설치 완료",
    "Install newest (unreviewed)": "최신 커밋 설치(미검토)",
    "Install reviewed": "검토된 커밋 설치",
    "Installed": "설치됨",
    "installed": "설치됨",
    "Installed at": "설치 위치",
    "Installed on this machine but not listed in the marketplace.": "이 컴퓨터에 설치돼 있지만 마켓에는 없는 플러그인입니다.",
    "Installing...": "설치 중...",
    "installs": "설치",
    "Keep it installed but stop loading it": "설치는 유지하고 불러오기만 중단",
    "Kids": "어린이",
    "kids": "어린이",
    "Kinds": "종류",
    "Language": "언어",
    "launcher": "런처",
    "Left": "왼쪽",
    "left": "왼쪽",
    "LEFT": "왼쪽",
    "Licence": "라이선스",
    "LISTING": "마켓 정보",
    "Listing": "등록 상태",
    "Load this plugin in the shell": "셸에서 이 플러그인 불러오기",
    "Loading...": "불러오는 중...",
    "locally modified": "로컬 수정됨",
    "Manual setup": "수동 설정",
    "media": "미디어",
    "Menu": "메뉴",
    "menu": "메뉴",
    "Menu + Bar widget": "메뉴 + 바 위젯",
    "Menus": "메뉴",
    "METADATA": "메타데이터",
    "missing": "없음",
    "Most installed": "설치순",
    "Most loved": "하트순",
    "Most starred": "스타순",
    "Most viewed": "조회순",
    "Never": "안 함",
    "no": "아니요",
    "No changes reported.": "변경 사항이 없습니다.",
    "No reviewed commit is published for %1, so it cannot be installed safely.": "%1에는 검토된 커밋이 없어 안전하게 설치할 수 없습니다.",
    "No reviewed commit is published for %1.": "%1에는 검토된 커밋이 없습니다.",
    "No third-party plugins installed yet.\nBrowse the marketplace to add one.": "설치한 외부 플러그인이 아직 없습니다.\n마켓을 둘러보고 추가하세요.",
    "no — this checkout is not the reviewed commit": "아니요 — 이 체크아웃은 검토된 커밋이 아닙니다",
    "not a git checkout": "git 체크아웃 아님",
    "NOT ON THE BAR": "바에 없음",
    "Nothing matches “%1”": "“%1”에 맞는 항목이 없습니다",
    "Nothing to show.": "표시할 항목이 없습니다.",
    "now       %1": "현재    %1",
    "offline copy": "오프라인 사본",
    "Omarchy will clone this repository into ~/.config/omarchy/plugins, validate its manifest, and enable it.": "Omarchy가 이 저장소를 ~/.config/omarchy/plugins에 복제하고 매니페스트를 검사한 뒤 활성화합니다.",
    "Other": "기타",
    "Overlay": "오버레이",
    "overlay": "오버레이",
    "Overlays": "오버레이",
    "panel": "패널",
    "Panel": "패널",
    "Panels": "패널",
    "Pinned": "고정",
    "Plugin": "플러그인",
    "Plugin id": "플러그인 ID",
    "Plugin page": "플러그인 페이지",
    "Position": "위치",
    "power-management": "전원 관리",
    "Productivity": "생산성",
    "Put the bar back the way it was when this view opened": "이 화면을 열었을 때의 바 배치로 되돌립니다",
    "Re-fetch the marketplace catalog and re-check for updates (F5)": "마켓 카탈로그를 다시 받고 업데이트를 다시 확인합니다(F5)",
    "Recently updated": "최근 업데이트순",
    "Refresh": "새로고침",
    "Remove": "제거",
    "Remove %1?": "%1을(를) 제거할까요?",
    "Remove failed (exit %1)": "제거 실패 (종료 코드 %1)",
    "Remove finished": "제거 완료",
    "Removing...": "제거 중...",
    "Repo updated": "저장소 갱신",
    "Repository": "저장소",
    "Review the incoming changes, then fast-forward this plugin": "들어올 변경 사항을 검토한 뒤 이 플러그인을 fast-forward",
    "reviewed  %1": "검토됨  %1",
    "Reviewed at": "검토된 커밋",
    "Right": "오른쪽",
    "right": "오른쪽",
    "RIGHT": "오른쪽",
    "Search plugins": "플러그인 검색",
    "security": "보안",
    "Select a plugin to see what it is and what you can do with it.": "플러그인을 선택하면 설명과 할 수 있는 작업이 나옵니다.",
    "service": "서비스",
    "Service": "서비스",
    "Service + Bar widget": "서비스 + 바 위젯",
    "Services": "서비스",
    "Settings": "설정",
    "Show in the bar": "바에 표시",
    "snapshot-verified": "스냅샷 검증됨",
    "Sort": "정렬",
    "star": "스타",
    "stars": "스타",
    "Status unknown": "상태 알 수 없음",
    "Stored on this plugin's entry in ~/.config/omarchy/shell.json, written through the omarchy bar commands.": "~/.config/omarchy/shell.json의 이 플러그인 항목에 저장하며 omarchy bar 명령으로 씁니다.",
    "Suite": "묶음",
    "System": "시스템",
    "system": "시스템",
    "tab change view   ctrl+b bar   ctrl+u updates   ctrl+i installed   ctrl+g sidebar   ctrl+, settings   ctrl+r refresh   esc close": "tab 보기 전환   ctrl+b 바   ctrl+u 업데이트   ctrl+i 설치됨   ctrl+g 사이드바   ctrl+, 설정   ctrl+r 새로고침   esc 닫기",
    "tab change view   esc back": "tab 보기 전환   esc 뒤로",
    "Tags": "태그",
    "That change could not be applied (exit %1).": "변경을 적용하지 못했습니다(종료 코드 %1).",
    "The bar icon is hidden and takes up no space. Open the manager from the Omarchy menu, a keybinding, or `omarchy-shell shell toggle %1`.": "바 아이콘을 숨기고 자리도 차지하지 않습니다. 관리자는 Omarchy 메뉴, 키 바인딩, `omarchy-shell shell toggle %1`로 엽니다.",
    "The bar widget will not poll on its own. The manager still checks every time you open it.": "바 위젯이 스스로 확인하지 않습니다. 관리자는 열 때마다 확인합니다.",
    "The checkout will be fast-forwarded to its origin and re-validated. If validation fails the update is rolled back.": "체크아웃을 origin으로 fast-forward한 뒤 다시 검사합니다. 검사에 실패하면 업데이트를 되돌립니다.",
    "The icon appears only while an installed plugin has an update waiting.": "설치한 플러그인에 대기 중인 업데이트가 있을 때만 아이콘이 나타납니다.",
    "The icon is always in the bar, with a count when updates are waiting.": "아이콘이 항상 바에 있고, 업데이트가 대기 중이면 개수를 표시합니다.",
    "The marketplace catalog could not be parsed.": "마켓 카탈로그를 해석하지 못했습니다.",
    "The marketplace has no reviewed commit for this listing, so there is nothing to pin to. Installing is not offered.": "마켓에 이 항목의 검토된 커밋이 없어 고정할 대상이 없습니다. 설치할 수 없습니다.",
    "The marketplace is unreachable.": "마켓에 연결할 수 없습니다.",
    "The marketplace lists this as verified: its source has been reviewed. A plugin still runs unsandboxed inside your shell process.": "마켓에서 검증됨으로 표시한 항목입니다. 소스를 검토했습니다. 그래도 플러그인은 샌드박스 없이 셸 프로세스 안에서 실행됩니다.",
    "The marketplace marks a listing verified once its source has been reviewed": "마켓은 소스 검토를 마친 항목을 검증됨으로 표시합니다",
    "The panel may close and reopen while this runs — that is the shell reloading its plugins.": "실행 중에 패널이 닫혔다 다시 열릴 수 있습니다. 셸이 플러그인을 다시 불러오는 과정입니다.",
    "The plugin stays installed but the shell stops loading it.": "플러그인은 설치된 채로 남고 셸이 더 이상 불러오지 않습니다.",
    "The plugin's directory is deleted and it is taken out of your shell layout. This cannot be undone from here.": "플러그인 디렉터리를 삭제하고 셸 레이아웃에서 뺍니다. 여기서는 되돌릴 수 없습니다.",
    "The repository is still at the commit the marketplace reviewed. Only that commit will be fetched.": "저장소가 아직 마켓이 검토한 커밋에 있습니다. 그 커밋만 가져옵니다.",
    "The shell will load this plugin.": "셸이 이 플러그인을 불러옵니다.",
    "This listing is unverified. A plugin runs as arbitrary, unsandboxed code inside your long-lived shell process — read its source before you enable it.": "미검증 항목입니다. 플러그인은 계속 실행 중인 셸 프로세스 안에서 샌드박스 없는 임의 코드로 실행됩니다. 켜기 전에 소스를 읽어 보십시오.",
    "This plugin's files have been edited locally, so an update cannot fast-forward. Revert the changes in %1 to update it.": "플러그인 파일을 로컬에서 수정해 업데이트를 fast-forward할 수 없습니다. 업데이트하려면 %1의 변경 사항을 되돌리십시오.",
    "This repository has moved since the marketplace reviewed it. The newer code has not been reviewed.": "마켓이 검토한 뒤 저장소가 바뀌었습니다. 새 코드는 검토되지 않았습니다.",
    "today": "오늘",
    "top": "위",
    "Tracking": "추적",
    "type to search   ↑↓ select   enter open": "입력해 검색   ↑↓ 선택   enter 열기",
    "Undo my changes": "변경 되돌리기",
    "Unlisted": "미등록",
    "unverified": "미검증",
    "Unverified listing": "미검증 항목",
    "update": "업데이트",
    "Update": "업데이트",
    "Update %1?": "%1을(를) 업데이트할까요?",
    "Update failed (exit %1)": "업데이트 실패 (종료 코드 %1)",
    "Update finished": "업데이트 완료",
    "update-unverified": "업데이트 미검증",
    "Updates": "업데이트",
    "Updating...": "업데이트 중...",
    "verified": "검증됨",
    "Verified by the marketplace": "마켓 검증됨",
    "Verified only": "검증됨만",
    "View": "보기",
    "view": "조회",
    "views": "조회",
    "Views and categories": "보기와 분류",
    "When updates wait": "업데이트 대기 시",
    "Where this sits in the bar, and how often it checks for updates": "바 위치와 업데이트 확인 주기를 정합니다",
    "Which section of the bar the icon sits in.": "아이콘이 놓이는 바 구역입니다.",
    "Which section the icon would sit in, if it were shown.": "표시한다면 아이콘이 놓일 바 구역입니다.",
    "widget": "위젯",
    "Widget": "위젯",
    "Widgets": "위젯",
    "workspaces": "워크스페이스",
    "yes": "예",
    "yes — at the reviewed commit": "예 — 검토된 커밋입니다",
    "yesterday": "어제"
  }
}

// "auto" follows the system locale. Anything else is the fallback.
function resolve(setting, localeName) {
  var s = String(setting || "auto")
  if (s !== "auto")
    return tables[s] || s === "en" ? s : fallbackLanguage
  var l = String(localeName || "").toLowerCase()
  for (var code in tables) {
    if (l === code || l.indexOf(code + "_") === 0 || l.indexOf(code + "-") === 0)
      return code
  }
  return fallbackLanguage
}

function format(s, args) {
  return String(s).replace(/%(\d+)/g, function (m, n) {
    // A passed argument prints as string concatenation would, even when it is
    // undefined; only a missing one leaves the marker.
    var i = Number(n) - 1
    return i >= 0 && i < args.length ? String(args[i]) : m
  })
}

// A message kept in a string property until it is shown, such as an error set
// by a handler. tr() at display time translates it into whatever the language
// is then, so changing the language does not leave it stranded in the old one.
var LATER = "\u0001"

function later(source) {
  return LATER + JSON.stringify(Array.prototype.slice.call(arguments))
}

// Text from outside, such as a command's stderr, held the same way so that tr()
// shows it verbatim: it is an argument, never a key, and never mistaken for a
// held message. Empty stays empty, so `!== ""` checks still work.
function raw(text) {
  var s = String(text)
  return s === "" ? "" : later("%1", s)
}

// tr(lang, source, arg1, arg2, ...)
function tr(lang, source) {
  if (typeof source === "string" && source.charAt(0) === LATER) {
    var held = null
    try {
      held = JSON.parse(source.substring(1))
    } catch (e) {
      held = null
    }
    if (held && held.length)
      return tr.apply(null, [lang].concat(held))
  }
  var t = tables[lang]
  var s = t && Object.prototype.hasOwnProperty.call(t, source) ? t[source] : source
  return format(s, Array.prototype.slice.call(arguments, 2))
}

// trn(lang, n, singular, plural, arg2, ...): picks the English form by n, then
// translates that form. %1 is n.
function trn(lang, n, singular, plural) {
  var source = Number(n) === 1 ? singular : plural
  var args = [lang, source, n].concat(Array.prototype.slice.call(arguments, 4))
  return tr.apply(null, args)
}
