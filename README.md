# dummy

Um comando que leva uma issue do GitHub, crua, até um PR com spec, testes e implementação revisados — em qualquer CLI de coding agent.

```
/dummy https://github.com/<owner>/<repo>/issues/<n>
```

Devolve o link do PR, linkado à issue e pronto para review humano — ou `blocked`, com o motivo e o que destrava. Nunca mergeia.

## O que ele faz

| # | Fase | Quem | Resultado |
|---|---|---|---|
| 0 | preflight | orquestrador | profile, repo, branch base, worktree, claim |
| 1 | make-agent-ready | `dummy-refine` | issue refinada + label de pronto |
| 2 | make-spec | `dummy-spec` | branch, spec, oráculo (testes) em xfail, PR aberto |
| 3 | review-spec ↔ revise | `dummy-spec-review` / `dummy-spec` | spec limpa e congelada (máx. 3 rounds) |
| 4 | implement-issue | `dummy-impl` | código; oráculo, lint e testes verdes |
| 5 | code-review ↔ fixes | `dummy-code-review` / `dummy-impl` | review limpo (máx. 3 rounds) |
| 6 | finalize | orquestrador | título/body do PR, link à issue, card movido |

No caminho feliz, o humano só é chamado no **gate de UI**: issue que toca UI para e pergunta se segue sem protótipo ou depende dele. Decisões de produto em aberto são resolvidas por precedente do projeto; sem precedente, viram *Decision by default* registrada na spec e listada no fim.

O loop inteiro está em [`docs/playbook.md`](docs/playbook.md).

## Instalação

```bash
git clone https://github.com/tamires-manhaes/dummy.git
cd dummy
scripts/install.sh            # instala nos CLIs detectados na máquina
```

Outras formas:

```bash
scripts/install.sh --list                     # o que foi detectado
scripts/install.sh codex goose                # alvos específicos
scripts/install.sh all                        # todos
scripts/install.sh cursor --project ~/code/x  # no projeto, não no usuário
scripts/install.sh --uninstall                # remove tudo que foi instalado
scripts/install.sh --uninstall gemini         # remove só um alvo
```

Os arquivos instalados apontam para o caminho deste clone. Moveu o repo → rode o instalador de novo. Arquivo existente que não é do dummy nunca é sobrescrito sem `--force`.

## Suporte por CLI

| CLI | Alvo | Como invocar | Modo | O que é instalado |
|---|---|---|---|---|
| Claude Code | `claude` | `/dummy <link>` | subagents | `~/.claude/commands/dummy.md` e `dummy-models.md` + 5 agents em `~/.claude/agents/` |
| Codex CLI | `codex` | `$dummy <link>` | subagents | skill em `~/.agents/skills/dummy/` + 5 agents em `~/.codex/agents/` |
| Cursor | `cursor` | `/dummy <link>` | subagents¹ | skill em `~/.cursor/skills/dummy/` + 5 agents em `~/.cursor/agents/` |
| Gemini CLI | `gemini` | `/dummy <link>` | subagents | `~/.gemini/commands/dummy.toml` + 5 agents em `~/.gemini/agents/` |
| OpenCode | `opencode` | `/dummy <link>` | subagents | `~/.config/opencode/commands/dummy.md` + 5 agents em `~/.config/opencode/agents/` |
| Cline | `cline` | `/dummy <link>` | inline | skill em `~/.cline/skills/dummy/` |
| Goose | `goose` | `goose run --recipe … --params issue_url=<link>`² | inline | recipe em `~/.config/goose/recipes/dummy.yaml` |
| Aider | `aider` | `dummy-aider <link>` | **parcial**³ | wrapper em `~/.local/bin/dummy-aider` |
| qualquer outro | `generic` | colar o prompt | inline | `dist/dummy.prompt.md` |

¹ O `cursor-agent` (CLI) só lê subagents do projeto. Para tê-los no CLI: `scripts/install.sh cursor --project <repo>`. No editor, a instalação por usuário basta.

² Para ter `/dummy` no Goose, adicione em `~/.config/goose/config.yaml` o trecho que o instalador imprime (`slash_commands`). O instalador não edita seu config.

³ O Aider não executa comandos de shell sugeridos pelo modelo. O wrapper busca a issue com `gh`, carrega playbook, agents e profiles como contexto somente-leitura, e o Aider faz as edições (spec, oráculo, código). Os passos de `gh`, `git` e execução de testes saem como lista de comandos para você rodar. Não é um loop autônomo.

Com `--project DIR`, os caminhos acima passam a ser relativos ao projeto (`DIR/.claude`, `DIR/.agents` + `DIR/.codex`, `DIR/.cursor`, `DIR/.cline`, `DIR/.gemini`, `DIR/.opencode`). Goose, Aider e `generic` são sempre por usuário.

### Modos

- **subagents** — cada fase roda num agent separado. É o que dá independência ao review: quem revisa não é quem escreveu.
- **inline** — o orquestrador executa as fases em sequência, lendo `agents/<fase>.md` como instrução de papel. Funciona, mas o review é feito pelo mesmo modelo e contexto que escreveu; o playbook manda reler tudo do disco antes de revisar e registrar o modo no PR.

## Modelos

O dummy usa dois modelos, e você escolhe quais:

| Tier | Papel | Fases |
|---|---|---|
| **primário** | o mais poderoso que você tem: revisa | `review-spec`, `code-review` |
| **secundário** | escreve | `make-agent-ready`, `make-spec`, `implement-issue`, fixes |

```bash
scripts/dummy-models show                                   # o que cada CLI usa hoje
scripts/dummy-models set --target codex <primário> <secundário>
scripts/dummy-models set --target claude claude-fable-5-2 claude-opus-4-8
scripts/dummy-models set                                    # pergunta interativamente
scripts/dummy-models set --target cursor inherit inherit    # herdar o modelo da sessão
scripts/dummy-models reset --target codex
```

No Claude Code o mesmo comando existe como `/dummy-models [<primário> <secundário>]`.

Depois de `set` ou `reset`, os CLIs já instalados são regerados sozinhos; abra uma sessão nova para carregar.

- **IDs são do CLI, não do dummy.** Cada CLI tem seus nomes de modelo (no OpenCode, `provedor/modelo`). O script grava o que você digitar, sem validar. Por isso prefira `--target`.
- **Sem `--target`** o valor vai para `default`: vale só para CLIs que não têm valor próprio, nem seu nem do repo. Não muda o Claude Code, que já vem com padrão.
- **Padrões do repo** ([`config/models.defaults.conf`](config/models.defaults.conf)): Claude Code com Fable 5.2 primário e Opus 4.8 secundário. Os demais herdam o modelo da sessão até você definir.
- **Suas escolhas** ficam em `~/.config/dummy/models.conf`, fora do repo.
- **Onde vale de verdade**: em CLIs com subagents (Claude Code, Codex, Cursor, Gemini, OpenCode) o modelo vai na definição de cada agent. Em modo inline (Cline, Goose, Aider, genérico) a sessão tem um modelo só; os dois nomes entram no prompt como orientação para trocar de modelo nos reviews, se o CLI permitir.
- Quem é primário ou secundário está no campo `tier:` do frontmatter de cada arquivo em `agents/`.

## Requisitos

- `git` e [`gh`](https://cli.github.com/) autenticado, com acesso aos repos alvo.
- Um CLI que execute shell de forma autônoma (todos acima, exceto Aider).
- Um **profile** em `profiles/` que case com o repo da issue.

## Profiles

Tudo que é específico do projeto alvo fica num profile: quais repos, regra de branch base, onde criar worktree, playbooks e formatos de spec do projeto, label de pronto, como linkar o PR e mover o card. Playbook e agents não citam projeto nenhum.

Copie [`profiles/example.md`](profiles/example.md) para `profiles/<seu-projeto>.md` e ajuste. Profiles reais ficam fora do git (`.gitignore`), porque costumam carregar nomes de repos privados e convenções internas. Issue de repo sem profile → `blocked reason=no-profile`.

## Estrutura

```
agents/      instruções de cada fase; `tier:` no frontmatter diz qual modelo usa
commands/    dummy.md e dummy-models.md (Claude Code), dummy.portable.md (demais CLIs)
config/      models.defaults.conf — modelos padrão por CLI
docs/        playbook.md — fonte de verdade do loop
profiles/    configuração por projeto alvo
scripts/     install.sh, dummy-models
```

O instalador gera os formatos de cada CLI a partir de `agents/` e `commands/`. Editou algo ali → `scripts/install.sh --reapply` regera tudo que está instalado.

## Retomada e bloqueios

O estado fica em markers `<!-- dummy:phase=… -->` na issue e no PR. Rodar `/dummy` de novo com o mesmo link retoma da primeira fase não concluída. Os motivos de `blocked` e o que destrava cada um estão no fim do playbook.

## Estado

- Testado: o instalador (instalação, desinstalação, `--project`, guarda de sobrescrita), `dummy-models` (set, reset, inherit, regeração) e a validade sintática dos arquivos gerados (TOML, YAML, frontmatter).
- **Ainda não testado**: uma execução completa do loop em nenhum CLI.
- Convenções de cada CLI conferidas na documentação oficial em 2026-11-24. Pontos que a documentação não cobre e podem variar com a versão: como Codex, Cursor e Cline repassam o texto digitado depois do nome da skill (o prompt trata como "o link que veio junto com o comando" e pergunta se não achar); o formato de agents do Cline (por isso inline); o schema de agents do OpenCode em versões anteriores à config V2.
