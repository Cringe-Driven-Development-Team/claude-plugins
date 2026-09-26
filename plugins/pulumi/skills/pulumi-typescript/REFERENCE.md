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
Terraform. `pulumi install` генерирует пакет в `sdks/<имя>` (и/или `.pulumi/`, в зависимости от
версии CLI) — каталог невоспроизводим детерминированно между машинами и идёт в `.gitignore` вместе с
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

Секретные значения — `pulumi.secret(value)` явно там, где провайдер сам не помечает выход секретом;
строки из нескольких `Output` — `pulumi.interpolate`, не ручная конкатенация после `apply`.

## 3. Опции ресурсов

- `protect: true` — `destroy`/`up` с удалением ресурса останавливаются с ошибкой, пока флаг не снят
  явным изменением кода; ставить на долгоживущие ресурсы (бакет стейта, DNS-зона, общий проект).
- `deleteBeforeReplace: true` — меняет порядок замены на delete-before-create. Нужен, когда у старого
  и нового ресурса конфликт по уникальному внешнему признаку: фиксированный порт, boot-диск сервера,
  уникальное имя — обычная create-before-delete-замена в этих случаях падает, потому что оба
  экземпляра не могут существовать одновременно.
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
      return { id: args.id || `${args.name}-id`, state: { ...args.inputs, accessKey: "AK" } };
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

`<prefix>` разделяет стейты разных стеков/проектов в одном бакете (например, `bootstrap/` для
bootstrap-стека и `main/` для основного). `pulumi login` — глобальная команда процесса: перед работой
с другим стеком нужен `login` в его префикс, иначе `stack select`/`preview` пойдут не в тот backend.

Перенос стейта между backend (например, из старого хранилища в новый бакет, или между `file://` и
S3):

```bash
# старый backend
pulumi stack export --show-secrets --file state.json   # секреты в файле — в открытом виде
# .gitignore обязателен для этого файла

# новый backend
pulumi login "s3://<bucket>/<prefix>?region=<region>&endpoint=<endpoint>&s3ForcePathStyle=true"
pulumi stack init <имя> --secrets-provider passphrase
pulumi stack import --file state.json
pulumi preview                                          # ожидается: без изменений

# только после того, как ключи доступа к новому backend сохранены отдельно от стейта:
rm state.json
# и вывести из эксплуатации старый backend/стейт
```

`preview` без изменений после `stack import` — единственное надёжное подтверждение, что перенос не
потерял и не исказил ресурсы. Файл экспорта с `--show-secrets` — открытый текст: удалять его можно
только после того, как ключи доступа к новому backend уже сохранены не внутри самого стейта (§7).

Ловушка: `pulumi login file://<несуществующий каталог>` завершается ошибкой, но некоторые версии CLI
после неё тихо используют Pulumi Cloud как backend по умолчанию — следующий `stack init` создаёт
стек там, а не локально. Каталог для `file://` — создавать заранее (`mkdir -p`) и после `login`
проверять `pulumi whoami --verbose`/`pulumi stack` на ожидаемый backend, а не только код возврата.

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
   провайдера, passphrase, личный ключ доступа), `pulumi login`, `pulumi preview`/`up`.

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
