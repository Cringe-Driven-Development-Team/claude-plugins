---
max_turns: 8
allowed_tools: [Read, Glob, Grep, Skill]
---

В `ansible/verify.yml` нашего репо есть задача:

```yaml
- name: "UFW: активен"
  ansible.builtin.assert:
    that:
      - ufw_status.stdout is search('(?m)^Status: active$')
```

У коллеги на ansible-core 2.17 проверка всегда зелёная, у меня на 2.19 падает с `Conditional expressions must be strings`. Что не так и как исправить? Команды не выполняй — только объяснение и исправление.
