---
name: ansible-org
description: Ansible в репозиториях организации — подводные камни, на которых уже падали: YAML-условия с «: » и обратные слеши в регулярках (разное поведение ansible-core 2.17/2.19+), ansible-lint (name[casing], var-naming[no-role-prefix]), ansible_user против remote_user, authorized_key с exclusive, sshd на Ubuntu 24.04 (ssh.socket), Docker и ufw, Docker Compose через community.docker, осмысленные проверки verify.yml, установка ansible-core и openstacksdk через pipx. Активируется при работе с каталогом ansible/ репозитория организации (роли, site.yml, bootstrap.yml, verify.yml, inventory openstack.cloud). Ревью по Red Hat CoP целиком — ansible-good-practices; всё про Selectel (inventory, clouds.yaml, OS_*) — selectel-ops.
---

# Ansible в организации

Правила, выведенные из реальных ошибок в `ansible/` инфраструктурного репо. Дополняет
`ansible-good-practices` (общее ревью по Red Hat CoP) и `selectel-ops` (облако, inventory, `OS_*`).

## Когда применять

Пишешь или правишь роль, плейбук, `verify.yml`, inventory; разбираешь упавший прогон или ansible-lint.

## Никогда

1. Не пишешь в YAML условие с «: » без кавычек целиком — `- x is search('^Status: active$')` YAML
   разбирает как словарь. ansible-core 2.19+ падает (`Conditional expressions must be strings`),
   2.17 молча считал такое условие **всегда истинным**. Кавычки: `- "x is search('^Status: active$')"`.
2. Не пишешь регулярки с `\` в шаблонах и условиях: экранирование разное в `{{ }}`, в `that:`/`when:`
   и между версиями ansible-core (`'\1'` может превратиться в `\x01`, `'\\s'` — в буквальный `\s`).
   Замены без слешей: `[ ]+` вместо `\s+`, `[(]` вместо `\(`, `regex_search('^[^ ]+')` вместо
   `regex_replace('^(\S+)\s.*', '\1')`.
3. Не включаешь `exclusive: true` в `authorized_key`, не проверив, что ключ того, кто запускает
   плейбук, есть в итоговом списке: иначе следующий вход под этим пользователем не пройдёт, а
   root-логин уже закрыт — останется консоль в панели.
4. Не публикуешь порты контейнеров на все интерфейсы и на приватный адрес сервера с floating IP: Docker
   открывает их в обход ufw (см. «Docker»).

## Подключение и доступ

- `ansible_user` (переменная подключения) перекрывает `remote_user` плейбука. В плейбуке, который
  ходит под другим пользователем (первичный `bootstrap.yml` под `root`), задавать `vars:
  ansible_user: root`, а не `remote_user`.
- Опции ssh для jump-хоста — `ProxyCommand="ssh -W %h:%p -i … -o IdentitiesOnly=yes …"`, не
  `ProxyJump`: `-o` из командной строки на хоп через `-J` не действуют.
- `IdentitiesOnly=yes` в `ansible.cfg` — при `MaxAuthTries` ssh-агент с несколькими ключами иначе
  исчерпает попытки до нужного (`Too many authentication failures`).
- Первичный плейбук под `root` работает только на чистом диске: после hardening root-логин закрыт.
  Новый хост — `--limit <хост>`; сервер, пересозданный IaC с сохранённым boot-диском, уже настроен —
  ему хватает основного `site.yml`.

## sshd на Ubuntu 24.04

- sshd запускается socket-активацией: порт слушает `ssh.socket`, конфиг читает `ssh.service`.
  Хендлер: если `ssh.socket` активен — рестарт `ssh.socket` и `ssh.service`, иначе только
  `ssh.service`. Статус — `ansible.builtin.systemd_service` без `state` (читает статус и не падает на
  отсутствующем юните), не `command: systemctl is-active` (ansible-lint `command-instead-of-module`).
- Drop-in `sshd_config.d/00-*.conf` с `validate: /usr/sbin/sshd -t -f %s`: sshd берёт первое значение
  директивы, файл с меньшим номером выигрывает.
- Итоговую проверку делать через `sshd -T`, а не по тексту файлов.

## Docker

- Опубликованный порт (`ports:`/`-p`) — DNAT в цепочке `nat/DOCKER`, раньше ufw: `deny incoming` его не
  закрывает. Floating IP — 1:1 DNAT на приватный адрес сервера, поэтому и `-p <приватный-ip>:…` на
  сервере с floating IP смотрит в интернет. Наружу публикуется только прокси (80/443); API и БД —
  во внутренней сети Compose без `ports:`, прокси ходит к ним по имени сервиса.
- Фильтр-страховка — цепочка `DOCKER-USER`, правило вставлять `-I` (после `-A` оно окажется за
  `RETURN`); в `DOCKER-USER` порт уже после DNAT. Правило `iptables` не переживает перезагрузку.
- Проект Compose раскладывать ролью и поднимать `community.docker.docker_compose_v2`
  (`project_src`, `state: present`) — идемпотентно, в отличие от `command: docker compose up -d`.
  Модулю нужен только Docker CLI с compose-плагином, Python-SDK Docker — нет.
- Конфиг в контейнер монтировать **каталогом**, не файлом: `template`/`copy` заменяют файл атомарно
  (новый inode), и bind-mount отдельного файла продолжает видеть старую версию.
- Перечитать конфиг без рестарта — хендлер `docker compose exec -T <сервис> <reload>` с
  `chdir: <каталог проекта>`; `validate` шаблона — тем же образом (`docker run --rm -v %s:…`).
- При переносе сервиса с хоста в контейнер — сначала удалить пакет с хоста (он держит порт), потом
  поднимать Compose.

## ansible-lint (профиль production)

- `name[casing]` — имя задачи с заглавной буквы («Файл compose.yml», не «compose.yml»).
- `name[template]` — Jinja только в конце имени задачи.
- `var-naming[no-role-prefix]` — переменные роли с префиксом `<роль>_`. Переменная, общая для
  нескольких ролей (например, каталог проекта Compose), — не в `defaults` одной из них, а в
  `inventory/group_vars/all`.
- `command-instead-of-module` — модуль вместо `command` (см. `systemd_service`).

## Секреты (ansible-vault)

- Открытое имя в `group_vars/all/vars.yml` (`x: "{{ vault_x }}"`), значение — в зашифрованном
  `vault.yml` рядом. Ссылка на переменную, которой в vault нет, не падает, пока её никто не
  использует, — упадёт первый шаблон. Добавил ссылку — тем же PR добавь значение и сверь имена:
  `ansible-vault view …/vault.yml | sed -E 's/:.*//'` (имена без значений).
- Секреты, которые выдаёт инфраструктура (S3-ключ приложения — выход Pulumi), в vault переносятся из
  `pulumi stack output <имя> --show-secrets`, а не генерируются `openssl rand`; после пересоздания
  стека — заново. Несекретные параметры того же сервиса (endpoint, регион, имена бакетов, публичный
  домен) — открыто в `vars.yml`, с пометкой, из какого выхода значение.
- Утечка пароля vault: `rekey` не помогает (старый шифротекст в истории git), меняются сами
  секреты — случайные заменой значения, выданные инфраструктурой перевыпуском там, где выданы
  (скилл `selectel-ops`, S3). В процедуре утечки это отдельный шаг, иначе утёкший ключ остаётся рабочим.
- Правка — `ansible-vault edit`, не `decrypt` → правка → `encrypt` (открытый текст на диске легко
  закоммитить). Без редактора: `{ ansible-vault view f; printf …; } | ansible-vault encrypt --output
  f.new`, сверить старые значения по хэшу расшифрованного, заменить файл.

## verify.yml: проверять настоящее

Проверка, которая проходит всегда, хуже отсутствия проверки. Пример: «приватный IP сервера не
отвечает с управляющей машины» ничего не доказывает — такой адрес не маршрутизируется в принципе.
Проверять:
- по API облака — есть ли у сервера floating IP, в каких сетях его порты, сколько серверов в проекте;
- снаружи — пробой портов публичного адреса: разрешённые открыты (`wait_for`), остальные закрыты
  (`wait_for: state: stopped` — любая ошибка соединения, включая таймаут DROP, считается «закрыт»);
- на хосте — `ufw status verbose` против `firewall_rules`, `ss -Hltn` без loopback против того же
  allowlist (ловит порты Docker), `sshd -T`.
Allowlist портов — из тех же переменных, что настраивают firewall, а не второй копией в проверке.

## Установка

`pipx install 'ansible-core>=<минимум коллекций>'` и `pipx inject ansible-core -r requirements.txt`
(Python-зависимости коллекций, например `openstacksdk`, — в venv Ansible; обычный `pip install`
ставит мимо). Минимальная версия ansible-core — из `requires_ansible` в `meta/runtime.yml` коллекций
(ansible-core из apt дистрибутива бывает старее). Коллекции и Python-пакеты — с точными версиями в
`requirements.yml`/`requirements.txt`.

## Когда что-то не получается

| Симптом | Причина | Действие |
|---|---|---|
| `Conditional expressions must be strings` | условие с «: » без кавычек стало словарём | взять условие в кавычки целиком |
| регулярка не находит очевидное / `regex_replace` вернул мусор | `\` экранирован иначе, чем ожидалось | переписать без обратных слешей |
| `Too many authentication failures` | агент перебрал ключи до нужного | `IdentitiesOnly=yes`, явный `-i` |
| bootstrap под root не заходит на настроенный хост | root-логин закрыт hardening'ом | только чистые диски, `--limit`; иначе основной плейбук |
| `'vault_…' is undefined` в шаблоне | открытое имя в `vars.yml` есть, значения в `vault.yml` нет | добавить через `ansible-vault edit` (см. «Секреты») |
| `Ansible requires blocking IO on stdin/stdout/stderr` | запуск без терминала с неблокирующим потоком | `</dev/null` и `2>файл` у команды |
| изменённый конфиг не виден в контейнере | bind-mount файла, файл заменён атомарно | монтировать каталог |
| порт контейнера доступен снаружи при `deny incoming` | Docker публикует мимо ufw | не публиковать; `DOCKER-USER` как страховка |
| `REMOTE HOST IDENTIFICATION HAS CHANGED` после пересоздания сервера | новые host keys на том же адресе, `accept-new` старую запись не заменит | `ssh-keygen -R <адрес>` для каждого пересозданного хоста |
