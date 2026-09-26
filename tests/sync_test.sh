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

test_warns_on_orphaned_synced_skill() {
  make_case "$(make_upstream)" "$demo_skill"
  run_sync >/dev/null 2>&1 || fail "начальный sync упал"
  mkdir -p "$UP/skills/renamed-skill"
  cp "$UP/skills/demo-skill/SKILL.md" "$UP/skills/renamed-skill/SKILL.md"
  jq --arg c "$(git_commit rename)" '.sources.acme.commit = $c | .skills[0].path = "skills/renamed-skill"' \
    "$CASE/upstream.json" > "$CASE/upstream.json.new" && mv "$CASE/upstream.json.new" "$CASE/upstream.json"
  local out
  out=$(run_sync 2>&1) || fail "sync упал"
  grep -q 'demo/skills/demo-skill' <<<"$out" || fail "нет предупреждения об осиротевшем скилле: $out"
}

test_no_warning_for_own_skill() {
  make_case "$(make_upstream)" "$demo_skill"
  mkdir -p "$CASE/plugins/demo/skills/own"
  echo mine > "$CASE/plugins/demo/skills/own/SKILL.md"
  local out
  out=$(run_sync 2>&1) || fail "sync упал"
  if grep -q 'skills/own' <<<"$out"; then fail "лишнее предупреждение о своём скилле: $out"; fi
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
