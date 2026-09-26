---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
---

В Selectel DNS-зона `example.org.` лежит в проекте A (там же регистрация домена), а мы хотим, чтобы зоной управлял наш bootstrap-стек Pulumi (TypeScript, terraform-bridged провайдер Selectel, ресурс `selectel.DomainsZoneV2` уже описан в коде с `projectId` проекта B). Сайт на этом домене работает, простоя быть не должно. Как перенести зону в проект B и взять её под Pulumi? Команды не выполняй — только план.
