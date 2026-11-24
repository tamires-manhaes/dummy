---
description: "dummy-models — mostra ou define o modelo primário (mais poderoso, usado nos reviews) e o secundário (autoria) que as fases do /dummy usam neste CLI"
argument-hint: "[<primário> <secundário>]"
---

Argumentos: $ARGUMENTS

Script: `{{DUMMY_HOME}}/scripts/dummy-models`

- Sem argumentos → rode `{{DUMMY_HOME}}/scripts/dummy-models show`, mostre o resultado e pergunte ao usuário qual modelo primário e qual secundário ele quer. Não escolha por ele.
- Dois argumentos → rode `{{DUMMY_HOME}}/scripts/dummy-models set --target claude <primário> <secundário>` e mostre a saída.
- `reset` → rode `{{DUMMY_HOME}}/scripts/dummy-models reset --target claude`.
- Se o usuário pedir outro CLI ou "todos", troque `--target claude` por `--target <alvo>` ou `--target default`.

Passe os IDs exatamente como o usuário escreveu; o script não valida se o modelo existe. Depois de `set` ou `reset`, avise que é preciso abrir uma sessão nova para os agents recarregarem.
