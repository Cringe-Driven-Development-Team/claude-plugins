---
name: pulumi-typescript
description: Pulumi-программы на TypeScript в репозиториях организации — bun, terraform-bridged провайдеры (packages в Pulumi.yaml, sdks/), DIY-backend стейта в S3, секреты через passphrase, тесты на моках (bun test, setMocks), побочные эффекты под isDryRun, protect/deleteBeforeReplace/import/aliases, перенос стейта между backend, импорт существующих ресурсов, bootstrap-стек. Активируется в каталогах pulumi/ и pulumi/bootstrap/ репозиториев организации: Pulumi.yaml с packagemanager: bun, terraform-bridged провайдеры, DIY S3-backend организации (свой bucket/prefix на стек в Selectel S3) — не по голым командам `pulumi login s3://`, `pulumi stack export/import` или `pulumi import` самим по себе, они общие для любого Pulumi-проекта. Общие вопросы про Output и компоненты — pulumi-best-practices, операции CLI в целом (включая перенос стейта и импорт ресурсов вне контекста этой организации) — pulumi-cli, всё про Selectel — selectel-ops.
---

# Pulumi TypeScript в организации

Как в организации пишут, тестируют и эксплуатируют Pulumi-программы на TypeScript: bun, terraform-bridged
провайдеры, DIY-backend стейта в S3, секреты через passphrase. Примеры обобщены из рабочего кода
`pulumi/bootstrap/`. Детали и полные фрагменты кода — `REFERENCE.md` (ссылки «REFERENCE §N»).

## Когда применять

Пишешь, читаешь или правишь программу Pulumi на TypeScript в репозитории организации: новый ресурс,
тест на моках, перенос стейта, импорт существующего ресурса, диагностика упавшего `preview`/`up`.

## Никогда

1. Не печатаешь секреты в argv, логах или тексте ошибок — только через stdin процесса или
   `pulumi.secret`; чувствительный вывод стека — `stack output --show-secrets`, не догадки по логу.
2. Не запускаешь `up`, `destroy`, `state delete` или `stack rm` без показанного пользователю
   `preview`/плана (для `stack rm` — списка ресурсов в стеке, подтверждающего, что он пуст) и явного
   «да» на него в этой сессии.
3. Не меняешь логическое имя ресурса, чтобы просто переименовать его отображаемое имя — логическое
   имя пересоздаёт ресурс; для переименования — `aliases` (REFERENCE §3).
4. Не удаляешь экспорт стейта (`stack export --show-secrets`) и старый бэкенд, пока ключи доступа к
   новому бэкенду не сохранены вне стейта (REFERENCE §5).
5. Не запускаешь `stack init`/`up` в стеке, пока не убедился, в каком backend он лежит: `pulumi whoami -v`
   показывает ожидаемый Backend URL, `pulumi stack ls` — ожидаемые стеки. Пустой стек поверх живой
   инфраструктуры начнёт создавать всё заново (409, дубли) — REFERENCE §5.
6. Не импортируешь экспорт стейта, сделанный до `destroy` или до других изменений: экспорт — свежий,
   сразу перед переносом; перед импортом — `stack --show-urns` на источнике (REFERENCE §5).

## Проект

`Pulumi.yaml`: `runtime.options.packagemanager: bun` явно, terraform-bridged провайдер — через
`packages.<имя>.source: terraform-provider` и `parameters`; `pulumi install` генерирует `sdks/`,
которые вместе с `node_modules/` идут в `.gitignore`. `tsconfig.json` включает в `include` только
файлы программы — тесты запускает `bun test`, не `tsc`. REFERENCE §1.

## Код

Конфиг — через `cfg.require`/`cfg.getNumber`, не переменные окружения программы. Учётные данные
провайдера — функцией вида `credentialsFromEnv(process.env)`, вызванной до создания провайдеров, с
понятной ошибкой вместо позднего 401. Побочные эффекты (сетевые вызовы, ожидание) внутри `apply` —
под `if (pulumi.runtime.isDryRun()) return …;`, иначе они выполняются и на `preview`. Опции ресурсов —
`protect`, `deleteBeforeReplace`, `ignoreChanges`, временный `import`, `aliases` при переименовании.
API без провайдера — dynamic-ресурс с учёткой из `process.env`, не побочный эффект в `apply`; его
код лежит в стейте, `diff` сравнивает и `__provider`, иначе правка провайдера до `refresh` не доходит.
Явный провайдер на учётке, создаваемой стеком, — через `id` этой учётки. Общая теория `Output`/`apply()` и компонентов — скилл `pulumi-best-practices`. REFERENCE §2–§3.

## Тесты

`bun test` + `pulumi.runtime.setMocks({ newResource, call }, project, stack, true)` — последний
аргумент `true` держит программу в режиме `preview`, чтобы сетевые побочные эффекты под `isDryRun` не
выполнялись при импорте модуля программы в тест. Проверка «без окружения» — отдельным процессом
(`Bun.spawnSync`), а не в том же тесте: модуль читает `process.env` на верхнем уровне при импорте.
Значение `Output<T>` в тесте — через `apply` и `Promise`; секретность — `await output.isSecret`.
Тест «окружение не задано» проверяет в одном `test(...)` ненулевой код процесса и текст подсказки в
`stderr` (а не ошибку провайдера/API). REFERENCE §4.

## Эксплуатация

DIY-backend стейта в S3, отдельный префикс в бакете на проект (`bootstrap/`, `prod/`). Backend прибит к
каталогу проекта полем `backend.url` в `Pulumi.yaml` — глобальный `pulumi login` на такой проект не
влияет и не нужен; проверка — `pulumi whoami -v`, чужой backend — только `PULUMI_BACKEND_URL=<url> pulumi …`.
Перенос стейта между backend и импорт существующего ресурса — REFERENCE §5–§6; bootstrap-стек для
самого бакета стейта — REFERENCE §7. `Pulumi.<stack>.yaml` коммитится: `secure:`-значений в нём нет,
passphrase стеков — длинная случайная (REFERENCE §7). Прочие операции CLI и стейта — скилл
`pulumi-cli`. Всё специфичное для Selectel (S3, DNS, проекты) — скилл `selectel-ops`.

## Когда что-то не получается

| Симптом | Причина | Действие |
|---|---|---|
| `pulumi login file://…` + `stack init` → стек оказался в Pulumi Cloud | каталога нет, `login` упал, CLI без backend'а создал временный аккаунт Pulumi Cloud | `logout`; если стек пуст — удалить его (`stack rm`) после подтверждения человека; `mkdir -p` каталога, повторить `login` |
| `stack output X` выводит `[secret]` (8 символов) | выход секретный (у terraform-bridged провайдеров секретом бывает и access key) | `pulumi stack output X --show-secrets` |
| `open ~/...: no such file or directory` у AWS-провайдера / `pulumi login s3://` | Go SDK читает `~/.aws/config`, `ca_bundle` с `~` не раскрывается | `AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null` |
| замена сервера падает на занятом порте/диске | create-before-delete по умолчанию | `deleteBeforeReplace: true` (и у keypair с фиксированным именем) |
| `no stack named '<стек>' found` | команда смотрит не в тот backend (глобальный `login`, не тот каталог, `PULUMI_BACKEND_URL`) | `pulumi whoami -v`; backend — через `backend.url` в `Pulumi.yaml` (REFERENCE §5) |
| `409 already_exists` на первом `up` нового стека | стейт живой инфраструктуры лежит в другом backend/префиксе | не создавать заново: найти стейт (`whoami -v`, `stack ls` в каждом backend) и перенести (REFERENCE §5) |
| `401` на каждом вызове провайдера после `stack import` | импортирован устаревший экспорт: учётка провайдера из него уже удалена | не `up`: `stack rm --force` и перенос свежего экспорта или стек с нуля (REFERENCE §5) |
| `incorrect passphrase` на `stack init` | `encryptionsalt` в `Pulumi.<stack>.yaml` от другой passphrase | командная passphrase в окружение; новый стек — убрать строку `encryptionsalt` (REFERENCE §7) |
| `401` у провайдера на `preview` при частичном стейте | провайдер настроен на ещё не созданного пользователя | вход провайдера через `id` пользователя (REFERENCE §2) |
| `failed to load checkpoint: ... unexpected end of JSON input` | запись стейта прервана, файл стека пустой | ничего не запускать; скопировать `<стек>.json.bak` поверх (REFERENCE §5) |
| `refresh` падает `not found` на удалённом вне Pulumi ресурсе | провайдер не сообщает «ресурса нет» | `pulumi state delete <urn>` (REFERENCE §5) |
| `refresh` падает той же ошибкой dynamic-ресурса после исправления кода, `preview` — `unchanged` | код провайдера исполняется из стейта, `diff` не видит его смену | сравнивать `__provider` в `diff`, затем `up` (REFERENCE §2) |
| `unable to delete resource … marked for protection`, `destroy` ничего не удалил | `protect` проверяется на плане, до любых удалений | `destroy --exclude-protected`; совсем — `state unprotect` и `destroy` (REFERENCE §3) |
| новый ресурс конфликтует со старым, удаляемым в том же `up` | удаления идут после создания | `destroy --target` старого, потом `up` (REFERENCE §3) |
| `Missing required configuration variable` | не задан конфиг стека | `pulumi config set`; в тестах — `setAllConfig` |
| `Response has no supported checksum` | S3-совместимое хранилище без контрольных сумм | норма, не ошибка |
| тест на моках зависает в `beforeAll` (таймаут 5000 мс) | в `preview` выход без значения из моков — unknown, `apply` не вызывается | вернуть из `newResource` значения всех выходов, которых ждёт тест (REFERENCE §4) |

Полный разбор с командами — REFERENCE §5, §7.
