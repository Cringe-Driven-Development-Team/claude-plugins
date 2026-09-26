#!/usr/bin/env bash
# Проверки манифестов маркетплейса. version в plugin.json не задаём: без него Claude Code
# берёт версией коммит, и обновления скиллов доходят до всех после /plugin marketplace update.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FAILS=0

for f in "$ROOT"/plugins/*/.claude-plugin/plugin.json; do
  if jq -e 'has("version")' "$f" >/dev/null; then
    echo "  FAIL: ${f#"$ROOT"/} задаёт version — обновления не дойдут до пользователей"
    FAILS=$((FAILS + 1))
  fi
done
if jq -e '[.plugins[] | select(has("version"))] | length > 0' "$ROOT/.claude-plugin/marketplace.json" >/dev/null; then
  echo "  FAIL: marketplace.json задаёт version плагина"
  FAILS=$((FAILS + 1))
fi

if [ "$FAILS" -gt 0 ]; then echo "провалов: $FAILS"; exit 1; fi
echo "манифесты в порядке"
