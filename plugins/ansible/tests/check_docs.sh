#!/usr/bin/env bash
# Структура и чистота собственного скилла ansible-org: разделы, ключевые факты, нет идентификаторов стенда.
set -u
cd "$(dirname "$0")/../skills/ansible-org" || exit 2
fail=0
need() { grep -qF -- "$2" "$1" || { echo "нет в $1: $2"; fail=1; }; }

[ -f SKILL.md ] || { echo "нет SKILL.md"; exit 1; }
need SKILL.md "name: ansible-org"
need SKILL.md "description:"
for h in "## Когда применять" "## Никогда" "## Подключение и доступ" "## sshd на Ubuntu 24.04" "## Docker" "## Секреты (ansible-vault)" \
         "## ansible-lint" "## verify.yml" "## Установка" "## Когда что-то не получается"; do
  need SKILL.md "$h"
done
for s in "Conditional expressions must be strings" "exclusive" "ssh.socket" "DOCKER-USER" \
         "docker_compose_v2" "var-naming[no-role-prefix]" "name[casing]" "pipx inject" \
         "ansible-good-practices" "selectel-ops" "ansible-vault" "--show-secrets"; do
  need SKILL.md "$s"
done
lines=$(wc -l < SKILL.md)
[ "$lines" -le 230 ] || { echo "SKILL.md длиннее 230 строк: $lines"; fail=1; }
leaks=$(grep -nE '([0-9]{1,3}\.){3}[0-9]{1,3}|[0-9a-f]{32}|(^|[^0-9.])[0-9]{6,}([^0-9.]|$)|gAAAA' SKILL.md 2>/dev/null \
        | grep -vE '127\.0\.0\.1' || true)
[ -z "$leaks" ] || { echo "похоже на идентификаторы стенда:"; echo "$leaks"; fail=1; }
exit $fail
