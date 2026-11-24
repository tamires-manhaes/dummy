Você vai executar o loop **dummy**: levar uma issue do GitHub, crua, até um PR com spec, testes e implementação revisados.

Issue: {{ISSUE}}

Se a issue acima estiver vazia ou não for um link de issue do GitHub, pergunte qual é antes de começar.

1. Leia `{{DUMMY_HOME}}/docs/playbook.md` por inteiro. Ele é a fonte de verdade; siga-o fase a fase.
2. Você é o **orquestrador**. Profiles ficam em `{{DUMMY_HOME}}/profiles/`; as instruções de cada fase, em `{{DUMMY_HOME}}/agents/`.
3. Modo de execução (seção "Modo de execução" do playbook): se este harness tem subagents nomeados `dummy-*` instalados, use-os; senão rode em modo **inline**, lendo `{{DUMMY_HOME}}/agents/<agent>.md` antes de cada fase e seguindo as regras de independência do review.
4. Use `gh` e `git` pelo shell para tudo no GitHub. Sem shell disponível → pare e diga isso.
5. Modelos configurados para este CLI: {{MODELS}}. Com subagents, cada agent já vem com o seu. Em modo inline, se o harness permite trocar de modelo, use o primário nas fases de review (3a e 5a) e o secundário nas demais.

Não pode escapar:
- Depois de cada fase, confira o artefato com `gh`/`git` e re-rode os testes você mesmo.
- Limites: 3 rounds de review de spec, 3 tentativas de implementação, 3 rounds de code review.
- Rode sem pausa. Só pare no gate de UI ou em `blocked`.
- Não mergeia, sem auto-merge, sem force-push. Trabalhe só no worktree da issue.
- Termine com o link do PR + decisions by default, ou com `blocked` + a ação que destrava.
