# Pulumi TypeScript: справочник

Подробности к `SKILL.md`. Примеры обобщены из рабочего кода `pulumi/bootstrap/` (задачи по стейту и
DNS-зоне организации) — с плейсхолдерами вместо реальных имён проектов, бакетов и адресов.

## 1. Проект

`Pulumi.yaml` фиксирует пакетный менеджер явно — без этого выбор рантайма может уехать на другой
пакетный менеджер по наличию lock-файла в каталоге:

```yaml
name: <project>
runtime:
  name: nodejs
  options:
    typescript: true
    packagemanager: bun
packages:
  <имя-провайдера>:
    source: terraform-provider
    parameters:
      - <namespace>/<provider>
      - <version>
```

`packages.<имя>.source: terraform-provider` — provider-bridge: Pulumi собирает SDK из провайдера
Terraform. `pulumi install` генерирует пакет в `sdks/<имя>` — каталог невоспроизводим детерминированно между машинами и идёт в `.gitignore` вместе с
`node_modules/`:

```
node_modules/
sdks/
<файл-экспорта-стейта>.json
```

`package.json` ссылается на сгенерированный SDK файловой зависимостью и явно доверяет её
build-скриптам (bun по умолчанию их не запускает для сторонних пакетов):

```json
{
  "dependencies": {
    "@pulumi/<имя>": "file:sdks/<имя>"
  },
  "trustedDependencies": ["@pulumi/<имя>"]
}
```

`tsconfig.json` держит в `include` только файлы самой программы, не тесты — тесты запускает
`bun test` напрямую, ему не нужна компиляция через `tsc`:

```json
{
  "compilerOptions": { "strict": true, "module": "commonjs", "moduleResolution": "node" },
  "include": ["index.ts", "<прочие файлы программы>.ts"]
}
```

`pulumi install` — обязательный первый шаг на каждой машине (CI тоже): без него `sdks/` нет и импорт
пакета падает.

## 2. Output и apply

Общая теория `Output<T>`, `apply()`, `pulumi.interpolate`, `pulumi.secret` и ComponentResource — в
скилле `pulumi-best-practices`; здесь — то, что специфично для программ организации.

Учётные данные провайдера читаются из окружения одной функцией, вызванной до создания любых
провайдеров — если её не хватает, ошибка должна называть источник переменных, а не всплывать позже
как 401 от API или как ошибка конфигурации провайдера:

```typescript
function credentialsFromEnv(env: Record<string, string | undefined>): Credentials {
  const missing = ["OS_USERNAME", "OS_PASSWORD", "OS_DOMAIN_NAME"].filter((k) => !env[k]);
  if (missing.length > 0) {
    throw new Error(`Нет ${missing.join(", ")}: выполните source pulumi/bootstrap/env.sh`);
  }
  return { username: env.OS_USERNAME!, password: env.OS_PASSWORD!, domain: env.OS_DOMAIN_NAME! };
}

const credentials = credentialsFromEnv(process.env); // до `new aws.Provider(...)` и т.п.
```

Побочные эффекты (сетевой вызов, ожидание готовности) внутри `apply` должны сами проверять режим —
`pulumi preview` тоже выполняет тело `apply`, просто с превью-значениями:

```typescript
const ready = pulumi.all([accessKey, secretKey, projectId]).apply(async ([ak, sk, id]) => {
  if (pulumi.runtime.isDryRun()) {
    return ak; // preview: не ходим в сеть, значение не готово по-настоящему
  }
  await initRemoteState(id);
  await waitUntilReady({ accessKey: ak, secretKey: sk });
  return ak;
});
```

Та же ранняя проверка — для переменных окружения, которые провайдер читает сам и которые
конфликтуют с явными аргументами. Пример: terraform-провайдер OpenStack берёт `OS_PROJECT_NAME` как
`tenant_name` рядом с явным `tenantId`, и авторизация падает посреди `up` — программа проверяет
`process.env.OS_PROJECT_NAME` до создания провайдера и падает с подсказкой.

Ожидание готовности (ключа, API) различает «ответ есть, но не тот» и «ответа нет»: `403` —
повторять до таймаута, отсутствие HTTP-ответа (сеть, TLS, нет `curl`) N раз подряд — падать сразу,
иначе `up` ждёт весь таймаут впустую. Нет исполняемого файла (`ENOENT`) — отказ сразу, без попыток.

Секретные значения — `pulumi.secret(value)` явно там, где провайдер сам не помечает выход секретом;
строки из нескольких `Output` — `pulumi.interpolate`, не ручная конкатенация после `apply`.

Явный провайдер на учётке, которую создаёт сам стек (сервисный пользователь и его пароль), должен
ждать создания этой учётки, а не только её входных данных. Имя и пароль известны уже на `preview` —
провайдер настраивается, invoke'и (`getImage`, `getNetwork`) идут от ещё не созданного пользователя и
падают с `401`. С пустого стейта этого не видно (неизвестен id проекта), а при частичном стейте
(после прерванного `up`: проект есть, пользователя нет) `preview` падает. Лечение — завязать вход
провайдера на `id` ресурса:

```typescript
const os = new openstack.Provider("project", {
  userName: pulumi.all([serviceUser.id, serviceUser.name]).apply(([, name]) => name), // ждём создания
  password: password.result,
  tenantId: project.id,
  // ...
});
```

API облака, которых нет в провайдере, — dynamic-ресурс (`pulumi.dynamic.Resource` с
`ResourceProvider`: `create`/`diff`/`update`/`read`/`delete`), а не побочный эффект в `apply`: у него
есть стейт, `diff` и удаление. Правила:
- функции API — отдельно от провайдера, с внедряемым http (`curl` через `execFile`), и тестируются на
  подмене http, как остальной код; dynamic-провайдер — тонкая обёртка;
- учётка — из `process.env` внутри методов провайдера (процесс провайдера запускает `pulumi` с тем же
  окружением), не во входных данных: входы и выходы dynamic-ресурса лежат в стейте открытым текстом;
- `diff` возвращает `replaces` для полей, которые API не меняет на месте, и `deleteBeforeReplace` для
  уникальных имён; `read` возвращает `id: ""`, если ресурса нет, — тогда `refresh` уберёт его из стейта;
- ожидание готовности внешней системы (DNS разошёлся, домен принят) — повтор с таймаутом внутри
  `create`, различая «ещё не готово» (конкретный код ошибки) и прочие ошибки — сразу отказ.

## 3. Опции ресурсов

- `protect: true` — `destroy`/`up` с удалением ресурса останавливаются с ошибкой, пока флаг не снят
  явным изменением кода; ставить на долгоживущие ресурсы (бакет стейта, DNS-зона, общий проект).
- `deleteBeforeReplace: true` — меняет порядок замены на delete-before-create. Нужен, когда у старого
  и нового ресурса конфликт по уникальному внешнему признаку: фиксированный порт, boot-диск сервера,
  уникальное имя — обычная create-before-delete-замена в этих случаях падает, потому что оба
  экземпляра не могут существовать одновременно.
  Проверять и соседние ресурсы с фиксированным именем: keypair с тем же `name` при смене ключа тоже
  упрётся в `409` без `deleteBeforeReplace`. Поле `userData` сервера — ForceNew: любое изменение
  (например, список ключей в cloud-init) пересоздаёт сервер, так что `deleteBeforeReplace` на нём
  нужен всегда, а boot-диск с `deleteOnTermination: false` данные сохраняет.
- Порядок в одном `up`: сначала создаются новые ресурсы, удаления — в конце. Если новый ресурс
  конфликтует со старым, который удаляется (та же DNS-запись другим типом, зона-поддомен, которая
  перекрывает запись родительской зоны), — два шага: `pulumi destroy --target <urn старого>`, потом `up`.
  Ресурсам с уникальным в аккаунте именем (DNS-зона, keypair) при замене — `deleteBeforeReplace: true`.
- ForceNew-поля не брать из data source (`get…Output`), если значение стабильно: ответ API
  сменится — ресурс пересоздастся. Пример: `pool` у floating IP — имя внешней сети из конфига
  (с разумным значением по умолчанию), а не `getNetwork({ external: true }).name`; такой invoke ещё и
  падает, когда внешних сетей несколько.
- `ignoreChanges: ["imageId"]` (пример) — Pulumi перестаёт предлагать замену/обновление ресурса при
  дрейфе этого поля вне Pulumi; типичный случай — поле, которое провайдер или платформа меняет сама.
- `import: "<id-в-облаке>"` — временная опция ресурса, чтобы взять существующий облачный объект под
  управление без пересоздания (детали процесса — §6).
- `aliases: [{ name: "<старое-логическое-имя>" }]` — переименование логического имени ресурса без
  пересоздания. Логическое имя (первый аргумент конструктора) входит в URN — его смена без `aliases`
  Pulumi читает как удаление старого ресурса и создание нового. Отображаемое имя в облаке (поле
  `name`/`bucket`/… во входных данных ресурса) — это обычное поле ресурса: его смена обновляет
  ресурс на месте (если провайдер это поддерживает) и логического имени не касается.

## 4. Тесты

`bun test` с моками Pulumi — без реального облака и без сети. Полный пример:

```typescript
import { beforeAll, describe, expect, test } from "bun:test";
import * as pulumi from "@pulumi/pulumi";

Object.assign(process.env, { OS_USERNAME: "u", OS_PASSWORD: "p", OS_DOMAIN_NAME: "1" });
pulumi.runtime.setAllConfig({ "<project>:bucketName": "<bucket>" });

const created = new Map<string, { type: string; inputs: Record<string, any> }>();
pulumi.runtime.setMocks(
  {
    newResource(args) {
      created.set(args.name, { type: args.type, inputs: args.inputs });
      // в preview выход без значения из моков — unknown: apply по нему не вызывается и ожидание в
      // beforeAll зависнет. Выходы, которых ждёт тест, должны получить значения здесь.
      return { id: args.id || `${args.name}-id`, state: { ...args.inputs, accessKey: "AK", secretKey: "SK" } };
    },
    call: (args) => args.inputs,
  },
  "<project>", // имя проекта Pulumi.yaml
  "<stack>",   // имя стека
  true,        // preview: тело `apply` видит isDryRun() === true
);

type Stack = typeof import("./index");
let stack: Stack;
const value = <T>(o: pulumi.Output<T>) =>
  new Promise<T>((resolve) => o.apply((v) => { resolve(v); return v; }));

beforeAll(async () => {
  stack = await import("./index"); // импорт модуля выполняет тело программы один раз
  // регистрация мок-ресурсов асинхронна: без ожидания выходов created.get(...) в первом тесте может
  // быть пуст. Ждите выходы, которые зависят от проверяемых ресурсов (надёжнее — все выходы стека).
  await Promise.all([value(stack.stateSecretKey), value(stack.versioningStatus), value(stack.stateProjectId)]);
});

describe("стек", () => {
  test("бакет создан с именем из конфига", () => {
    expect(created.get("state-bucket")!.inputs.bucket).toBe("<bucket>");
  });
  test("секретный выход помечен секретом", async () => {
    expect(await stack.stateSecretKey.isSecret).toBe(true);
  });
});
```

`setMocks(mocks, project, stack, preview)` — четвёртый аргумент `true` держит `isDryRun()` истинным
внутри `apply`, поэтому сетевые шаги из §2 (`if (pulumi.runtime.isDryRun()) return …`) в тесте не
выполняются; `false` или отсутствие аргумента эмулирует реальный `up`.

`value()` — стандартный хелпер, чтобы дождаться значения `Output<T>` в тесте через `apply` и
`Promise`; `isSecret` — асинхронное свойство `Output`, проверяется так же через `await`.

Ошибку «нет окружения» нельзя проверить в том же тестовом процессе: модуль программы уже импортирован
с нужными `OS_*` в переменных окружения для остальных тестов файла, а `require`/`import` в Node
кешируется — повторный импорт не перевыполнит тело модуля. Проверка — отдельный процесс без этих
переменных:

```typescript
test("без окружения падает с понятной ошибкой", () => {
  const script = `
    const pulumi = require("@pulumi/pulumi");
    pulumi.runtime.setAllConfig({ "<project>:bucketName": "b" });
    pulumi.runtime.setMocks({ newResource: (a) => ({ id: a.name + "-id", state: a.inputs }), call: (a) => a.inputs },
      "<project>", "<stack>", true);
    require("./index");
  `;
  const env = { PATH: process.env.PATH ?? "", HOME: process.env.HOME ?? "" }; // без OS_*
  const run = Bun.spawnSync(["bun", "-e", script], { cwd: import.meta.dir, env });
  expect(run.exitCode).not.toBe(0);
  expect(run.stderr.toString()).toContain("source pulumi/bootstrap/env.sh");
});
```

Мутационная проверка теста (сам тест на самопроверку, не входит в постоянный набор): временно
сломать код, который тест должен ловить (например, убрать `if (pulumi.runtime.isDryRun())` или
поменять ожидаемое имя поля), запустить `bun test` и увидеть красный результат, затем вернуть код —
подтверждает, что тест действительно проверяет то, что должен, а не проходит вхолостую.

## 5. Backend и перенос стейта

DIY-backend стейта — S3-совместимое хранилище, без Pulumi Cloud:

```
pulumi login "s3://<bucket>/<prefix>?region=<region>&endpoint=<endpoint>&s3ForcePathStyle=true"
```

`<prefix>` разделяет стейты разных проектов в одном бакете (например, `bootstrap/` для bootstrap-стека
и `prod/` для основного — не `main/`: это слово и так значит ветку и имя стека).

`pulumi login` глобален — запоминается для всех каталогов и терминалов. С двумя проектами в разных
префиксах это ловушка: забыл перелогиниться — `stack init` молча создал стек не там (реальные случаи:
прод-стек в префиксе bootstrap-стека; прод в временном `file://`-backend bootstrap-стека; повтор
«первого запуска» создал пустой bootstrap-стек поверх настоящего). Решение — прибить backend к проекту
в `Pulumi.yaml`:

```yaml
backend:
  url: s3://<bucket>/<prefix>?region=<region>&endpoint=<endpoint>&s3ForcePathStyle=true
```

Тогда `pulumi` в каталоге проекта всегда работает со своим стейтом, `pulumi login` не нужен и на такой
проект не влияет. Перебивает `backend.url` только `PULUMI_BACKEND_URL` — её не задавать постоянно, а
для разовой работы с чужим backend (перенос) — префиксом одной команды. Проверка перед любой записью:
`pulumi whoami -v` (строка `Backend URL`) и `pulumi stack ls`.

Перенос стейта между backend (например, из старого хранилища в новый бакет, или между `file://` и
S3). С `backend.url` в `Pulumi.yaml` источник читается через `PULUMI_BACKEND_URL`, приёмник — по
умолчанию:

```bash
# старый backend: сначала посмотреть, что в стеке, и сделать СВЕЖИЙ экспорт
PULUMI_BACKEND_URL=<старый-url> pulumi stack --show-urns -s <имя>
PULUMI_BACKEND_URL=<старый-url> pulumi stack export -s <имя> --show-secrets --file state.json
# секреты в файле — в открытом виде; шаблон *-export.json / state.json — в .gitignore

# новый backend (из backend.url; без него — pulumi login "s3://<bucket>/<prefix>?…")
pulumi whoami -v                                        # Backend URL — ожидаемый
pulumi stack init <имя> --secrets-provider passphrase   # та же PULUMI_CONFIG_PASSPHRASE, что была у
                                                         # старого стека — иначе secure-значения в
                                                         # Pulumi.<stack>.yaml не расшифруются
pulumi stack import --file state.json
pulumi preview                                          # ожидается: без изменений

# только после того, как ключи доступа к новому backend сохранены отдельно от стейта:
rm state.json
# старый backend/стейт выводятся из эксплуатации только после того, как `pulumi preview` на новом
# backend подтвердил отсутствие изменений И человек явно подтвердил («да») это решение
```

`preview` без изменений после `stack import` — единственное надёжное подтверждение, что перенос не
потерял и не исказил ресурсы. Файл экспорта с `--show-secrets` — открытый текст: удалять его можно
только после того, как ключи доступа к новому backend уже сохранены не внутри самого стейта (§7).
`stack init --secrets-provider passphrase` в новом backend должен использовать ту же passphrase, что и
старый стек (`PULUMI_CONFIG_PASSPHRASE`) — иначе secure-значения в `Pulumi.<stack>.yaml` не
расшифруются при импорте. Вывод старого backend (и его стейта) из эксплуатации — только после того,
как `preview` на новом backend показал отсутствие изменений, и только после явного подтверждения
человека, а не сразу по факту успешного `stack import`.

Экспорт делается непосредственно перед импортом. Импорт экспорта, сделанного до `destroy` (или до
любого `up`), кладёт в новый backend ресурсы, которых в облаке уже нет или которые другие: провайдер
на учётке из этих ресурсов получает `401` на каждом вызове, а `refresh` не помогает по той же причине.
Лечение — не `up`: `pulumi stack rm --force` (удаляет только запись стейта) и заново — перенос свежего
экспорта или стек с нуля, если облако уже пусто.

Ловушка: `pulumi login file://<несуществующий каталог>` завершается ошибкой, но некоторые версии CLI
после неё тихо используют Pulumi Cloud как backend по умолчанию — следующий `stack init` создаёт
стек там, а не локально. Каталог для `file://` — создавать заранее (`mkdir -p`) и после `login`
проверять `pulumi whoami --verbose`/`pulumi stack` на ожидаемый backend, а не только код возврата.

Пустой или обрезанный стейт — `failed to load checkpoint: ... unexpected end of JSON input`: запись
стейта прервали (Ctrl+C во время `up`/`refresh`), `.pulumi/stacks/<проект>/<стек>.json` в бакете —
0 байт. Рядом `<стек>.json.bak` — предыдущий checkpoint (Pulumi копирует его перед каждой записью), а в
`.pulumi/history/` и `.pulumi/backups/` — более старые. Восстановление — до любой следующей
записывающей команды (она скопирует пустой файл поверх `.bak`): скачать `.bak`, проверить (валидный
JSON, `checkpoint.latest.resources`, время), затем скопировать его поверх `<стек>.json` в бакете и
проверить `pulumi stack --show-urns`. `stack import` не годится — он сначала загружает сломанный стейт.

`refresh` не убирает ресурс, удалённый вне Pulumi, если провайдер на чтение отвечает ошибкой
(`not found`), а не пустым результатом (так делают, например, DNS-ресурсы terraform-bridged провайдера
Selectel): `refresh` падает. Такие записи — `pulumi state delete <urn>` (зависимые — первыми, с
`protect` — сначала `state unprotect`), затем `refresh --clear-pending-creates`, если висит прерванное
создание.

Прочие операции со стейтом (state delete/move/repair, refresh, targeted operations, CI-настройка) —
скилл `pulumi-cli`.

## 6. Импорт

Взять существующий облачный ресурс под управление Pulumi без пересоздания — двумя способами.

Способ через временную опцию ресурса в коде (предпочтителен, когда ресурс уже описан в программе):

1. Добавить `{ import: "<id-в-облаке>" }` к опциям ресурса. Формат `<id>` — свой у каждого
   провайдера (не всегда совпадает с полем `id` в панели облака); для нестандартных id — смотреть
   документацию конкретного провайдера (пример для Selectel — скилл `selectel-ops`, REFERENCE §3).
2. `pulumi preview` — должен показать `= import` (импорт без изменения свойств); расхождения полей
   значат, что аргументы ресурса в коде не совпадают с реальным состоянием, их нужно поправить.
3. `pulumi up` — ресурс переходит под управление Pulumi.
4. Убрать `import` из опций ресурса (иначе следующий `up` попробует импортировать снова).
5. `pulumi preview` — ожидается: без изменений.

Альтернатива — CLI-команда `pulumi import`, когда ресурса ещё нет в коде программы (генерирует
код-заглушку и импортирует за один шаг); подробности флагов и bulk-импорт из файла — скилл
`pulumi-cli`.

## 7. Bootstrap-стек

Бакет стейта Pulumi нельзя создать в стеке, чей собственный стейт лежит в этом же бакете — на первом
`up` бакета ещё не существует. Паттерн — отдельный маленький bootstrap-стек:

1. Первый запуск — с локальным (или иным временным) backend: `pulumi login file://<каталог>`,
   `pulumi stack init <имя> --secrets-provider passphrase`, `pulumi up` — создаёт бакет и то, что
   рядом с ним логически долгоживёт (например, DNS-зону домена организации).
2. Перенос собственного стейта bootstrap-стека в только что созданный им бакет — процедура §5, под
   отдельным префиксом (например, `bootstrap/`, отдельно от `main/` основного стека).
3. Дальше bootstrap-стек эксплуатируется как обычный: `source env.sh` (переменные окружения
   провайдера, passphrase, личный ключ доступа), `pulumi preview`/`up` — backend из `backend.url`
   в `Pulumi.yaml` (§5).

4. Временный `file://`-backend удалять только тогда, когда из него перенесены **все** стеки, и оба
   `preview` на новом месте прошли без изменений: пока глобальный `login` смотрит в него, туда
   молча попадают и другие стеки (§5).
5. «Первый запуск» — история, не инструкция: повтор на уже поднятой организации создаёт пустой стек
   поверх настоящего или упирается в `409` на уже существующих проекте, бакете, зоне. Если бакет
   стейта пропал (`NoSuchBucket`) — сначала проверить в облаке, что пропало всё (проект, зона,
   сервисный пользователь), убрать остатки, и только потом поднимать заново; id нового проекта
   стейта — обновить везде, где он записан (например, `env.sh`), иначе выпуск личных ключей
   ответит `404 PROJECT_NOT_FOUND`.

Passphrase и `encryptionsalt`. `stack init` пишет в `Pulumi.<stack>.yaml` `encryptionsalt`, привязанный
к passphrase; `init`/`import` с другой passphrase — `incorrect passphrase`. Поэтому одна командная
passphrase для всех стеков (в менеджере паролей), а при сознательной смене — строку `encryptionsalt`
удалить до `stack init` и раздать новую passphrase. `Pulumi.<stack>.yaml` коммитится (без него у коллег
не работает `preview`), но в публичном репо `encryptionsalt` сам по себе позволяет офлайн-перебор
passphrase — она длинная и случайная, а `secure:`-значений в файле нет (`grep -n 'secure:'` перед
`git add`; учётки провайдеров — из окружения, не из конфига стека).

Долгоживущие ресурсы, которые нужны инфраструктуре организации целиком (бакет стейта, DNS-зона
основного домена, общий облачный проект), — в bootstrap-стеке с `protect: true`; ресурсы продукта
(серверы, записи в зоне, отдельный проект под прод) — в основном стеке, который читает выходы
bootstrap-стека через `pulumi -C <bootstrap> stack output <имя>` и/или конфиг.

Ключи доступа к backend стейта не должны существовать только внутри самого стейта — иначе получить
их для переноса или восстановления можно только имея уже рабочий доступ к стейту (замкнутый круг), и
единственная копия ключа пропадает вместе с потерей доступа к бакету. Ключ каждого человека — личный,
выпущенный на bootstrap-ресурсы отдельным скриптом вне Pulumi (в рабочем коде — `state-key.ts`) и
хранящийся у человека локально, а не в стейте и не переданный из рук в руки. Детали выпуска и
хранения S3-ключей, DNS-зоны и облачных проектов Selectel — скилл `selectel-ops`, REFERENCE §9–§10.
