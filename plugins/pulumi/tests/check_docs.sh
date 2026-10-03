#!/usr/bin/env bash
# Структура и чистота собственного скилла pulumi-typescript: разделы, ключевые факты, нет идентификаторов стенда.
set -u
cd "$(dirname "$0")/../skills/pulumi-typescript" || exit 2
fail=0
need() { grep -qF -- "$2" "$1" || { echo "нет в $1: $2"; fail=1; }; }

[ -f SKILL.md ] || { echo "нет SKILL.md"; exit 1; }
[ -f REFERENCE.md ] || { echo "нет REFERENCE.md"; exit 1; }
need SKILL.md "name: pulumi-typescript"
need SKILL.md "description:"
for h in "## Когда применять" "## Никогда" "## Проект" "## Код" "## Тесты" "## Эксплуатация" \
         "## Когда что-то не получается"; do
  need SKILL.md "$h"
done
for h in "## 1. Проект" "## 2. Output и apply" "## 3. Опции ресурсов" "## 4. Тесты" \
         "## 5. Backend и перенос стейта" "## 6. Импорт" "## 7. Bootstrap-стек"; do
  need REFERENCE.md "$h"
done
for s in "isDryRun" "deleteBeforeReplace" "protect" "ignoreChanges" "aliases" "--show-secrets" \
         "file://" "setMocks" "Bun.spawnSync" "packagemanager: bun" "terraform-provider" "sdks/" \
         "stack export" "stack import" "s3ForcePathStyle" "selectel-ops" "pulumi-best-practices" "pulumi-cli" \
         "__provider" "--exclude-protected"; do
  need REFERENCE.md "$s"
done
for s in "isDryRun" "deleteBeforeReplace" "--show-secrets" "file://" "setMocks" "import" "selectel-ops"; do
  need SKILL.md "$s"
done
# SDK генерируется только в sdks/<имя> — не отправлять читателя в несуществующий каталог
! grep -qF "и/или \`.pulumi/\`" REFERENCE.md || { echo "REFERENCE.md: неподтверждённая оговорка про .pulumi/"; fail=1; }
lines=$(wc -l < SKILL.md)
[ "$lines" -le 230 ] || { echo "SKILL.md длиннее 230 строк: $lines"; fail=1; }

leaks=$(grep -nE '([0-9]{1,3}\.){3}[0-9]{1,3}|[0-9a-f]{32}|(^|[^0-9.])[0-9]{6,}([^0-9.]|$)|gAAAA' SKILL.md REFERENCE.md 2>/dev/null \
        | grep -vE '127\.0\.0\.1|0{32}|<ACCOUNT>|<PROJECT_ID>' || true)
[ -z "$leaks" ] || { echo "похоже на идентификаторы стенда:"; echo "$leaks"; fail=1; }
exit $fail
