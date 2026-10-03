# cdd-tasks: команды

Команды проверены на `gh` 2.x. Организация — `Cringe-Driven-Development-Team`, доска — проект
номер 1 (Scrumban). Для команд `gh project` токену нужен scope `project`:
`gh auth refresh -s project`.

## 1. Шаблон описания задачи

```markdown
## Цель

Что изменится, когда задача будет сделана, и зачем.

## Что сделать

- [ ] Шаг, который можно проверить.

## Приёмка

- Наблюдаемый результат: что открыть или запустить и что увидеть.

## Зависимости

1. Задачи и PR, без которых эту не сделать.

## Не входит

- Что рядом, но делается другой задачей.
```

«Цель», «Что сделать» и «Приёмка» обязательны. В задаче на несколько репозиториев добавь раздел
«Порядок мержа».

## 2. Задача и sub-issue

Создать задачу (описание — из файла, чтобы не ломать разметку кавычками):

```bash
gh issue create -R Cringe-Driven-Development-Team/frontend \
  --title "Frontend. Выкатка клиента в S3" --body-file body.md --assignee <логин>
```

Привязать существующую задачу как sub-issue. API принимает числовой `id` задачи, а не её номер:

```bash
SUB_ID=$(gh api repos/Cringe-Driven-Development-Team/infra/issues/22 --jq .id)
gh api -X POST repos/Cringe-Driven-Development-Team/frontend/issues/6/sub_issues \
  -F sub_issue_id="$SUB_ID" --jq .sub_issues_summary
```

Здесь `frontend#6` — родитель, `infra#22` — sub-issue. `-F`, не `-f`: значение должно уйти числом.

Проверить связь:

```bash
gh api repos/Cringe-Driven-Development-Team/frontend/issues/6/sub_issues --jq '.[] | "\(.repository_url | split("/") | last)#\(.number) \(.state)"'
```

## 3. Доска

Новая задача попадает на доску сама, если в репозитории подключён workflow «Автоматизация».
Не попала — добавить:

```bash
gh project item-add 1 --owner Cringe-Driven-Development-Team --url <ссылка на задачу>
```

Статус и спринт меняются по id, а id ищутся по имени — не зашивай их: id спринта меняется каждый
спринт.

```bash
# id проекта
PROJECT=$(gh project view 1 --owner Cringe-Driven-Development-Team --format json --jq .id)

# id карточки задачи
ITEM=$(gh api graphql -f query='query{repository(owner:"Cringe-Driven-Development-Team",name:"frontend"){issue(number:6){projectItems(first:5){nodes{id project{number}}}}}}' \
  --jq '.data.repository.issue.projectItems.nodes[] | select(.project.number==1) | .id')

# поле Status и id нужного значения
gh project field-list 1 --owner Cringe-Driven-Development-Team --format json \
  --jq '.fields[] | select(.name=="Status") | {id, options: [.options[] | "\(.name)=\(.id)"]}'

# выставить статус
gh project item-edit --project-id "$PROJECT" --id "$ITEM" \
  --field-id <id поля Status> --single-select-option-id <id значения>
```

Спринт — поле-итерация, `field-list` его значения не показывает:

```bash
gh api graphql -f query='query{organization(login:"Cringe-Driven-Development-Team"){projectV2(number:1){field(name:"Sprint"){... on ProjectV2IterationField{id configuration{iterations{id title startDate duration}}}}}}}' \
  --jq '.data.organization.projectV2.field | {id, iterations: .configuration.iterations}'

gh project item-edit --project-id "$PROJECT" --id "$ITEM" \
  --field-id <id поля Sprint> --iteration-id <id итерации>
```

В списке только текущая и будущие итерации; текущая — та, у которой `startDate` не позже сегодня.

## 4. Pull request

Курсовой репозиторий фронта, задача `frontend#12`:

```bash
git switch -c web-12 origin/main
# …коммиты…
git push -u origin web-12
gh pr create -R frontend-park-mail-ru/2026_2_Cringe_Driven_Development --base main \
  --title "WEB-12: Форма входа" --body-file pr.md
```

Первая строка `pr.md` — `Closes Cringe-Driven-Development-Team/frontend#12`. Для бэка — `api-12`,
`API-12: …`, `Closes Cringe-Driven-Development-Team/backend#12`.

Проверить, что PR привязан к задаче:

```bash
gh pr view <номер> -R <репозиторий> --json closingIssuesReferences \
  --jq '[.closingIssuesReferences[] | "\(.repository.name)#\(.number)"]'
```

Пустой список при строке `Closes …` — ошибка в ссылке: чаще всего короткое `#N` в курсовом
репозитории. При `Part of …` пустой список — норма.

Задача закрывается при мерже в ветку по умолчанию. PR курсовых репозиториев требуют апрува; их
мерж закрывает задачу в организации автоматически.

## 5. Задача без PR

```bash
gh issue comment 3 -R Cringe-Driven-Development-Team/figma --body "Готово: <ссылка на результат>"
```

Затем карточку — в `In review` (§3). Закрывает ментор:

```bash
gh issue close 3 -R Cringe-Driven-Development-Team/figma --comment "Принято."
```

Задача больше не нужна: `gh issue close <номер> -R <репозиторий> --reason "not planned" --comment "<почему>"`.
