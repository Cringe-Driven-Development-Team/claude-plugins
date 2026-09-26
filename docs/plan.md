# claude-plugins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Публичный репо `Cringe-Driven-Development-Team/claude-plugins` — маркетплейс `cdd` с плагинами `pulumi` (5 скиллов) и `ansible` (1 скилл), синхронизируемыми с апстримами скриптом, и переезд `infra` на него.

**Architecture:** Скиллы копируются из апстримов без правок скриптом `scripts/sync.sh` по манифесту `upstream.json` (источник → закреплённый коммит, скилл → плагин). Маркетплейс и плагины описаны вручную (`marketplace.json`, `plugin.json`), скиллы плагины находят сами в `skills/`. Репо орги подключают маркетплейс строкой в `.claude/settings.json`.

**Tech Stack:** bash, git, jq, Claude Code plugin marketplace, GitHub (`gh`).

**Spec:** `docs/design.md` (до создания репо — `/tmp/claude-1000/-mnt-f-Github-2026-H2-infra/ac9607f3-d6f2-4889-8563-2e9d2b29ec39/scratchpad/claude-plugins-design.md`)

## Global Constraints

- Репо: `Cringe-Driven-Development-Team/claude-plugins`, видимость public; локально `/mnt/f/Github/2026_H2/claude-plugins`, ветка `main`.
- Имя маркетплейса — `cdd`; плагины — `pulumi`, `ansible`.
- Апстримы и коммиты: `pulumi/agent-skills` `9b794aec9c4169f137285c2763c06064d247dd47`; `dirien/claude-skills` `22aaf94d59d53c88a5465bcb5434d309fae8787a`; `leogallego/claude-ansible-skills` `2c43de8f4b180342f05f5e670cc7e6e8ae359ec4`.
- Копируются только `SKILL.md`, `references/`, `scripts/` скилла и `LICENSE` источника; плюс `pluginFiles`. Никогда: `agents/`, `evals/`, `use_cases.yaml`, `mcp.json`.
- Скиллы апстрима не правятся руками — только через `sync.sh`.
- `sync.sh` зависит только от `bash`, `git`, `jq`; при любой ошибке рабочее дерево и `upstream.json` не меняются.
- `sync.sh` и тесты работают на bash 3.2 (macOS, коллега на MacBook): без `declare -A`, `mapfile`, `${x,,}`, `sed -i`, `sha256sum`.
- Собственные файлы репо — MIT; тексты на русском, как в остальных репо орги.
- Коммиты заканчиваются строкой `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

- `path` со слешем в конце (`skills/x/`) — имя скилла должно быть `x`, не пустое. Тест: `test_trailing_slash_path` (Task 2).
- Запуск `sync.sh` не из корня репо — пути должны разрешаться от расположения скрипта. Тест: `test_runs_from_other_cwd` (Task 2).
- `--update`, когда в новом HEAD апстрима скилл удалён — падение без изменения `upstream.json` и `plugins/`. Тест: `test_update_failure_keeps_manifest` (Task 2).
- Один и тот же скилл/путь указан дважды или источник не описан в `sources` — понятная ошибка, не молчаливая перезапись. Тесты: `test_duplicate_skill_fails`, `test_unknown_source_fails` (Task 2).
- В каталоге скилла остались файлы от прошлой версии апстрима — после синка их быть не должно (каталог заменяется целиком). Тест: `test_replaces_stale_files` (Task 2).

---

### Task 1: Каркас репо: манифесты, лицензия, спека

**Files:**
- Create: `/mnt/f/Github/2026_H2/claude-plugins/.claude-plugin/marketplace.json`
- Create: `/mnt/f/Github/2026_H2/claude-plugins/plugins/pulumi/.claude-plugin/plugin.json`
- Create: `/mnt/f/Github/2026_H2/claude-plugins/plugins/ansible/.claude-plugin/plugin.json`
- Create: `/mnt/f/Github/2026_H2/claude-plugins/LICENSE`
- Create: `/mnt/f/Github/2026_H2/claude-plugins/.gitignore`
- Create: `/mnt/f/Github/2026_H2/claude-plugins/docs/design.md` (копия спеки)
- Create: `/mnt/f/Github/2026_H2/claude-plugins/docs/plan.md` (копия этого плана)

**Interfaces:**
- Produces: каталоги `plugins/pulumi/`, `plugins/ansible/` с `.claude-plugin/plugin.json` — `sync.sh` (Task 2) требует их наличия.

- [ ] **Step 1: Инициализировать репо**

```bash
mkdir -p /mnt/f/Github/2026_H2/claude-plugins && cd /mnt/f/Github/2026_H2/claude-plugins
git init -q -b main
mkdir -p .claude-plugin plugins/pulumi/.claude-plugin plugins/ansible/.claude-plugin docs scripts tests
cp /tmp/claude-1000/-mnt-f-Github-2026-H2-infra/ac9607f3-d6f2-4889-8563-2e9d2b29ec39/scratchpad/claude-plugins-design.md docs/design.md
cp /tmp/claude-1000/-mnt-f-Github-2026-H2-infra/ac9607f3-d6f2-4889-8563-2e9d2b29ec39/scratchpad/claude-plugins-plan.md docs/plan.md
```

В `docs/design.md` заменить строку `Статус: на утверждении.` на `Статус: утверждено.`

- [ ] **Step 2: `.claude-plugin/marketplace.json`**

```json
{
  "name": "cdd",
  "owner": {
    "name": "Cringe-Driven-Development-Team"
  },
  "metadata": {
    "description": "Плагины Claude Code организации Cringe-Driven-Development-Team: отобранные скиллы из апстримов и свои"
  },
  "plugins": [
    {
      "name": "pulumi",
      "source": "./plugins/pulumi",
      "description": "Pulumi: лучшие практики, ComponentResource, разбор упавших операций, обновление провайдеров, работа с CLI и стейтом"
    },
    {
      "name": "ansible",
      "source": "./plugins/ansible",
      "description": "Ansible: ревью ролей и плейбуков по Red Hat CoP good practices"
    }
  ]
}
```

- [ ] **Step 3: `plugin.json` обоих плагинов**

`plugins/pulumi/.claude-plugin/plugin.json`:
```json
{
  "name": "pulumi",
  "version": "1.0.0",
  "description": "Pulumi: лучшие практики, ComponentResource, разбор упавших операций, обновление провайдеров, работа с CLI и стейтом. Скиллы из pulumi/agent-skills и dirien/claude-skills, см. upstream.json."
}
```

`plugins/ansible/.claude-plugin/plugin.json`:
```json
{
  "name": "ansible",
  "version": "1.0.0",
  "description": "Ansible: ревью ролей и плейбуков по Red Hat CoP good practices. Скилл из leogallego/claude-ansible-skills, см. upstream.json."
}
```

- [ ] **Step 4: `LICENSE` (MIT) и `.gitignore`**

`LICENSE`:
```
MIT License

Copyright (c) 2026 Cringe-Driven-Development-Team

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Скиллы в plugins/*/skills/* и файлы plugins/*/references распространяются под
лицензиями своих апстримов — файл LICENSE лежит рядом с каждым из них.
```

`.gitignore`:
```
*~
.DS_Store
```

- [ ] **Step 5: Проверить манифест маркетплейса**

Run: `cd /mnt/f/Github/2026_H2/claude-plugins && claude plugin validate .`
Expected: маркетплейс валиден (предупреждения о плагинах без скиллов допустимы — скиллы появятся в Task 3). Любая ошибка схемы — исправить JSON и повторить.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: каркас маркетплейса cdd

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: scripts/sync.sh с тестами

**Files:**
- Create: `/mnt/f/Github/2026_H2/claude-plugins/tests/sync_test.sh`
- Create: `/mnt/f/Github/2026_H2/claude-plugins/scripts/sync.sh`

**Interfaces:**
- Consumes: `plugins/<plugin>/.claude-plugin/plugin.json` (Task 1).
- Produces: `scripts/sync.sh [--update]`; env `SYNC_GIT_BASE` (префикс адреса репо, по умолчанию `https://github.com/`); формат `upstream.json`:
  `{"sources": {<key>: {"repo": "owner/name", "commit": "<sha>", "license": "LICENSE"}}, "skills": [{"plugin": "...", "source": "<key>", "path": "...", "pluginFiles": [{"from": "...", "to": "..."}]}]}`.

- [ ] **Step 1: Написать тесты `tests/sync_test.sh`**

```bash
#!/usr/bin/env bash
# Тесты scripts/sync.sh: апстрим — локальный git-репо, адрес подменяется через SYNC_GIT_BASE.
set -uo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SYNC=$ROOT/scripts/sync.sh
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
UP=$TMP/upstreams/acme/skills
FAILS=0
CASES=0

fail() { echo "  FAIL: $*"; FAILS=$((FAILS + 1)); }
assert_file() { [ -f "$1" ] || fail "нет файла ${1#$TMP/}"; }
assert_no() { [ ! -e "$1" ] || fail "лишний путь ${1#$TMP/}"; }
assert_eq() { [ "$1" = "$2" ] || fail "$3: ожидалось '$2', получено '$1'"; }
snapshot() { (cd "$1" && find . -type f | sort | xargs cksum); }

git_commit() {
  git -C "$UP" -c user.name=t -c user.email=t@t add -A
  git -C "$UP" -c user.name=t -c user.email=t@t commit -qm "$1"
  git -C "$UP" rev-parse HEAD
}

# Апстрим acme/skills со скиллом skills/demo-skill; служебные файлы копироваться не должны.
make_upstream() {
  rm -rf "$UP"
  mkdir -p "$UP/skills/demo-skill/references" "$UP/skills/demo-skill/scripts" \
    "$UP/skills/demo-skill/agents" "$UP/skills/demo-skill/evals" "$UP/refs"
  echo "LICENSE acme" > "$UP/LICENSE"
  printf -- '---\nname: demo-skill\ndescription: demo\n---\nv1\n' > "$UP/skills/demo-skill/SKILL.md"
  echo ref > "$UP/skills/demo-skill/references/a.md"
  echo 'echo hi' > "$UP/skills/demo-skill/scripts/run.sh"
  echo x > "$UP/skills/demo-skill/agents/openai.yaml"
  echo x > "$UP/skills/demo-skill/evals/evals.json"
  echo x > "$UP/skills/demo-skill/use_cases.yaml"
  echo doc > "$UP/refs/guide.adoc"
  git -C "$UP" init -q -b main
  git_commit init
}

# Копия репо claude-plugins с плагином demo. $1 — коммит, $2 — массив skills в JSON.
make_case() {
  CASES=$((CASES + 1))
  CASE=$TMP/case-$CASES
  mkdir -p "$CASE/scripts" "$CASE/plugins/demo/.claude-plugin"
  cp "$SYNC" "$CASE/scripts/sync.sh"
  echo '{"name":"demo"}' > "$CASE/plugins/demo/.claude-plugin/plugin.json"
  jq -n --arg c "$1" --argjson skills "$2" \
    '{sources: {acme: {repo: "acme/skills", commit: $c, license: "LICENSE"}}, skills: $skills}' \
    > "$CASE/upstream.json"
}

demo_skill='[{"plugin": "demo", "source": "acme", "path": "skills/demo-skill"}]'

run_sync() { SYNC_GIT_BASE="file://$TMP/upstreams/" bash "$CASE/scripts/sync.sh" "$@"; }

test_copies_skill_files() {
  make_case "$(make_upstream)" "$demo_skill"
  run_sync >/dev/null 2>&1 || fail "sync упал"
  local s=$CASE/plugins/demo/skills/demo-skill
  assert_file "$s/SKILL.md"
  assert_file "$s/references/a.md"
  assert_file "$s/scripts/run.sh"
  assert_eq "$(cat "$s/LICENSE" 2>/dev/null)" "LICENSE acme" "LICENSE скилла"
  assert_no "$s/agents"
  assert_no "$s/evals"
  assert_no "$s/use_cases.yaml"
}

test_idempotent() {
  make_case "$(make_upstream)" "$demo_skill"
  run_sync >/dev/null 2>&1 || fail "первый sync упал"
  local before; before=$(snapshot "$CASE")
  run_sync >/dev/null 2>&1 || fail "второй sync упал"
  assert_eq "$(snapshot "$CASE")" "$before" "повторный sync изменил файлы"
}

test_missing_skill_md_fails_without_changes() {
  make_case "$(make_upstream)" '[{"plugin": "demo", "source": "acme", "path": "skills/nope"}]'
  mkdir -p "$CASE/plugins/demo/skills/demo-skill"
  echo keep > "$CASE/plugins/demo/skills/demo-skill/SKILL.md"
  local before out; before=$(snapshot "$CASE")
  if out=$(run_sync 2>&1); then fail "sync должен упасть"; fi
  grep -q 'skills/nope' <<<"$out" || fail "в ошибке нет пути: $out"
  assert_eq "$(snapshot "$CASE")" "$before" "упавший sync изменил файлы"
}

test_plugin_files() {
  make_case "$(make_upstream)" \
    '[{"plugin": "demo", "source": "acme", "path": "skills/demo-skill", "pluginFiles": [{"from": "refs", "to": "references"}]}]'
  run_sync >/dev/null 2>&1 || fail "sync упал"
  assert_file "$CASE/plugins/demo/references/guide.adoc"
  assert_eq "$(cat "$CASE/plugins/demo/LICENSE" 2>/dev/null)" "LICENSE acme" "LICENSE рядом с references"
}

test_update_bumps_commit() {
  make_case "$(make_upstream)" "$demo_skill"
  printf -- '---\nname: demo-skill\ndescription: demo\n---\nv2\n' > "$UP/skills/demo-skill/SKILL.md"
  local head; head=$(git_commit v2)
  run_sync --update >/dev/null 2>&1 || fail "sync --update упал"
  assert_eq "$(jq -r .sources.acme.commit "$CASE/upstream.json")" "$head" "коммит в upstream.json"
  grep -qx v2 "$CASE/plugins/demo/skills/demo-skill/SKILL.md" || fail "SKILL.md не обновился"
}

test_update_failure_keeps_manifest() {
  make_case "$(make_upstream)" "$demo_skill"
  run_sync >/dev/null 2>&1 || fail "начальный sync упал"
  rm "$UP/skills/demo-skill/SKILL.md"
  git_commit "remove skill" >/dev/null
  local before; before=$(snapshot "$CASE")
  if run_sync --update >/dev/null 2>&1; then fail "sync --update должен упасть"; fi
  assert_eq "$(snapshot "$CASE")" "$before" "упавший --update изменил файлы"
}

test_leaves_unlisted_skills() {
  make_case "$(make_upstream)" "$demo_skill"
  mkdir -p "$CASE/plugins/demo/skills/own"
  echo mine > "$CASE/plugins/demo/skills/own/SKILL.md"
  run_sync >/dev/null 2>&1 || fail "sync упал"
  assert_eq "$(cat "$CASE/plugins/demo/skills/own/SKILL.md")" "mine" "свой скилл"
}

test_replaces_stale_files() {
  make_case "$(make_upstream)" "$demo_skill"
  mkdir -p "$CASE/plugins/demo/skills/demo-skill"
  echo old > "$CASE/plugins/demo/skills/demo-skill/old.md"
  run_sync >/dev/null 2>&1 || fail "sync упал"
  assert_no "$CASE/plugins/demo/skills/demo-skill/old.md"
}

test_unknown_plugin_fails() {
  make_case "$(make_upstream)" '[{"plugin": "ghost", "source": "acme", "path": "skills/demo-skill"}]'
  local out
  if out=$(run_sync 2>&1); then fail "sync должен упасть"; fi
  grep -q 'ghost' <<<"$out" || fail "в ошибке нет имени плагина: $out"
}

test_unknown_source_fails() {
  make_case "$(make_upstream)" '[{"plugin": "demo", "source": "nobody", "path": "skills/demo-skill"}]'
  local out
  if out=$(run_sync 2>&1); then fail "sync должен упасть"; fi
  grep -q 'nobody' <<<"$out" || fail "в ошибке нет имени источника: $out"
}

test_duplicate_skill_fails() {
  make_case "$(make_upstream)" \
    '[{"plugin": "demo", "source": "acme", "path": "skills/demo-skill"}, {"plugin": "demo", "source": "acme", "path": "skills/demo-skill/"}]'
  if run_sync >/dev/null 2>&1; then fail "sync должен упасть на дубле"; fi
  assert_no "$CASE/plugins/demo/skills/demo-skill"
}

test_trailing_slash_path() {
  make_case "$(make_upstream)" '[{"plugin": "demo", "source": "acme", "path": "skills/demo-skill/"}]'
  run_sync >/dev/null 2>&1 || fail "sync упал"
  assert_file "$CASE/plugins/demo/skills/demo-skill/SKILL.md"
}

test_runs_from_other_cwd() {
  make_case "$(make_upstream)" "$demo_skill"
  (cd / && run_sync >/dev/null 2>&1) || fail "sync упал при запуске не из корня"
  assert_file "$CASE/plugins/demo/skills/demo-skill/SKILL.md"
}

test_bad_argument_fails() {
  make_case "$(make_upstream)" "$demo_skill"
  if run_sync --bogus >/dev/null 2>&1; then fail "sync должен отвергнуть --bogus"; fi
}

for t in $(declare -F | awk '$3 ~ /^test_/ {print $3}'); do
  echo "$t"
  "$t"
done
echo
if [ "$FAILS" -gt 0 ]; then echo "провалов: $FAILS"; exit 1; fi
echo "все тесты прошли"
```

- [ ] **Step 2: Запустить тесты — убедиться, что падают**

Run: `cd /mnt/f/Github/2026_H2/claude-plugins && bash tests/sync_test.sh`
Expected: FAIL — `cp: cannot stat '.../scripts/sync.sh'`, итог `провалов: N`, exit 1.

- [ ] **Step 3: Реализовать `scripts/sync.sh`**

```bash
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
```

Run: `chmod +x scripts/sync.sh tests/sync_test.sh`

- [ ] **Step 4: Запустить тесты — убедиться, что проходят**

Run: `cd /mnt/f/Github/2026_H2/claude-plugins && bash tests/sync_test.sh`
Expected: каждое имя `test_*` без строк `FAIL`, в конце `все тесты прошли`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/sync.sh tests/sync_test.sh
git commit -m "feat: sync.sh — синхронизация скиллов с апстримами по upstream.json

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: upstream.json и первая синхронизация скиллов

**Files:**
- Create: `/mnt/f/Github/2026_H2/claude-plugins/upstream.json`
- Create (генерирует sync.sh): `plugins/pulumi/skills/{pulumi-best-practices,pulumi-component,pulumi-debug-failed-operation,provider-upgrade,pulumi-cli}/`, `plugins/ansible/skills/ansible-good-practices/`, `plugins/ansible/references/`, `plugins/ansible/LICENSE`

**Interfaces:**
- Consumes: `scripts/sync.sh` (Task 2), `plugin.json` плагинов (Task 1).

- [ ] **Step 1: Написать `upstream.json`**

```json
{
  "sources": {
    "pulumi-agent-skills": {
      "repo": "pulumi/agent-skills",
      "commit": "9b794aec9c4169f137285c2763c06064d247dd47",
      "license": "LICENSE"
    },
    "dirien": {
      "repo": "dirien/claude-skills",
      "commit": "22aaf94d59d53c88a5465bcb5434d309fae8787a",
      "license": "LICENSE"
    },
    "ansible-skills": {
      "repo": "leogallego/claude-ansible-skills",
      "commit": "2c43de8f4b180342f05f5e670cc7e6e8ae359ec4",
      "license": "LICENSE"
    }
  },
  "skills": [
    { "plugin": "pulumi", "source": "pulumi-agent-skills", "path": "pulumi/skills/pulumi-best-practices" },
    { "plugin": "pulumi", "source": "pulumi-agent-skills", "path": "pulumi/skills/pulumi-component" },
    { "plugin": "pulumi", "source": "pulumi-agent-skills", "path": "pulumi/skills/pulumi-debug-failed-operation" },
    { "plugin": "pulumi", "source": "pulumi-agent-skills", "path": "pulumi/skills/provider-upgrade" },
    { "plugin": "pulumi", "source": "dirien", "path": "pulumi-cli" },
    {
      "plugin": "ansible",
      "source": "ansible-skills",
      "path": "ansible-good-practices/skills/ansible-good-practices",
      "pluginFiles": [ { "from": "ansible-good-practices/references", "to": "references" } ]
    }
  ]
}
```

- [ ] **Step 2: Запустить синхронизацию**

Run: `cd /mnt/f/Github/2026_H2/claude-plugins && scripts/sync.sh`
Expected: `sync: скиллов синхронизировано: 6`, exit 0.

- [ ] **Step 3: Проверить состав и воспроизводимость**

```bash
find plugins -type f | sort
scripts/sync.sh && git status --porcelain plugins upstream.json   # после первого add — пусто
```

Expected (`find`): 5 каталогов в `plugins/pulumi/skills/`, в каждом `SKILL.md` и `LICENSE` (+ `references/` у `provider-upgrade` и `pulumi-cli`); `plugins/ansible/skills/ansible-good-practices/{SKILL.md,LICENSE}`, `plugins/ansible/references/*.adoc` (13 файлов), `plugins/ansible/LICENSE`. Нет ни одного `openai.yaml`, `use_cases.yaml`, `evals.json`, `mcp.json`.

Сверка с апстримом (пример для pulumi-cli, аналогично для остальных — `diff` должен молчать):
```bash
tmp=$(mktemp -d) && git clone -q https://github.com/dirien/claude-skills "$tmp/d" && git -C "$tmp/d" checkout -q 22aaf94d59d53c88a5465bcb5434d309fae8787a
diff -r "$tmp/d/pulumi-cli/references" plugins/pulumi/skills/pulumi-cli/references && diff "$tmp/d/pulumi-cli/SKILL.md" plugins/pulumi/skills/pulumi-cli/SKILL.md && diff "$tmp/d/LICENSE" plugins/pulumi/skills/pulumi-cli/LICENSE; rm -rf "$tmp"
```

Лицензии: `head -3 plugins/pulumi/skills/*/LICENSE plugins/ansible/skills/*/LICENSE plugins/ansible/LICENSE` — Apache у четырёх pulumi-скиллов, MIT у `pulumi-cli`, GPL у ansible.

- [ ] **Step 4: Валидация плагинов**

Run: `claude plugin validate . && claude plugin validate plugins/pulumi && claude plugin validate plugins/ansible`
Expected: без ошибок.

Run: `claude plugin details` недоступен до установки — проверка состава после публикации в Task 6.

- [ ] **Step 5: Commit**

```bash
git add upstream.json plugins
git commit -m "feat: скиллы pulumi и ansible из апстримов

pulumi: pulumi-best-practices, pulumi-component, pulumi-debug-failed-operation,
provider-upgrade (pulumi/agent-skills), pulumi-cli (dirien/claude-skills).
ansible: ansible-good-practices (leogallego/claude-ansible-skills).

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: README

**Files:**
- Create: `/mnt/f/Github/2026_H2/claude-plugins/README.md`

- [ ] **Step 1: Написать README.md**

````markdown
# claude-plugins

Маркетплейс плагинов Claude Code организации Cringe-Driven-Development-Team (`cdd`). Здесь лежат
отобранные скиллы — чтобы не отбирать их заново в каждом репо и у каждого человека.

Правило: сюда попадает то, что приходится собирать самим — подмножества чужих плагинов и свои
скиллы. Целые сторонние плагины подключаются напрямую из их маркетплейсов
(см. [рекомендуемые](#рекомендуемые-сторонние-плагины)).

## Подключение в репо

В `.claude/settings.json` репо (коммитится в git):

```json
{
  "extraKnownMarketplaces": {
    "cdd": { "source": { "source": "github", "repo": "Cringe-Driven-Development-Team/claude-plugins" } }
  },
  "enabledPlugins": {
    "pulumi@cdd": true,
    "ansible@cdd": true
  }
}
```

Включайте только нужные репо плагины. При открытии репо Claude Code предложит довериться
маркетплейсу и поставить плагины. Новые версии: `/plugin marketplace update cdd`.

## Каталог

| Плагин | Скилл | Источник | Лицензия |
|---|---|---|---|
| `pulumi` | `pulumi-best-practices` | [pulumi/agent-skills](https://github.com/pulumi/agent-skills) | Apache-2.0 |
| `pulumi` | `pulumi-component` | pulumi/agent-skills | Apache-2.0 |
| `pulumi` | `pulumi-debug-failed-operation` | pulumi/agent-skills | Apache-2.0 |
| `pulumi` | `provider-upgrade` | pulumi/agent-skills | Apache-2.0 |
| `pulumi` | `pulumi-cli` | [dirien/claude-skills](https://github.com/dirien/claude-skills) | MIT |
| `ansible` | `ansible-good-practices` | [leogallego/claude-ansible-skills](https://github.com/leogallego/claude-ansible-skills) | GPL-3.0 |

Закреплённые коммиты — в `upstream.json`. Почему взяты именно эти скиллы и что сознательно не
взято — `docs/design.md`.

## Обновление скиллов из апстримов

```bash
scripts/sync.sh --update   # коммиты источников → HEAD, скиллы перекопированы
git diff                   # прочитать, что изменилось в скиллах
```

Изменения — через PR. Скиллы апстримов руками не правим: следующий `sync.sh` затрёт правки.
Нужна своя версия — отдельный скилл в том же плагине.

Зависимости: `bash`, `git`, `jq`. Тесты скрипта: `bash tests/sync_test.sh`.

## Добавить скилл

- **Из апстрима:** источник в `sources` (если новый) и запись в `skills` файла `upstream.json`,
  затем `scripts/sync.sh`. Если скилл читает файлы из корня своего плагина — `pluginFiles`
  (пример — `ansible-good-practices`).
- **Свой:** `plugins/<плагин>/skills/<имя>/SKILL.md`. `sync.sh` его не трогает.
- **Новый плагин:** `plugins/<плагин>/.claude-plugin/plugin.json` и запись в
  `.claude-plugin/marketplace.json`.

Проверка: `claude plugin validate .`

## Рекомендуемые сторонние плагины

Подключаются в репо целиком, своим маркетплейсом:

```json
{
  "extraKnownMarketplaces": {
    "claude-plugins-official": { "source": { "source": "github", "repo": "anthropics/claude-plugins-official" } }
  },
  "enabledPlugins": {
    "superpowers@claude-plugins-official": true
  }
}
```

## Лицензии

Собственные файлы репо — MIT (`LICENSE`). Скиллы и `plugins/*/references` — лицензии апстримов,
файл `LICENSE` лежит рядом с каждым.
````

- [ ] **Step 2: Проверить адрес официального маркетплейса**

Run: `python3 -c "import json;d=json.load(open('/home/oleg/.claude/plugins/known_marketplaces.json'));print(json.dumps(d.get('claude-plugins-official',{}).get('source')))"`
Expected: `{"source": "github", "repo": "..."}` — если `repo` отличается от `anthropics/claude-plugins-official`, исправить README на фактическое значение.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: README маркетплейса cdd

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Публикация репо в организации

**Files:** нет изменений.

- [ ] **Step 1: Создать публичный репо и запушить**

```bash
cd /mnt/f/Github/2026_H2/claude-plugins
gh repo create Cringe-Driven-Development-Team/claude-plugins --public \
  --description "Маркетплейс плагинов Claude Code организации (cdd)" --source . --remote origin --push
```

Expected: URL `https://github.com/Cringe-Driven-Development-Team/claude-plugins`, ветка `main` запушена.

- [ ] **Step 2: Проверить**

Run: `gh repo view Cringe-Driven-Development-Team/claude-plugins --json visibility,defaultBranchRef -q '.visibility + " " + .defaultBranchRef.name' && git status -sb | head -1`
Expected: `PUBLIC main`, `## main...origin/main`.

---

### Task 6: Переезд infra на маркетплейс cdd и сквозная проверка

**Files:**
- Delete: `/mnt/f/Github/2026_H2/infra/.claude/skills/` (целиком)
- Modify: `/mnt/f/Github/2026_H2/infra/.claude/settings.json`

**Interfaces:**
- Consumes: опубликованный маркетплейс `cdd` (Task 5).

- [ ] **Step 1: Сквозная проверка в чистом клоне**

```bash
tmp=$(mktemp -d) && git clone -q https://github.com/Cringe-Driven-Development-Team/claude-plugins "$tmp/cp"
cd "$tmp" && mkdir proj && cd proj && git init -q
claude plugin marketplace add Cringe-Driven-Development-Team/claude-plugins --scope project
claude plugin install pulumi@cdd -s project && claude plugin install ansible@cdd -s project
claude plugin details pulumi@cdd | sed -n '/Component inventory/,/LSP/p'
claude plugin details ansible@cdd | sed -n '/Component inventory/,/LSP/p'
```

Expected: `pulumi@cdd` — `Skills (5)`: provider-upgrade, pulumi-best-practices, pulumi-cli, pulumi-component, pulumi-debug-failed-operation; `MCP servers (0)`. `ansible@cdd` — `Skills (1)` ansible-good-practices; `MCP servers (0)`.

Убрать временное:
```bash
claude plugin uninstall pulumi@cdd -s project; claude plugin uninstall ansible@cdd -s project
cd / && rm -rf "$tmp"
```

- [ ] **Step 2: Переключить infra**

```bash
cd /mnt/f/Github/2026_H2/infra && git switch task-infra-5-bootstrap
claude plugin uninstall ansible-good-practices@claude-ansible-skills -s project
claude plugin marketplace remove claude-ansible-skills --scope project
git rm -rq .claude/skills
```

Записать `.claude/settings.json`:
```json
{
  "extraKnownMarketplaces": {
    "cdd": {
      "source": {
        "source": "github",
        "repo": "Cringe-Driven-Development-Team/claude-plugins"
      }
    }
  },
  "enabledPlugins": {
    "pulumi@cdd": true,
    "ansible@cdd": true
  }
}
```

```bash
claude plugin install pulumi@cdd -s project && claude plugin install ansible@cdd -s project
claude plugin list
```

Expected: `claude plugin list` — `pulumi@cdd` и `ansible@cdd` (scope project, enabled); `ansible-good-practices@claude-ansible-skills` отсутствует. `git diff .claude/settings.json` совпадает с JSON выше (если `claude plugin install` переформатировал файл — привести к виду выше).

- [ ] **Step 3: Commit**

```bash
git add -A .claude
git commit -m "chore: скиллы Claude Code из маркетплейса орги cdd

Вместо копий в .claude/skills и прямого claude-ansible-skills —
pulumi@cdd и ansible@cdd из Cringe-Driven-Development-Team/claude-plugins.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Не коммитить `.github/workflows/automation.yml` и `w~` — чужие изменения рабочей копии.

- [ ] **Step 4: Проверить в сессии**

Попросить пользователя выполнить `/reload-plugins` (или перезапустить сессию) и убедиться, что в списке скиллов есть `pulumi-cli`, `pulumi-best-practices` и `ansible-good-practices` из `cdd`, а дублей из `.claude/skills` нет.
