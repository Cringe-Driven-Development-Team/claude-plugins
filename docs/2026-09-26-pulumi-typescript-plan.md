# Собственный скилл pulumi-typescript и актуализация selectel-ops — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** В маркетплейсе `cdd` появляется собственный скилл `pulumi-typescript` (плагин `pulumi`), а `selectel-ops` дополнен фактами, проверенными 2026-09-26; поведение нового скилла проверено сценариями `claude plugin eval`.

**Architecture:** Скиллы — Markdown (`SKILL.md` короткий + `REFERENCE.md` с §N), у каждого плагина свой `tests/check_docs.sh` (структура, ключевые факты, отсутствие идентификаторов стенда) — проверки пишутся до текста. Поведение — сценарии `plugins/pulumi/evals/<case>/{prompt.md,graders/*.md}` с ablation (с плагином / без).

**Tech Stack:** Markdown, bash (`check_docs.sh`, совместимо с bash 3.2/macOS), `claude plugin validate`, `claude plugin eval`.

**Spec:** `docs/2026-09-26-pulumi-typescript-design.md`

## Global Constraints

- Репо `/mnt/f/Github/2026_H2/claude-plugins`, ветка `main` (прямые коммиты, как в остальной истории репо); push в `origin main` в конце Task 4.
- Новый скилл — `plugins/pulumi/skills/pulumi-typescript/`; НЕ добавлять в `upstream.json` (свой скилл; `sync.sh` его не трогает).
- Текст свой, на русском; не копировать текст `dirien/claude-skills` (допустима ссылка как на источник идей в README).
- Примеры кода — по образцу рабочего кода `/mnt/f/Github/2026_H2/infra/pulumi/bootstrap/` (`index.ts`, `selectel-s3.ts`, `*.test.ts`, `env.sh`, `README.md`), обобщённые: без реальных id проектов, IP, номеров аккаунтов, ключей.
- `SKILL.md` любого скилла — не длиннее 230 строк; frontmatter `name:` и `description:` обязательны.
- Селектел-специфика — только в `selectel-ops`; в `pulumi-typescript` — ссылки «см. скилл selectel-ops, REFERENCE §N».
- `check_docs.sh`: `set -u`, без `\b` в grep (BSD grep), код выхода 1 при любом нарушении; утечки — тот же regex, что в `plugins/selectel-ops/tests/check_docs.sh`.
- Коммиты заканчиваются строкой `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; не коммитить `__pycache__/`, `evals/results/`.

## Review Focus

- `description` нового скилла перехватывает общие вопросы о Pulumi у `pulumi-best-practices`/`pulumi-cli` — описание должно сужать область: TypeScript + bun + terraform-bridged провайдеры + DIY S3-backend в организации. Проверка: сценарий Task 3 с `tool_used: Skill` (скилл вызывается) и ревью текста description.
- Пример кода в `REFERENCE.md` не компилируется/устарел относительно `infra/pulumi/bootstrap` — Task 1 шаг сверки: ключевые фрагменты (`setMocks(..., true)`, `Bun.spawnSync`, `isDryRun`) совпадают по API с рабочим кодом.
- Утечка идентификаторов стенда (id проекта `36b609e1…`, IP, номер аккаунта) при переносе примеров — `check_docs.sh` с regex утечек в Task 1 и Task 2.
- Совет в скилле, ведущий к необратимому действию без подтверждения (`up`, `destroy`, `state delete`, удаление экспорта) — раздел «Никогда» + грейдеры сценариев Task 3.
- `SKILL.md` разрастается за 230 строк — проверка длины в `check_docs.sh`.

---

### Task 1: скилл pulumi-typescript

**Files:**
- Create: `plugins/pulumi/tests/check_docs.sh`
- Create: `plugins/pulumi/skills/pulumi-typescript/SKILL.md`
- Create: `plugins/pulumi/skills/pulumi-typescript/REFERENCE.md`

**Interfaces:**
- Produces: скилл `pulumi-typescript` (frontmatter `name: pulumi-typescript`); разделы `SKILL.md`: `## Когда применять`, `## Никогда`, `## Проект`, `## Код`, `## Тесты`, `## Эксплуатация`, `## Когда что-то не получается`; разделы `REFERENCE.md`: `## 1. Проект`, `## 2. Output и apply`, `## 3. Опции ресурсов`, `## 4. Тесты`, `## 5. Backend и перенос стейта`, `## 6. Импорт`, `## 7. Bootstrap-стек`.

- [ ] **Step 1: Написать `plugins/pulumi/tests/check_docs.sh`**

```bash
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
         "stack export" "stack import" "s3ForcePathStyle" "selectel-ops" "pulumi-best-practices" "pulumi-cli"; do
  need REFERENCE.md "$s"
done
for s in "isDryRun" "deleteBeforeReplace" "--show-secrets" "file://" "setMocks" "import" "selectel-ops"; do
  need SKILL.md "$s"
done
lines=$(wc -l < SKILL.md)
[ "$lines" -le 230 ] || { echo "SKILL.md длиннее 230 строк: $lines"; fail=1; }

leaks=$(grep -nE '([0-9]{1,3}\.){3}[0-9]{1,3}|[0-9a-f]{32}|(^|[^0-9.])[0-9]{6,}([^0-9.]|$)|gAAAA' SKILL.md REFERENCE.md 2>/dev/null \
        | grep -vE '127\.0\.0\.1|0{32}|<ACCOUNT>|<PROJECT_ID>' || true)
[ -z "$leaks" ] || { echo "похоже на идентификаторы стенда:"; echo "$leaks"; fail=1; }
exit $fail
```

- [ ] **Step 2: Запустить — убедиться, что падает**

Run: `cd /mnt/f/Github/2026_H2/claude-plugins && chmod +x plugins/pulumi/tests/check_docs.sh && bash plugins/pulumi/tests/check_docs.sh; echo "exit=$?"`
Expected: `нет SKILL.md`, `exit=1`.

- [ ] **Step 3: Написать `SKILL.md`**

Frontmatter:
```yaml
---
name: pulumi-typescript
description: Pulumi-программы на TypeScript в репозиториях организации — bun, terraform-bridged провайдеры (packages в Pulumi.yaml, sdks/), DIY-backend стейта в S3, секреты через passphrase, тесты на моках (bun test, setMocks), побочные эффекты под isDryRun, protect/deleteBeforeReplace/import/aliases, перенос стейта между backend, импорт существующих ресурсов, bootstrap-стек. Активируется при работе с pulumi/ и pulumi/bootstrap/ в репо организации, Pulumi.yaml с packagemanager bun, pulumi login s3://, pulumi stack export/import, pulumi import. Общие вопросы про Output и компоненты — pulumi-best-practices, операции CLI в целом — pulumi-cli, всё про Selectel — selectel-ops.
---
```
Разделы (содержание — из спеки, раздел «pulumi-typescript», пункты 1–7), каждый пункт — одна-две строки и ссылка «REFERENCE §N» на подробности:
- `## Когда применять` — п.1 спеки.
- `## Никогда` — п.2 спеки, нумерованный список из 4 правил.
- `## Проект` — п.3; `## Код` — п.4; `## Тесты` — п.5; `## Эксплуатация` — п.6.
- `## Когда что-то не получается` — таблица «Симптом | Причина | Действие», 6 строк п.7 спеки:
  1. `pulumi login file://…` + `stack init` → стек оказался в Pulumi Cloud (временный агентский аккаунт) | каталога нет, login упал, CLI откатился на Cloud | удалить стек (`stack rm`), `logout`, `mkdir -p` каталога, повторить login;
  2. `stack output X` выводит `[secret]` (8 символов) | выход секретный (у terraform-bridged провайдеров секретом бывает и access key) | `--show-secrets`;
  3. `open ~/...: no such file or directory` у AWS-провайдера / `pulumi login s3://` | Go SDK читает `~/.aws/config`, `ca_bundle` с `~` не раскрывается | `AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null`;
  4. замена сервера падает на занятом порте/диске | create-before-delete по умолчанию | `deleteBeforeReplace: true`;
  5. `Missing required configuration variable` | не задан конфиг стека | `pulumi config set`; в тестах — `setAllConfig`;
  6. `Response has no supported checksum` | S3-совместимое хранилище без контрольных сумм | норма, не ошибка.

- [ ] **Step 4: Написать `REFERENCE.md`**

Разделы §1–§7 (заголовки из Interfaces). В каждом — объяснение и фрагменты кода, обобщённые из `infra/pulumi/bootstrap/`:
- §1: `Pulumi.yaml` с `packagemanager: bun` и `packages.<имя>.source: terraform-provider` + `parameters`; `pulumi install` генерирует `sdks/`; `.gitignore` (`node_modules/`, `sdks/`, файл экспорта); `tsconfig.json` `include` только программы (тесты запускает bun); `package.json` с `"@pulumi/<имя>": "file:sdks/<имя>"`.
- §2: `pulumi.all([...]).apply(async ...)` с `if (pulumi.runtime.isDryRun()) return …;` для сетевых шагов; ранняя проверка окружения до создания провайдеров (функция вида `credentialsFromEnv(process.env)` с понятной ошибкой); `pulumi.secret`, `pulumi.interpolate`; ссылка на `pulumi-best-practices` для общей теории Output.
- §3: `protect` (что делает, destroy останавливается), `deleteBeforeReplace` (когда нужен: фиксированный порт, boot-диск, уникальное имя), `ignoreChanges` (напр. `imageId`), `import` (временно), `aliases` (переименование логического имени без пересоздания), смена отображаемого имени ресурса (`name`) — обновление на месте, а смена логического имени — пересоздание.
- §4: полный пример теста на моках: `pulumi.runtime.setAllConfig({...})`, `pulumi.runtime.setMocks({newResource, call}, "<project>", "<stack>", true)` — preview-режим, чтобы побочные эффекты под `isDryRun` не выполнялись; `await import("./index")`; хелпер `value = o => new Promise(r => o.apply(v => { r(v); return v; }))`; проверка `isSecret`; тест «без окружения» через `Bun.spawnSync(["bun", "-e", script], { env: { PATH, HOME } })` и проверка `stderr`; мутационная проверка (временно сломать код → тест падает → вернуть).
- §5: DIY-backend в S3 (`pulumi login "s3://<bucket>/<prefix>?region=<r>&endpoint=<host>&s3ForcePathStyle=true"`), префиксы на проект, `pulumi login` глобален; перенос: `stack export --show-secrets --file x.json` (файл с секретами в открытом виде — в `.gitignore`) → `login` в новый backend → `stack init <имя> --secrets-provider passphrase` → `stack import --file x.json` → `preview` без изменений → и **только после сохранения ключей доступа вне стейта** удалить файл и старый стейт; ловушка `file://` на несуществующий каталог; ссылка на `pulumi-cli` для прочих операций со стейтом.
- §6: импорт существующего ресурса: временно добавить `{ import: "<id>" }` к ресурсу (для провайдеров, где id импорта нестандартный, — см. документацию провайдера; пример Selectel — `selectel-ops` REFERENCE §3), `preview` показывает `= import`, `up`, убрать `import` из кода, `preview` — без изменений; альтернатива — `pulumi import` CLI.
- §7: bootstrap-стек: бакет стейта нельзя создать в стеке, чей стейт в нём; отдельный маленький стек с локальным стейтом на первый запуск → перенос его стейта в созданный им бакет; долгоживущие ресурсы (стейт, DNS-зона) — в bootstrap, прод — в основном стеке; ключи доступа к стейту не должны существовать только внутри стейта — личные ключи людей (пример реализации — `infra/pulumi/bootstrap/state-key.ts`); Selectel-детали — `selectel-ops` REFERENCE §9–§10.

- [ ] **Step 5: Сверить примеры с рабочим кодом**

Run: `grep -n "setMocks\|Bun.spawnSync\|isDryRun\|credentialsFromEnv" /mnt/f/Github/2026_H2/infra/pulumi/bootstrap/*.ts`
Expected: сигнатуры и порядок аргументов в `REFERENCE.md` совпадают с рабочим кодом (`setMocks(mocks, project, stack, preview)`).

- [ ] **Step 6: Запустить проверку — проходит**

Run: `bash plugins/pulumi/tests/check_docs.sh; echo "exit=$?"; wc -l plugins/pulumi/skills/pulumi-typescript/SKILL.md; claude plugin validate plugins/pulumi 2>&1 | tail -1`
Expected: `exit=0`, ≤ 230 строк, `Validation passed` (предупреждение про version допустимо).

- [ ] **Step 7: Commit**

```bash
git add plugins/pulumi/tests/check_docs.sh plugins/pulumi/skills/pulumi-typescript
git commit -m "feat(pulumi): собственный скилл pulumi-typescript

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: selectel-ops — факты 2026-09-26

**Files:**
- Modify: `plugins/selectel-ops/tests/check_docs.sh`
- Modify: `plugins/selectel-ops/skills/selectel-ops/REFERENCE.md` (§3 DNS, §9 S3, новый `## 10. Проекты`)
- Modify: `plugins/selectel-ops/skills/selectel-ops/SKILL.md` (таблица «Когда что-то не получается», строка в «Куда идти»)

- [ ] **Step 1: Добавить проверки в `check_docs.sh`**

В цикл заголовков `REFERENCE.md` добавить `"## 10. Проекты"`. В цикл строк `REFERENCE.md` добавить: `"Перенести в другой проект"`, `"INFRA_PROJECT_ID"`, `"vpc/resell/v2/projects/<PROJECT_ID>"`, `"X-Token"`, `"a.ns.selectel.ru"`, `"по сроку жизни"`. Добавить проверку `need SKILL.md "Перенести в другой проект"`.

- [ ] **Step 2: Запустить — падает**

Run: `cd plugins/selectel-ops && bash tests/check_docs.sh; echo "exit=$?"`
Expected: список «нет в REFERENCE.md: …», `exit=1`.

- [ ] **Step 3: Дописать тексты**

`REFERENCE.md`:
- §3 DNS: подраздел «Перенос зоны между проектами» — в панели: DNS → Доменные зоны → ⋮ → «Перенести в другой проект»; записи и id зоны сохраняются, NS (`a.ns.selectel.ru` … `d.ns.selectel.ru`) общие для всех проектов — делегирование у регистратора не меняется, задержка только в TTL записей; через API вторую зону с тем же именем в другом проекте не создать (удаление + создание = простой). Импорт зоны в Pulumi: id импорта — имя зоны с точкой (`example.com.`), проект — переменная окружения `INFRA_PROJECT_ID=<PROJECT_ID>` на время `up`.
- новый `## 10. Проекты`: переименование — `PATCH https://api.selectel.ru/vpc/resell/v2/projects/<PROJECT_ID>` с `{"project": {"name": "<новое имя>"}}` (domain-токен), id не меняется → в IaC и конфиге ссылаться на проекты по id; раскладка по сроку жизни: общий проект (стейт Pulumi + DNS-зона, bootstrap-стек), прод (создаёт/удаляет основной стек), регистрация домена (панель; переносимость регистрации между проектами не проверена); статический API-ключ (`X-Token`, профиль владельца → Доступ → API-ключи) — полный доступ ко всему аккаунту без ролей и срока действия: агентам не давать, использовать сервисного пользователя с нужными ролями (для биллинга — отдельная роль).
`SKILL.md`:
- таблица «Когда что-то не получается»: строка `| нужно перенести DNS-зону в другой проект | удаление+создание даёт простой | «Перенести в другой проект» в панели (записи и id сохраняются), затем импорт в Pulumi — REFERENCE §3 |`;
- таблица «Куда идти»: строка `| переименовать проект, разложить проекты | REFERENCE §10 |`.

- [ ] **Step 4: Проверки проходят**

Run: `bash tests/check_docs.sh; echo "exit=$?"; python3 -m unittest discover -s tests -t . 2>&1 | tail -1; wc -l skills/selectel-ops/SKILL.md; cd ../.. && find . -name __pycache__ -prune -exec rm -rf {} +`
Expected: `exit=0`, `OK`, ≤ 230 строк.

- [ ] **Step 5: Commit**

```bash
git add plugins/selectel-ops
git commit -m "docs(selectel-ops): перенос DNS-зоны, импорт в Pulumi, проекты и API-ключи

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: сценарии claude plugin eval для плагина pulumi

**Files:**
- Create: `plugins/pulumi/evals/state-migration/{prompt.md,graders/criteria.md,graders/skill.md}`
- Create: `plugins/pulumi/evals/zone-import/{prompt.md,graders/criteria.md}`
- Create: `plugins/pulumi/evals/missing-env-test/{prompt.md,graders/criteria.md}`
- Modify: `.gitignore` (добавить `evals/results/`)

- [ ] **Step 1: Сценарии**

`evals/state-migration/prompt.md`:
```markdown
---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
---

У нас Pulumi-проект на TypeScript (bun), стейт сейчас в локальном backend `file://~/.pulumi-local`. Мы только что создали S3-бакет `team-state` (S3-совместимое хранилище, endpoint `s3.example-cloud.ru`, регион `r-1`, path-style), а ключи доступа к нему — выходы этого же стека. Распиши по шагам, как перенести стейт стека `main` в этот бакет. Команды не выполняй — только план с командами.
```
`graders/criteria.md`:
```markdown
---
type: llm
weight: 3
---

Ответ хорош, если одновременно:
1. Перенос через `pulumi stack export --show-secrets` → `pulumi login "s3://…"` (с endpoint и path-style) → `pulumi stack init` → `pulumi stack import` → `pulumi preview` без изменений.
2. Явно сказано сохранить ключи доступа к бакету вне стейта (менеджер паролей/личный ключ) ДО удаления файла экспорта и локального стейта — иначе ключи окажутся только внутри недоступного стейта.
3. Файл экспорта назван секретным (секреты в открытом виде) и удаляется после импорта, не коммитится.
Ответ плох, если предлагает удалить локальный стейт/экспорт до сохранения ключей или не упоминает проблему «ключи только в стейте».
```
`graders/skill.md`:
```markdown
---
type: tool_used
tool: Skill
---
```
Формат `graders/skill.md` (`type: tool_used`) взят из справки CLI; если `claude plugin eval` его не принимает (ошибка разбора грейдера) — удалить `skill.md` и записать ruling, остальные грейдеры (`type: llm`) достаточны.

`evals/zone-import/prompt.md`:
```markdown
---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
---

В облаке уже есть DNS-зона `example.org.`, созданная руками в панели. Мы хотим, чтобы ей управлял наш Pulumi-стек на TypeScript (провайдер terraform-bridged, ресурс зоны уже описан в коде с `protect: true`). Как взять существующую зону под управление стека, не пересоздавая её? Команды не выполняй — только план и изменения кода.
```
`evals/zone-import/graders/criteria.md`:
```markdown
---
type: llm
weight: 3
---

Ответ хорош, если: (1) предлагает импорт (опция ресурса `import` или `pulumi import`), а не создание/удаление; (2) `pulumi preview` перед `up` должен показать `import`, без create/delete; (3) после успешного `up` опцию `import` убирают из кода и повторный `preview` — без изменений; (4) `up` — после подтверждения человека. Плох, если предлагает удалить зону и создать заново или оставить `import` в коде навсегда без проверки.
```
`evals/missing-env-test/prompt.md`:
```markdown
---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
---

Pulumi-программа на TypeScript (тесты — `bun test`) при реальном `up` делает сетевые вызовы внутри `apply` под `pulumi.runtime.isDryRun()` и берёт учётные данные из переменных окружения. Напиши тест, который проверяет: если переменные окружения не заданы, программа падает с понятной подсказкой, а не с ошибкой провайдера. Покажи код теста.
```
`evals/missing-env-test/graders/criteria.md`:
```markdown
---
type: llm
weight: 3
---

Ответ хорош, если тест: (1) использует моки Pulumi (`pulumi.runtime.setMocks`) в режиме preview (`true` последним аргументом), чтобы побочные эффекты не выполнялись; (2) запускает программу в отдельном процессе с очищенным окружением (например `Bun.spawnSync` с `env` только из PATH/HOME), потому что модуль программы кэшируется и окружение процесса тестов уже заполнено; (3) проверяет текст подсказки в stderr и ненулевой код. Плох, если проверка ошибки идёт только в режиме up или в том же процессе после import уже загруженного модуля.
```
`.gitignore`: добавить строку `evals/results/`.

- [ ] **Step 2: Прогнать**

Run: `cd /mnt/f/Github/2026_H2/claude-plugins && claude plugin eval plugins/pulumi --runs 1 -j 3 --trust-plugin --no-publish --threshold 0 --json /tmp/claude-1000/-mnt-f-Github-2026-H2-infra/ac9607f3-d6f2-4889-8563-2e9d2b29ec39/scratchpad/pulumi-eval.json 2>&1 | tail -30`
Expected: три сценария, по каждому score с плагином и без и дельта; `tool_used: Skill` срабатывает хотя бы в `state-migration`. Записать итог (score with/without по сценариям) в ledger. Если с плагином не лучше, чем без, по какому-то сценарию — дописать соответствующее правило/пример в `SKILL.md`/`REFERENCE.md` (Task 1 файлы) и прогнать этот сценарий ещё раз (`--case <имя>`); не более одной итерации.

- [ ] **Step 3: Commit**

```bash
git add plugins/pulumi/evals .gitignore
git commit -m "test(pulumi): сценарии plugin eval для pulumi-typescript

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: каталог, общие проверки, публикация, обновление в infra

**Files:**
- Modify: `README.md` (каталог: строка `pulumi-typescript`, раздел тестов)
- Modify: `plugins/pulumi/.claude-plugin/plugin.json` (description упоминает собственный скилл)

- [ ] **Step 1: README и plugin.json**

В таблицу «Каталог» после строки `pulumi-cli` добавить: `| `pulumi` | `pulumi-typescript` | собственный (идеи — [dirien/claude-skills](https://github.com/dirien/claude-skills), текст свой) | MIT |`. В разделе тестов добавить `bash plugins/pulumi/tests/check_docs.sh` и `claude plugin eval plugins/pulumi --runs 1`. В `plugin.json` плагина `pulumi` в `description` дописать «; собственный скилл pulumi-typescript — TypeScript/bun, S3-backend, тесты на моках».

- [ ] **Step 2: Все проверки**

Run: `bash tests/sync_test.sh | tail -1 && bash tests/manifest_test.sh && bash plugins/pulumi/tests/check_docs.sh && (cd plugins/selectel-ops && bash tests/check_docs.sh && python3 -m unittest discover -s tests -t . 2>&1 | tail -1) && claude plugin validate . 2>&1 | tail -1 && scripts/sync.sh && git status --porcelain plugins upstream.json`
Expected: все проходят; `sync.sh` не меняет файлы (пустой `git status` по `plugins`, `upstream.json`), собственный скилл `pulumi-typescript` не тронут и без предупреждения об «осиротевшем» (у него нет LICENSE апстрима).

- [ ] **Step 3: Commit и push**

```bash
find . -name __pycache__ -prune -exec rm -rf {} +
git add README.md plugins/pulumi/.claude-plugin/plugin.json
git commit -m "docs: pulumi-typescript в каталоге маркетплейса

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git push origin main
```

- [ ] **Step 4: Обновить в infra**

Run: `cd /mnt/f/Github/2026_H2/infra && claude plugin marketplace update cdd && claude plugin update pulumi@cdd -s project && claude plugin update selectel-ops@cdd -s project && claude plugin details pulumi@cdd | sed -n '/Component inventory/,/Agents/p'`
Expected: `Skills (6)`, в списке `pulumi-typescript`.
