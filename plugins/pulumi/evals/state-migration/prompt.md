---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
---

У нас Pulumi-проект на TypeScript (bun), стейт сейчас в локальном backend `file://~/.pulumi-local`. Мы только что создали S3-бакет `team-state` (S3-совместимое хранилище, endpoint `s3.example-cloud.ru`, регион `r-1`, path-style), а ключи доступа к нему — выходы этого же стека. Распиши по шагам, как перенести стейт стека `main` в этот бакет. Команды не выполняй — только план с командами.
