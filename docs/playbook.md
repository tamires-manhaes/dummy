# Playbook do /dummy

Fonte de verdade do loop. O comando `/dummy` é só um shim que manda seguir este arquivo.

**Entrada**: um link de issue do GitHub.
**Saída**: o link de um PR com spec, testes e implementação revisados, linkado à issue e pronto para review humano — ou `blocked` com o motivo e o que falta do humano. Nunca mergeia.

## Papéis

- **Orquestrador**: a sessão principal que recebeu `/dummy`. Faz preflight, spawna um agent por fase, confere o resultado de cada fase, posta comentários no GitHub, congela a spec e finaliza o PR.
- **Agents de fase** (`agents/`): cada um executa uma fase e devolve um bloco de saída estruturado. Não spawnam outros agents e não falam com o humano.

| Fase | Agent | Modelo |
|---|---|---|
| 1 make-agent-ready | `dummy-refine` | secundário |
| 2 make-spec / 3c revise-spec | `dummy-spec` | secundário |
| 3a review-spec | `dummy-spec-review` | primário |
| 4 implement-issue / 5b apply-fixes | `dummy-impl` | secundário |
| 5a code-review | `dummy-code-review` | primário |

**Primário** é o modelo mais poderoso disponível e faz os reviews; **secundário** faz a autoria. Quais modelos são, por CLI, o usuário define com `scripts/dummy-models`; o instalador grava a escolha na definição de cada agent.

## Modo de execução

O loop roda em dois modos, conforme o harness:

- **Subagents** (Claude Code, e qualquer harness com agents nomeados): cada fase é um agent separado, com o modelo do seu tier gravado na definição do agent. No Claude Code, **não passe `model` na chamada da tool Agent**: o parâmetro sobrepõe o frontmatter e só aceita alias.
- **Inline** (harness sem subagents nomeados): o orquestrador executa cada fase ele mesmo, em sequência. Antes de cada fase, leia `agents/<agent>.md` e siga-o como instrução de papel, ignorando o frontmatter; ao terminar, produza o bloco de saída da fase e aplique sobre ele as mesmas conferências. Onde o playbook diz "spawne X", leia "execute a fase X".

No modo inline, o review perde independência: quem revisa é o mesmo modelo e contexto que escreveu. Compense assim:

1. Se o harness permite trocar de modelo ou abrir sessão limpa por comando, faça as fases 3a e 5a num modelo/sessão diferente do autor.
2. Senão, antes de cada review releia do disco a issue, a spec e o diff (`git diff <base>...HEAD`) e revise só a partir deles, sem se apoiar no raciocínio da fase de autoria.
3. Registre no body do PR em qual modo o loop rodou e qual modelo fez cada fase.

Em modo inline, o prompt de entrada informa os modelos primário e secundário configurados. Sem configuração, use o modelo da sessão para tudo.

## Regras do orquestrador

1. **Confira o artefato, não o relatório.** Depois de cada fase, verifique com `gh`/`git` o que o agent diz ter feito (label, PR, SHA, arquivos) e re-rode você mesmo os comandos de teste. Relatório que não bate com o artefato = fase falhou.
2. **Um retry por fase.** Agent que volta sem ter usado tools, com saída fora do formato ou com artefato ausente: re-spawne uma vez com o erro apontado. Segunda falha → `blocked reason=phase-failed`.
3. **Nada de decisão inventada.** Só é decisão do usuário o que ele escreveu na conversa ou na issue. Agent que afirma aprovação do usuário sem fonte é ignorado nesse ponto.
4. **Estado no GitHub.** Ao concluir cada fase, grave um marker em comentário na issue (antes do PR existir) ou no PR:
   `<!-- dummy:phase=<nome> status=<done|blocked> round=<n> sha=<sha> reason=<...> -->`
5. **Limites duros.** Review de spec: 3 rounds. Implementação: 3 tentativas. Code review: 3 rounds. Estourou → `blocked`, sem round extra.
6. **Sem merge.** Não mergeia, não habilita auto-merge, não faz force-push.
7. **Só no worktree da issue.** Nunca `git checkout` num checkout compartilhado.

## Fase 0 — Preflight (orquestrador)

1. Parse do link → `owner/repo#NN`. Carregue o profile que casa com o repo (`profiles/*.md`, campo `match`). Sem profile → `blocked reason=no-profile`.
2. Leia a issue, comentários, issue pai e markers `dummy:*`. Se houver markers, retome da primeira fase não concluída; em `blocked`, só continue se a causa foi resolvida (ex.: resposta do gate de UI presente).
3. Resolva pelo profile: repo componente onde o código vive, branch base (slice pai ou default do profile), tipo da issue.
4. Roteie pelo tipo: bug ou task → pare e aponte o loop indicado no profile. Só enhancement/feature seguem.
5. Issue com assignee ou claim de outra sessão → `blocked reason=claimed`. Senão, registre o claim (marker `phase=preflight`).
6. Crie o worktree da issue conforme o profile, a partir da branch base atualizada.

## Fase 1 — make-agent-ready

Spawne `dummy-refine` com: path do profile, URL da issue, repo componente, branch base, path do worktree, e a resposta do gate de UI se existir.

**Gate de UI**: se o agent volta `blocked reason=ui-decision`, pare o loop e faça ao usuário a pergunta única:
> A issue toca UI. Sigo sem protótipo, gerando a UI de forma independente a partir dos padrões do repo, ou ela depende de protótipo?

Grave a resposta como marker (`ui=independent` | `ui=prototype-required`). `independent` → re-spawne a fase 1 com a resposta. `prototype-required` → `blocked reason=awaiting-prototype`.

**Confira**: label de pronto do profile presente na issue; nenhuma linha de blocker aberta; diretório de features criado, se o playbook de refino exigir.

## Fase 2 — make-spec

Spawne `dummy-spec` em `mode: create`.

**Confira**: branch existe no remoto; PR aberto, non-draft, com base na branch base e referência à issue; o diff do PR contém só spec + oráculo; rode `oracle_command` — executa e fica em xfail.

Fan-out reportado (contrato cruza repos) → `blocked reason=fan-out`, listando as specs necessárias. Um `/dummy` entrega um PR.

## Fase 3 — review-spec ↔ revise-spec (máx. 3 rounds)

Por round:

1. **Review**: spawne `dummy-spec-review` com issue + comentários, path da spec, branch base e, do round 2 em diante, o diff desde o round anterior e os findings anteriores.
2. **Poste** cada finding como comentário no PR, com a solução sugerida.
3. `verdict: clean` → vá para o freeze.
4. Finding com `needs_scope_change: true` → `blocked reason=scope-change`.
5. **Findings de produto**: a resolução segue a ordem — precedente no código/docs do repo → diretório de features do profile → opção recomendada registrada como **Decision by default** na spec. Colecione as decisions by default para o relatório final.
6. **Revise**: spawne `dummy-spec` em `mode: revise` com os findings. Confira o novo commit e re-rode o oráculo.

Após o 3º round ainda com findings → `blocked reason=review-exhausted`.

**Freeze**: com o review limpo e o oráculo em xfail, grave o SHA do head na spec (`Frozen at`, `Status: frozen`), faça commit e push, registre o SHA frozen no marker e comente na issue que a spec está congelada.

## Fase 4 — implement-issue

Spawne `dummy-impl` em `mode: implement` com: issue, PR, worktree, branch, path da spec, SHA frozen, comando do oráculo.

**Confira** (re-rodando você mesmo): oráculo verde, sem xfail restante; lint, typecheck e testes do repo verdes; `git diff <sha-frozen>..HEAD` não toca a spec nem a lógica dos casos do oráculo (remoção de xfail é esperada); commits no remoto.

- `blocked reason=spec-amendment-needed` → volte à fase 3 com a emenda como finding (conta no limite de rounds); re-congele; retome a fase 4.
- `blocked reason=attempts-exhausted` → `blocked`, anexando a saída do teste que falha.

## Fase 5 — code-review ↔ apply-fixes (máx. 3 rounds)

Por round:

1. **Review**: spawne `dummy-code-review` com issue + comentários, spec frozen, comentários do PR, worktree, branch base, head SHA e, do round 2 em diante, o diff de fix e os findings anteriores.
2. **Poste** cada finding como comentário inline no PR (arquivo + linha), com cenário de falha e solução.
3. `verdict: clean` → fase 6.
4. Finding com `contradicts_spec: true` cuja correção exige mudar a spec → trate como emenda (fase 3).
5. **Fixes**: spawne `dummy-impl` em `mode: fix` com os findings.
6. **Verify**: re-rode oráculo + lint + typecheck + testes. Vermelho → devolva ao `dummy-impl` (conta como round).
7. Responda cada comentário de finding com o commit que o resolveu, ou com o motivo de não aplicar.

Após o 3º round ainda com blocker/major → `blocked reason=code-review-exhausted`.

## Fase 6 — Finalize (orquestrador)

1. Título do PR a partir da issue + spec + implementação, no padrão de commits do repo.
2. Body do PR: resumo do que muda; link da issue; path e SHA frozen da spec; evidência (comandos rodados e resultado); decisions by default; emendas à spec; findings não aplicados e por quê; rounds usados.
3. Linke o PR à issue conforme o profile (keyword de fechamento só linka com base default; em base de slice, linke explicitamente e comente na issue).
4. Mova o card no board conforme o profile. Remova o claim.
5. Marker final `phase=finalize status=done`.
6. Entregue ao usuário: link do PR, decisions by default para ele validar, rounds usados em cada loop.

## Saídas `blocked`

Sempre com: fase, motivo, evidência, e a ação exata que destrava. Re-rodar `/dummy <mesmo link>` retoma do marker.

| reason | Destrava com |
|---|---|
| `no-profile` | criar profile para o repo |
| `claimed` | liberar a issue |
| `ui-decision` | responder o gate de UI |
| `awaiting-prototype` | protótipo aprovado |
| `fan-out` | dividir a issue por repo |
| `scope-change` | decidir o escopo na issue |
| `review-exhausted` / `code-review-exhausted` | ler os findings restantes no PR |
| `attempts-exhausted` | ver a falha anexada |
| `phase-failed` | ver o erro do agent |
