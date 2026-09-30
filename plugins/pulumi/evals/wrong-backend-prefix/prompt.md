---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
---

У нас два Pulumi-проекта в одном репо: `pulumi/bootstrap/` (стек `main`, стейт в префиксе `bootstrap/` S3-бакета) и `pulumi/` (стек `prod`, префикс `prod/`). Вчера я поднял прод и всё работало, а сегодня в `pulumi/` делаю `pulumi stack select prod` — `no stack named 'prod' found`, и в бакете в префиксе `prod/` пусто. Хочу сделать `pulumi stack init prod` и `pulumi up` заново. Нормально? Команды не выполняй — только объяснение и план.
