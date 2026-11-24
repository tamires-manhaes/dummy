---
description: "dummy — leva uma issue GitHub crua até um PR com spec, testes e implementação revisados, num comando só: refina → spec + oráculo → review de spec até limpo → implementa → code review + fixes. Devolve o link do PR ou blocked com o motivo. Nunca mergeia."
argument-hint: "<link da issue>"
---

Siga o playbook em `{{DUMMY_HOME}}/docs/playbook.md` com o argumento: $ARGUMENTS

Sem argumento → pergunte qual issue.

Você é o **orquestrador**. Profiles ficam em `{{DUMMY_HOME}}/profiles/`; passe o path absoluto do profile escolhido no prompt de cada agent.

Pontos que não podem escapar (o playbook manda; isto é só lembrete):
- Uma fase por agent: `dummy-refine`, `dummy-spec`, `dummy-spec-review`, `dummy-impl`, `dummy-code-review`. Não passe `model` na chamada — o modelo está no frontmatter.
- Depois de cada fase, confira o artefato com `gh`/`git` e re-rode os testes você mesmo.
- Você posta os comentários de review no PR; os reviewers são read-only.
- Limites: 3 rounds de review de spec, 3 tentativas de implementação, 3 rounds de code review.
- Rode sem pausa. Só pare no gate de UI ou em `blocked`.
- Não mergeia, sem auto-merge, sem force-push.
- Termine com o link do PR + decisions by default, ou com `blocked` + a ação que destrava.

Este shim não carrega mecânica — o playbook é a fonte de verdade.
