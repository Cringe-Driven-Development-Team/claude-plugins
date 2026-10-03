# cdd-tasks

Скилл для работы с задачами и PR команды из Claude Code: в каком репозитории заводить задачу,
как её назвать и описать, как разбить на sub-issues работу, которая затрагивает несколько
репозиториев, как выставить статус и спринт на доске, что писать в описании PR — `Closes` или
`Part of`.

Сами правила — в [CONTRIBUTING.md](https://github.com/Cringe-Driven-Development-Team/.github/blob/main/CONTRIBUTING.md)
организации. Скилл их не заменяет: он читает их перед работой и добавляет то, что нужно агенту, —
карту репозиториев и точные команды `gh`.

## Требования

- `gh`, авторизованный в GitHub с доступом к организации.
- Для статуса и спринта на доске — scope `project`: `gh auth refresh -s project`.

## Подключение

В `.claude/settings.json` репозитория:

```json
{
  "extraKnownMarketplaces": {
    "cdd": { "source": { "source": "github", "repo": "Cringe-Driven-Development-Team/claude-plugins" } }
  },
  "enabledPlugins": {
    "cdd-tasks@cdd": true
  }
}
```

## Чего скилл не делает

- Не вливает PR в обход обязательного ревью.
- Без просьбы не переводит задачи в спринт, не меняет исполнителя и не правит чужие описания:
  такие изменения уходят уведомлением в чат команды.
- Не проверяет доску: задачи без описания и PR без привязки он не ищет.

## Проверка

Из корня маркетплейса:

```bash
bash plugins/cdd-tasks/tests/check_docs.sh
claude plugin eval plugins/cdd-tasks --case multi-repo-task --runs 3
```
