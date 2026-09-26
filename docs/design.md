# claude-plugins — маркетплейс плагинов Claude Code организации

Дата: 2026-09-26. Статус: утверждено.

## Цель

Отобранные командой скиллы Claude Code лежат в одном репо организации
`Cringe-Driven-Development-Team/claude-plugins` и подключаются в любой репо орги строкой в
`.claude/settings.json`. Новый участник открывает репо в Claude Code, подтверждает установку
плагинов — и получает ровно отобранный набор, без повторного исследования.

Маркетплейс общий для организации: сейчас в нём плагины инфраструктуры, структура рассчитана на
плагины других репо (`react`, `docs` и т.д.).

## Что входит и что нет

Входит:
- скиллы, которые приходится собирать самим: подмножества чужих плагинов и в будущем свои скиллы;
- скрипт синхронизации с апстримами и описание источников.

Не входит:
- целые сторонние плагины (например, `superpowers` из `claude-plugins-official`) — репо подключают их
  напрямую из их маркетплейса; в README только список рекомендуемых с готовыми строками;
- правки чужих скиллов — нужна своя версия → отдельный скилл в том же плагине.

## Состав (первая версия)

| Плагин | Скилл | Источник | Лицензия |
|---|---|---|---|
| `pulumi` | `pulumi-best-practices` | `pulumi/agent-skills` → `pulumi/skills/pulumi-best-practices` | Apache-2.0 |
| `pulumi` | `pulumi-component` | `pulumi/agent-skills` → `pulumi/skills/pulumi-component` | Apache-2.0 |
| `pulumi` | `pulumi-debug-failed-operation` | `pulumi/agent-skills` → `pulumi/skills/pulumi-debug-failed-operation` | Apache-2.0 |
| `pulumi` | `provider-upgrade` | `pulumi/agent-skills` → `pulumi/skills/provider-upgrade` | Apache-2.0 |
| `pulumi` | `pulumi-cli` | `dirien/claude-skills` → `pulumi-cli` | MIT |
| `ansible` | `ansible-good-practices` | `leogallego/claude-ansible-skills` → `ansible-good-practices/skills/ansible-good-practices` | GPL-3.0 |

Закреплённые коммиты апстримов:
- `pulumi/agent-skills` — `9b794aec9c4169f137285c2763c06064d247dd47`
- `dirien/claude-skills` — `22aaf94d59d53c88a5465bcb5434d309fae8787a`
- `leogallego/claude-ansible-skills` — `2c43de8f4b180342f05f5e670cc7e6e8ae359ec4`

Сознательно не взяты: остальные 11 скиллов плагина `pulumi` (миграции Terraform/CDK/ARM/
CloudFormation, ESC, Neo, automation/context API, overview, package-usage); `pulumi-typescript`
(построен вокруг Pulumi ESC и AWS/Azure/GCP, пересекается с `pulumi-best-practices`; мы на
Selectel/OpenStack, стейт в S3, секреты через passphrase); `ansible-docs` (требует MCP
`ansible-know`); `ansible-new-role`/`ansible-new-molecule` (тянут к раскладке коллекций, у нас
плоская).

## Структура репо

```
claude-plugins/
├── .claude-plugin/marketplace.json   маркетплейс "cdd"
├── plugins/
│   ├── pulumi/
│   │   ├── .claude-plugin/plugin.json
│   │   └── skills/<скилл>/{SKILL.md, references/…, LICENSE}
│   └── ansible/
│       ├── .claude-plugin/plugin.json
│       ├── references/*.adoc          SKILL.md читает их из корня плагина
│       ├── LICENSE                    к references/ (GPL-3.0)
│       └── skills/ansible-good-practices/{SKILL.md, LICENSE}
├── upstream.json
├── scripts/sync.sh
├── docs/design.md                    этот документ
├── README.md
└── LICENSE                           MIT — на собственные файлы репо
```

- Один плагин на область: репо включают область целиком (`pulumi@cdd`). Новые области —
  `plugins/<область>/`.
- Имя маркетплейса — `cdd`. С официальным `pulumi@pulumi-agent-skills` не конфликтует.
- Скиллы копируются без правок: `SKILL.md`, `references/`, `scripts/` (если есть). Служебные файлы
  апстримов (`agents/openai.yaml`, `use_cases.yaml`, `evals/`, `mcp.json`) не копируются.
- Лицензия источника лежит в каталоге каждого скилла (в одном плагине скиллы с разными
  лицензиями) и рядом с каждым дополнительным путём, скопированным в корень плагина.
- `plugin.json` скиллы не перечисляет — Claude Code находит всё в `skills/`. Новый скилл = запись в
  `upstream.json` + `sync.sh`; `plugin.json`/`marketplace.json` правятся только при добавлении
  плагина.

## upstream.json

```json
{
  "sources": {
    "pulumi-agent-skills": { "repo": "pulumi/agent-skills", "commit": "9b794ae…", "license": "LICENSE" },
    "dirien": { "repo": "dirien/claude-skills", "commit": "22aaf94…", "license": "LICENSE" },
    "ansible-skills": { "repo": "leogallego/claude-ansible-skills", "commit": "2c43de8…", "license": "LICENSE" }
  },
  "skills": [
    { "plugin": "pulumi", "source": "pulumi-agent-skills", "path": "pulumi/skills/pulumi-best-practices" },
    { "plugin": "pulumi", "source": "dirien", "path": "pulumi-cli" },
    { "plugin": "ansible", "source": "ansible-skills",
      "path": "ansible-good-practices/skills/ansible-good-practices",
      "pluginFiles": [ { "from": "ansible-good-practices/references", "to": "references" } ] }
  ]
}
```

- `sources` — репо апстрима, закреплённый полный SHA, путь к файлу лицензии в апстриме.
- `skills[]` — плагин назначения, источник, путь к каталогу скилла в апстриме; имя каталога скилла
  = последний сегмент пути.
- `pluginFiles` (необязательно) — пути апстрима, которые копируются в корень плагина (для скиллов,
  читающих файлы плагина, как `ansible-good-practices`).

## scripts/sync.sh

`scripts/sync.sh [--update]`, зависимости: `bash`, `git`, `jq`.

1. С `--update` — сначала `commit` каждого источника заменяется на HEAD его ветки по умолчанию
   (`git ls-remote`), `upstream.json` перезаписывается.
2. Каждый источник клонируется во временный каталог и переключается на закреплённый коммит.
3. Во временном каталоге собирается итог: для каждого скилла — `SKILL.md`, `references/`,
   `scripts/` (что есть) и `LICENSE` источника; для `pluginFiles` — указанный путь и `LICENSE`
   рядом.
4. Проверки до записи: путь скилла существует, в нём есть `SKILL.md`, файл лицензии существует.
   Любая ошибка → понятное сообщение, выход с ненулевым кодом, рабочее дерево не тронуто.
5. Замена: для каждого затронутого скилла и `pluginFiles` каталог в `plugins/` заменяется
   собранным. Скиллы, которых нет в `upstream.json`, скрипт не трогает (свои скиллы живут рядом).

Обновление апстримов — только через `--update` + PR: изменения скиллов видны в диффе и
проходят ревью.

## Подключение в репо организации

`.claude/settings.json` репо (в git):

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

Каждый репо включает только нужные плагины. Сторонние целые плагины подключаются так же, своим
маркетплейсом.

README `claude-plugins`: назначение; блок для `settings.json`; каталог (плагин → скиллы →
источник, лицензия); обновление (`sync.sh --update` → PR); добавление скилла/плагина;
рекомендуемые сторонние плагины с готовыми строками.

## Переезд infra

В ветке `task-infra-5-bootstrap` репо `infra`:
- удалить `.claude/skills/` (копии из коммита `22b7da3`);
- `.claude/settings.json` — только маркетплейс `cdd`, `pulumi@cdd`, `ansible@cdd`; прямое
  подключение `claude-ansible-skills` убрать.

## Проверка

1. `sync.sh` дважды подряд без `--update` → пустой `git diff`; содержимое каждого скилла совпадает
   с апстримом на закреплённом коммите по списку копируемых файлов.
2. `claude plugin validate` для маркетплейса и обоих плагинов проходит.
3. После пуша, в чистом временном клоне `infra` (ветка `task-infra-5-bootstrap`):
   `claude plugin marketplace add` видит `cdd`; `claude plugin install pulumi@cdd` и
   `ansible@cdd` (scope project) проходят; `claude plugin details` показывает 5 и 1 скилл,
   MCP-серверов 0. Затем локально убрать маркетплейс `claude-ansible-skills` и убедиться, что
   `ansible-good-practices` приходит из `cdd`.
4. В каждом `plugins/*/skills/*/` есть `LICENSE`, совпадающий с лицензией своего источника;
   рядом с `plugins/ansible/references/` — `LICENSE` источника.
