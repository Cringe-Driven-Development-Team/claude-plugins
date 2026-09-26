# Собственный скилл pulumi-typescript и актуализация selectel-ops

Дата: 2026-09-26. Статус: утверждено.

## Цель

Знания, полученные на практике при создании bootstrap-стека в `infra` (задачи #5, #7), попадают в
плагины `cdd`, чтобы следующий агент не повторял те же ошибки. Вместо отказа от
`dirien/pulumi-typescript` (построен вокруг Pulumi ESC и AWS/Azure/GCP) — свой скилл под наш стек:
TypeScript + bun, Selectel/OpenStack (terraform-bridged провайдеры), DIY-backend в S3, секреты через
passphrase.

## Решения

- Один собственный скилл `pulumi-typescript` в плагине `pulumi` (не в `upstream.json`, `sync.sh` его
  не трогает): написание, тесты и эксплуатация Pulumi-программ на TypeScript в организации.
- Текст свой; примеры — из `infra/pulumi/bootstrap/` (рабочий код с тестами). Текст
  `dirien/claude-skills` не копируется; в README плагина — ссылка на него как источник идей.
- Селектел-специфика — в `selectel-ops`; в `pulumi-typescript` — ссылки на него.
- Граница с upstream-скиллами: общие вопросы об `Output`/компонентах — `pulumi-best-practices`,
  стандартные операции CLI — `pulumi-cli`; в тексте явные отсылки.

## pulumi-typescript

Структура: `plugins/pulumi/skills/pulumi-typescript/{SKILL.md,REFERENCE.md}`,
`plugins/pulumi/tests/check_docs.sh`.

`SKILL.md` (не длиннее 230 строк):
1. Когда применять — программа Pulumi на TypeScript в репо организации.
2. Никогда: секреты в argv/логах/ошибках (только stdin, `pulumi.secret`); `up`/`destroy`/
   `state delete` без «да» на показанный `preview`; смена логических имён (для этого `aliases`);
   удаление экспорта стейта, пока ключи доступа не сохранены вне стейта.
3. Проект: `Pulumi.yaml` (`packagemanager: bun`, `packages` c `source: terraform-provider`),
   `pulumi install`, `sdks/` в `.gitignore`, `tsconfig` включает только программу.
4. Код: `cfg.require` для конфига, учётные данные из окружения с ранней проверкой; побочные эффекты
   в `apply` под `pulumi.runtime.isDryRun()`; опции `protect`, `deleteBeforeReplace` (фиксированные
   порты/диски), `ignoreChanges`, `import`; смена имени ресурса «на месте» против пересоздания.
5. Тесты: `bun test` + `pulumi.runtime.setMocks(..., preview=true)`; ошибка при отсутствии окружения —
   в отдельном процессе (`Bun.spawnSync`); мутационная проверка.
6. Эксплуатация: DIY-backend в S3; bootstrap-паттерн; перенос стейта
   (`stack export --show-secrets` → `login` → `stack init` → `stack import` → `preview` без изменений);
   импорт существующего ресурса (временный `import` → `up` → убрать → `preview` без изменений);
   `stack output --show-secrets` для секретных выходов.
7. Симптом → причина → действие: временный аккаунт Pulumi Cloud после `login file://` на
   несуществующий каталог; `[secret]` вместо значения; `~/.aws` с `ca_bundle = ~/…` ломает Go SDK;
   create-before-delete на занятом порте/диске; `Missing required configuration variable`;
   `Response has no supported checksum`.

`REFERENCE.md`: §1 проект, §2 Output/apply/async, §3 опции ресурсов, §4 тесты (полные примеры),
§5 backend и перенос стейта, §6 импорт, §7 bootstrap-паттерн.

## selectel-ops

Дописать в `REFERENCE.md` (§3 DNS, §9 S3, новый §10 «Проекты») и таблицу ошибок `SKILL.md`:
- перенос DNS-зоны между проектами в панели («Перенести в другой проект») сохраняет записи и id;
  через API вторую зону с тем же именем в другом проекте не создать;
- импорт зоны в Pulumi: id импорта = имя зоны с точкой, проект — `INFRA_PROJECT_ID`;
- NS Selectel (`a/b/c/d.ns.selectel.ru`) общие для всех проектов: пересоздание/перенос зоны не
  требует смены делегирования, задержка — только TTL записей;
- переименование проекта: `PATCH /vpc/resell/v2/projects/<id>` с `{"project":{"name":…}}`, id не
  меняется — ссылаться на проекты по id;
- раскладка проектов по сроку жизни: общий (стейт + зона, bootstrap-стек), прод (основной стек),
  регистрация домена;
- статический API-ключ (`X-Token`) владельца против сервисного пользователя: для агентов — только
  сервисный пользователь с нужными ролями.

## Проверка

1. `check_docs.sh` для `pulumi-typescript`: разделы `SKILL.md`/`REFERENCE.md`, ключевые факты
   (`isDryRun`, `deleteBeforeReplace`, `--show-secrets`, `file://`, `setMocks`, `import`), длина
   `SKILL.md` ≤ 230, нет идентификаторов стенда (IPv4, 32-hex, номера аккаунтов). Для `selectel-ops` —
   новые факты в существующий `check_docs.sh`. Проверки пишутся до текста.
2. `claude plugin eval` в `plugins/pulumi/evals/`, три сценария с ablation (без плагина):
   перенос стейта в S3 (не удаляет экспорт до сохранения ключей, не делает `up` без «да»);
   импорт существующей зоны (временный `import`, затем убрать, `preview` без изменений);
   тест на отсутствие окружения (preview-режим, отдельный процесс).
3. `claude plugin validate .`, `tests/manifest_test.sh`, `tests/sync_test.sh`; после пуша —
   `claude plugin marketplace update cdd` в `infra` и проверка состава плагинов.
