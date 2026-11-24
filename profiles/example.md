# Profile: example

Modelo de profile. Copie para `profiles/<seu-projeto>.md` e ajuste. Tudo que é específico do projeto alvo fica aqui; o playbook e os agents do dummy não citam projeto nenhum.

Profiles reais ficam fora do git por padrão (veja `.gitignore`): costumam carregar nomes de repos privados e convenções internas.

```yaml
match:
  # issues destes repos usam este profile
  - owner/repo
workspace: ~/code
root: ~/code/repo          # repo que guarda playbooks e docs do projeto
```

## Onde o código vive

Se a issue fica num repo e o código em outro, diga aqui como resolver o repo do código (linha no corpo da issue, issue pai, label). Se é o mesmo repo, diga isso.

## Branches

- **Base**: de onde cortar e para onde o PR aponta (ex.: `develop`; ou a branch da feature pai, se a issue declarar). Nunca a branch de produção.
- **Feature**: padrão de nome, ex. `feat/<NN>-<desc>`.
- Diga se o CI roda em PRs com essa base. Se não roda, lint, typecheck, testes e oráculo rodam localmente.

## Worktree

Onde criar o worktree de cada issue, ex. `~/code/<repo>-wt-<NN>`. Diga se o checkout principal é compartilhado entre sessões.

## Playbooks e artefatos (relativos a `root`)

Opcionais. Se o projeto tem documentos que definem como refinar issue, o formato da spec ou a mecânica de implementação, liste-os; os agents os seguem. Sem eles, os agents seguem só as próprias instruções.

```yaml
playbooks:
  refine:    docs/how-to-refine.md
  spec:      docs/how-to-spec.md
  implement: docs/how-to-implement.md
artifacts:
  issue:     docs/templates/issue.md
  spec:      docs/templates/spec.md
principles:  docs/principles.md
features_dir: docs/features
```

## Issue

- Label de pronto: ex. `agent:ready`.
- Roteamento por tipo: o que fazer com bug e task (o dummy só segue com enhancement/feature).
- Onde as specs ficam, ex. `docs/specs/<YYYYMMDD>-<slug>.md`.

## Link e board

- Como o PR referencia a issue (`Closes #NN`, `Part of owner/repo#NN`).
- Keyword de fechamento só linka quando a base é a branch default; diga o que fazer nos outros casos.
- Board: qual projeto e para qual coluna mover o card ao finalizar.

## Decisões de produto

Ordem de consulta para decisão em aberto: código e docs do repo → diretório de features → opção recomendada registrada como Decision by default.
