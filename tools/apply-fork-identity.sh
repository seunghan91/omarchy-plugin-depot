#!/bin/bash
# Re-apply what makes this fork the Korean edition, on top of whatever upstream
# just merged in. Idempotent: running it twice changes nothing the second time.
#
#   - its own plugin id, so it installs beside upstream Plugin Depot and keeps
#     its own cache, job and snapshot directories
#   - its own display name in the menu and bar settings
#   - Korean when the language setting is Auto (Omarchy itself runs en_US)
#
# The window title stays "Plugin Depot" so floating-window rules written for
# upstream keep matching.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

UPSTREAM_ID="io.github.omarcodehub.plugin-manager"
FORK_ID="io.github.seunghan91.plugin-depot-ko"

# Code only. Docs keep upstream's id where they talk about upstream.
{ git grep -l -F "$UPSTREAM_ID" -- '*.qml' '*.js' 'bin/*' manifest.json || true; } | while read -r f; do
  sed -i.bak "s/${UPSTREAM_ID//./\\.}/$FORK_ID/g" "$f" && rm -f "$f.bak"
done

jq --arg id "$FORK_ID" '
  .id = $id
  | .name = "Plugin Depot (한국어)"
  | .author = "seunghan91 (Plugin Depot: OmarCodeHub)"
  | .description = "Omarchy 마켓을 한국어로 둘러보고 셸 플러그인을 설치·업데이트·켜기·끄기·제거합니다"
  | .homepage = "https://github.com/seunghan91/omarchy-plugin-depot"
  | .panel.displayName = "Plugin Depot (한국어)"
  | .panel.description = "플러그인 관리자: 마켓 둘러보기, 설치, 업데이트, 제거"
  | .barWidget.displayName = "Plugin Depot (한국어)"
  | .barWidget.description = "Plugin Depot 한국어판을 열고, 플러그인 업데이트가 있으면 개수를 표시합니다"
' manifest.json >manifest.json.tmp && mv manifest.json.tmp manifest.json

sed -i.bak 's/^var fallbackLanguage = "en"$/var fallbackLanguage = "ko"/' I18n.js && rm -f I18n.js.bak
grep -q '^var fallbackLanguage = "ko"$' I18n.js || { echo "fallbackLanguage not found in I18n.js" >&2; exit 1; }

if git grep -q -F "$UPSTREAM_ID" -- '*.qml' '*.js' 'bin/*' manifest.json; then
  echo "upstream id still present:" >&2
  git grep -n -F "$UPSTREAM_ID" -- '*.qml' '*.js' 'bin/*' manifest.json >&2
  exit 1
fi
echo "fork identity applied ($FORK_ID)"
