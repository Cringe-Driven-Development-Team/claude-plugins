---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
---

Я новый участник команды инфраструктуры. У нас в репозитории `pulumi/` и `pulumi/bootstrap/` (TypeScript, bun, Pulumi.yaml с packagemanager: bun), стейт всех стеков лежит в S3-бакете Selectel, bootstrap-стек создал этот бакет. Мне нужен доступ к стейту, чтобы делать `pulumi preview` основного стека. Коллега предлагает просто скинуть мне в мессенджер ключи S3 из выходов bootstrap-стека. Как правильно получить доступ? Команды не выполняй — только план.
