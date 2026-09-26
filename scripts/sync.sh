#!/usr/bin/env bash
# Синхронизирует скиллы в plugins/ с апстримами из upstream.json.
# Использование: scripts/sync.sh [--update]
#   без флага — копирует скиллы с закреплённых коммитов (результат воспроизводим);
#   --update  — сначала переставляет коммиты источников на HEAD их ветки по умолчанию.
# SYNC_GIT_BASE — префикс адреса репо источников (по умолчанию https://github.com/).
# При любой ошибке plugins/ и upstream.json не меняются: всё собирается во временном каталоге.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MANIFEST=$ROOT/upstream.json
GIT_BASE=${SYNC_GIT_BASE:-https://github.com/}

die() { echo "sync: $*" >&2; exit 1; }

update=0
case "${1:-}" in
  "") ;;
  --update) update=1 ;;
  *) die "неизвестный аргумент '$1'; использование: scripts/sync.sh [--update]" ;;
esac
for bin in git jq; do
  command -v "$bin" >/dev/null || die "не найден $bin"
done
[ -f "$MANIFEST" ] || die "нет $MANIFEST"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
manifest=$work/upstream.json
cp "$MANIFEST" "$manifest"

if [ "$update" = 1 ]; then
  for src in $(jq -r '.sources | keys[]' "$manifest"); do
    repo=$(jq -r --arg s "$src" '.sources[$s].repo' "$manifest")
    head=$(git ls-remote "$GIT_BASE$repo" HEAD | cut -f1)
    [ -n "$head" ] || die "не удалось получить HEAD $repo"
    jq --arg s "$src" --arg c "$head" '.sources[$s].commit = $c' "$manifest" > "$manifest.new"
    mv "$manifest.new" "$manifest"
  done
fi

source_field() { jq -r --arg s "$1" --arg f "$2" '.sources[$s][$f] // empty' "$manifest"; }

# Клонирует источник на закреплённый коммит (один раз за запуск) и печатает путь к клону.
checkout_source() {
  local src=$1 dir=$work/src/$1 repo commit
  if [ ! -d "$dir" ]; then
    repo=$(source_field "$src" repo)
    commit=$(source_field "$src" commit)
    [ -n "$repo" ] && [ -n "$commit" ] || die "источник '$src' не описан в sources"
    git clone -q "$GIT_BASE$repo" "$dir" 2>/dev/null || die "не удалось склонировать $repo"
    git -C "$dir" checkout -q "$commit" 2>/dev/null || die "в $repo нет коммита $commit"
  fi
  echo "$dir"
}

out=$work/out
targets=()                   # пути относительно plugins/, которые заменяются собранными
licenses=$work/licenses       # строки «<LICENSE относительно plugins/> <источник>» для pluginFiles
: > "$licenses"

count=$(jq '.skills | length' "$manifest")
for ((i = 0; i < count; i++)); do
  entry=$(jq -c ".skills[$i]" "$manifest")
  plugin=$(jq -r '.plugin // empty' <<<"$entry")
  src=$(jq -r '.source // empty' <<<"$entry")
  path=$(jq -r '.path // empty' <<<"$entry")
  path=${path%/}
  [ -n "$plugin" ] && [ -n "$src" ] && [ -n "$path" ] || die "skills[$i]: нужны plugin, source и path"
  [ -f "$ROOT/plugins/$plugin/.claude-plugin/plugin.json" ] ||
    die "skills[$i]: плагин '$plugin' не создан (нет plugins/$plugin/.claude-plugin/plugin.json)"

  dir=$(checkout_source "$src")
  repo=$(source_field "$src" repo)
  commit=$(source_field "$src" commit)
  lic=$(source_field "$src" license)
  lic=${lic:-LICENSE}
  [ -f "$dir/$lic" ] || die "skills[$i]: в $repo нет файла лицензии $lic"
  [ -f "$dir/$path/SKILL.md" ] || die "skills[$i]: в $repo@$commit нет $path/SKILL.md"

  rel=$plugin/skills/${path##*/}
  [ ! -e "$out/$rel" ] || die "skills[$i]: скилл $rel указан дважды"
  mkdir -p "$out/$rel"
  cp "$dir/$path/SKILL.md" "$out/$rel/"
  for sub in references scripts; do
    if [ -d "$dir/$path/$sub" ]; then
      cp -R "$dir/$path/$sub" "$out/$rel/"
    fi
  done
  cp "$dir/$lic" "$out/$rel/LICENSE"
  targets+=("$rel")

  pf_count=$(jq '.pluginFiles // [] | length' <<<"$entry")
  for ((j = 0; j < pf_count; j++)); do
    from=$(jq -r ".pluginFiles[$j].from // empty" <<<"$entry")
    to=$(jq -r ".pluginFiles[$j].to // empty" <<<"$entry")
    from=${from%/}
    to=${to%/}
    [ -n "$from" ] && [ -n "$to" ] || die "skills[$i].pluginFiles[$j]: нужны from и to"
    case "/$to/" in
      //* | */../* | /skills/* | /.claude-plugin/* | /LICENSE/)
        die "skills[$i].pluginFiles[$j]: недопустимый to '$to'" ;;
    esac
    [ -e "$dir/$from" ] || die "skills[$i].pluginFiles[$j]: в $repo@$commit нет $from"
    [ ! -e "$out/$plugin/$to" ] || die "skills[$i].pluginFiles[$j]: $plugin/$to указан дважды"
    mkdir -p "$(dirname "$out/$plugin/$to")"
    cp -R "$dir/$from" "$out/$plugin/$to"
    licrel=$(dirname "$plugin/$to")/LICENSE
    prev=$(awk -v k="$licrel" '$1 == k { print $2; exit }' "$licenses")
    if [ -n "$prev" ] && [ "$prev" != "$src" ]; then
      die "skills[$i].pluginFiles[$j]: в $licrel нужны лицензии двух источников — разнесите to по подкаталогам"
    fi
    cp "$dir/$lic" "$out/$licrel"
    echo "$licrel $src" >> "$licenses"
    targets+=("$plugin/$to" "$licrel")
  done
done

for rel in ${targets[@]+"${targets[@]}"}; do
  rm -rf "${ROOT:?}/plugins/$rel"
  mkdir -p "$(dirname "$ROOT/plugins/$rel")"
  cp -R "$out/$rel" "$ROOT/plugins/$rel"
done
cp "$manifest" "$MANIFEST"
echo "sync: скиллов синхронизировано: $count"
