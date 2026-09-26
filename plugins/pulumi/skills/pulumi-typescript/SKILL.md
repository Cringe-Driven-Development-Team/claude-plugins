---
name: pulumi-typescript
description: Pulumi-программы на TypeScript в репозиториях организации — bun, terraform-bridged провайдеры (packages в Pulumi.yaml, sdks/), DIY-backend стейта в S3, секреты через passphrase, тесты на моках (bun test, setMocks), побочные эффекты под isDryRun, protect/deleteBeforeReplace/import/aliases, перенос стейта между backend, импорт существующих ресурсов, bootstrap-стек. Активируется при работе с pulumi/ и pulumi/bootstrap/ в репо организации, Pulumi.yaml с packagemanager bun, pulumi login s3://, pulumi stack export/import, pulumi import. Общие вопросы про Output и компоненты — pulumi-best-practices, операции CLI в целом — pulumi-cli, всё про Selectel — selectel-ops.
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
2. Не запускаешь `up`, `destroy` или `state delete` без показанного пользователю `preview` и явного
   «да» на него в этой сессии.
3. Не меняешь логическое имя ресурса, чтобы просто переименовать его отображаемое имя — логическое
   имя пересоздаёт ресурс; для переименования — `aliases` (REFERENCE §3).
4. Не удаляешь экспорт стейта (`stack export --show-secrets`) и старый бэкенд, пока ключи доступа к
   новому бэкенду не сохранены вне стейта (REFERENCE §5).

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
Общая теория `Output`/`apply()` и компонентов — скилл `pulumi-best-practices`. REFERENCE §2–§3.

## Тесты

`bun test` + `pulumi.runtime.setMocks({ newResource, call }, project, stack, true)` — последний
аргумент `true` держит программу в режиме `preview`, чтобы сетевые побочные эффекты под `isDryRun` не
выполнялись при импорте модуля программы в тест. Проверка «без окружения» — отдельным процессом
(`Bun.spawnSync`), а не в том же тесте: модуль читает `process.env` на верхнем уровне при импорте.
Значение `Output<T>` в тесте — через `apply` и `Promise`; секретность — `await output.isSecret`.
Тест «переменные окружения не заданы» в одном `test(...)` проверяет все три вещи сразу: (1) моки в
режиме `preview` (`true`), чтобы дело не дошло до реального сетевого вызова; (2) отдельный процесс с
очищенным `env` (`PATH`/`HOME`, без `OS_*`), потому что модуль программы кешируется; (3) ненулевой
код возврата процесса и текст понятной подсказки в `stderr` (а не ошибку провайдера/API). REFERENCE §4.

## Эксплуатация

DIY-backend стейта в S3 (`pulumi login "s3://…?...&s3ForcePathStyle=true"`), отдельный префикс в
бакете на проект/стек. Перенос стейта между backend и импорт существующего ресурса — REFERENCE §5–§6;
bootstrap-стек для самого бакета стейта — REFERENCE §7. Прочие операции CLI и стейта — скилл
`pulumi-cli`. Всё специфичное для Selectel (S3, DNS, проекты) — скилл `selectel-ops`.

## Когда что-то не получается

| Симптом | Причина | Действие |
|---|---|---|
| `pulumi login file://…` + `stack init` → стек оказался в Pulumi Cloud (временный агентский аккаунт) | каталога нет, `login` упал, CLI откатился на Cloud | удалить стек (`stack rm`), `logout`, `mkdir -p` каталога, повторить `login` |
| `stack output X` выводит `[secret]` (8 символов) | выход секретный (у terraform-bridged провайдеров секретом бывает и access key) | `pulumi stack output X --show-secrets` |
| `open ~/...: no such file or directory` у AWS-провайдера / `pulumi login s3://` | Go SDK читает `~/.aws/config`, `ca_bundle` с `~` не раскрывается | `AWS_CONFIG_FILE=/dev/null AWS_SHARED_CREDENTIALS_FILE=/dev/null` |
| замена сервера падает на занятом порте/диске | create-before-delete по умолчанию | `deleteBeforeReplace: true` |
| `Missing required configuration variable` | не задан конфиг стека | `pulumi config set`; в тестах — `setAllConfig` |
| `Response has no supported checksum` | S3-совместимое хранилище без контрольных сумм | норма, не ошибка |

Полный разбор с командами — REFERENCE §5, §7.
