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
    "ansible@cdd": true,
    "selectel-ops@cdd": true
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
| `pulumi` | `pulumi-typescript` | собственный (идеи — [dirien/claude-skills](https://github.com/dirien/claude-skills), текст свой) | MIT |
| `ansible` | `ansible-good-practices` | [leogallego/claude-ansible-skills](https://github.com/leogallego/claude-ansible-skills) | GPL-3.0 |
| `selectel-ops` | `selectel-ops` | собственный плагин организации (перенесён из YarikMix/claude-plugins) | MIT |

Закреплённые коммиты — в `upstream.json`. Почему взяты именно эти скиллы и что сознательно не
взято — `docs/design.md`.

## Обновление скиллов из апстримов

```bash
scripts/sync.sh --update   # коммиты источников → HEAD, скиллы перекопированы
git diff                   # прочитать, что изменилось в скиллах
```

Изменения — через PR. `version` в `plugin.json` не задаём: версией служит коммит, и после
мержа обновления приходят всем по `/plugin marketplace update cdd`. Скиллы апстримов руками не правим: следующий `sync.sh` затрёт правки.
Нужна своя версия — отдельный скилл в том же плагине.

Зависимости: `bash`, `git`, `jq`. Тесты: `bash tests/sync_test.sh && bash tests/manifest_test.sh && bash plugins/pulumi/tests/check_docs.sh`;
`selectel-ops` — `cd plugins/selectel-ops && python3 -m unittest discover -s tests -t . && bash tests/check_docs.sh`.

Отдельно, не в этой цепочке — оценка поведения скиллов живыми вызовами модели (платно,
недетерминированно, запускается вручную, по одному сценарию: `--case` не складывается):
`claude plugin eval plugins/<плагин> --case <сценарий> --runs 3 --max-cost-usd 4`. Каждый сценарий
идёт в двух вариантах — с плагином и без; результаты последнего прогона (2026-09-26, `--runs 3`):

| Плагин | Сценарий | С плагином | Без | Δ |
|---|---|---|---|---|
| `pulumi` | `missing-env-test` — тест «окружение не задано» | 1 | 0 | +1 |
| `pulumi` | `personal-state-key` — доступ новичка к стейту | 1 | 0.33 | +0.67 |
| `pulumi` | `file-login-trap` — `login file://` откатился на Pulumi Cloud | 1 | 0.67 | +0.33 |
| `selectel-ops` | `zone-move-import` — перенос DNS-зоны и импорт в Pulumi | 1 | 0 | +1 |
| `pulumi` | `state-migration`, `zone-import` (`--runs 1`) | 1 | 1 | 0 — общие знания Pulumi |

Вариант «без плагина» запускается в каталоге этого репо и может найти текст скиллов поиском по
файлам — Δ скорее занижена, чем завышена.

## Добавить скилл

- **Из апстрима:** источник в `sources` (если новый) и запись в `skills` файла `upstream.json`,
  затем `scripts/sync.sh`. Если скилл читает файлы из корня своего плагина — `pluginFiles`
  (пример — `ansible-good-practices`).
- **Свой:** `plugins/<плагин>/skills/<имя>/SKILL.md`. `sync.sh` его не трогает.
- **Убрать или переименовать скилл из апстрима:** поправить `upstream.json` и удалить старый
  `plugins/<плагин>/skills/<имя>/` руками — `sync.sh` сам ничего не удаляет, но предупреждает
  о каталогах с лицензией апстрима, которых нет в `upstream.json`.
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
