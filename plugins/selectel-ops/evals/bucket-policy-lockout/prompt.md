---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
---

В Pulumi-стеке для Selectel S3 я добавил `aws.s3.BucketPolicy` с одним правилом — публичное чтение (`Principal: "*"`, `s3:GetObject` на `<bucket>/*`), чтобы потом повесить CDN. `pulumi up` падает: `waiting for S3 Bucket Policy (<bucket>) create: operation error S3: GetBucketPolicy, StatusCode: 403, AccessDenied`. Ключ S3 — сервисного пользователя с ролью member на проект, бакет он же и создал. Почему 403 и как сделать публичное чтение правильно? Команды не выполняй — только объяснение и план.
