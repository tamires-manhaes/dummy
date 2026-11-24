#!/usr/bin/env bash
# Instalador do dummy para CLIs de coding agent.
# Compatível com bash 3.2 (macOS). Veja --help.
set -euo pipefail

DUMMY_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$DUMMY_HOME/.install-manifest"
MARK="dummy:managed"
STATE="$DUMMY_HOME/.install-state"
CONF_USER="${XDG_CONFIG_HOME:-$HOME/.config}/dummy/models.conf"
CONF_DEFAULTS="$DUMMY_HOME/config/models.defaults.conf"
CUR_TARGET=""
ALL_TARGETS="claude codex cursor cline gemini opencode goose aider generic"
PHASE_AGENTS="dummy-refine dummy-spec dummy-spec-review dummy-impl dummy-code-review"

TARGETS=""
PROJECT=""
FORCE=0
ACTION="install"

usage() {
  cat <<EOF
Uso: scripts/install.sh [alvos...] [opções]

Alvos:  $ALL_TARGETS
        all   todos os alvos
        (sem alvo: instala nos CLIs detectados nesta máquina)

Opções:
  --project DIR   instala no projeto DIR em vez de no usuário (claude, codex,
                  cursor, cline, gemini, opencode)
  --force         sobrescreve arquivo existente que não é do dummy
  --uninstall     remove tudo que este instalador criou (ou só os alvos dados)
  --list          mostra os CLIs detectados e sai
  --reapply       regera tudo que já está instalado (usado por scripts/dummy-models)
  -h, --help

Exemplos:
  scripts/install.sh                      # auto-detecta
  scripts/install.sh codex goose
  scripts/install.sh cursor --project ~/code/meu-repo
  scripts/install.sh --uninstall
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project) PROJECT="$(cd "${2:?--project exige DIR}" && pwd)"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --uninstall) ACTION="uninstall"; shift ;;
    --list) ACTION="list"; shift ;;
    --reapply) ACTION="reapply"; shift ;;
    -h|--help) usage; exit 0 ;;
    all) TARGETS="$ALL_TARGETS"; shift ;;
    -*) echo "opção desconhecida: $1" >&2; usage >&2; exit 2 ;;
    *)
      case " $ALL_TARGETS " in
        *" $1 "*) TARGETS="$TARGETS $1" ;;
        *) echo "alvo desconhecido: $1" >&2; usage >&2; exit 2 ;;
      esac
      shift ;;
  esac
done

# ---------- helpers ----------

say()  { printf '%s\n' "$*"; }
warn() { printf 'aviso: %s\n' "$*" >&2; }

detected() {
  case "$1" in
    claude)   command -v claude >/dev/null 2>&1 || [ -d "$HOME/.claude" ] ;;
    codex)    command -v codex >/dev/null 2>&1 || [ -d "$HOME/.codex" ] ;;
    cursor)   command -v cursor-agent >/dev/null 2>&1 || command -v cursor >/dev/null 2>&1 || [ -d "$HOME/.cursor" ] ;;
    cline)    command -v cline >/dev/null 2>&1 || [ -d "$HOME/.cline" ] ;;
    gemini)   command -v gemini >/dev/null 2>&1 || [ -d "$HOME/.gemini" ] ;;
    opencode) command -v opencode >/dev/null 2>&1 || [ -d "$HOME/.config/opencode" ] ;;
    goose)    command -v goose >/dev/null 2>&1 || [ -d "$HOME/.config/goose" ] ;;
    aider)    command -v aider >/dev/null 2>&1 ;;
    *)        return 1 ;;
  esac
}

in_manifest() { [ -f "$MANIFEST" ] && grep -qxF "$1" "$MANIFEST"; }

record() { in_manifest "$1" || printf '%s\n' "$1" >> "$MANIFEST"; }

# Um caminho é "nosso" se está no manifesto, é symlink para dentro do repo,
# ou carrega o marcador de arquivo gerenciado.
is_ours() {
  local p="$1"
  in_manifest "$p" && return 0
  if [ -L "$p" ]; then
    case "$(readlink "$p")" in "$DUMMY_HOME"/*) return 0 ;; esac
    return 1
  fi
  [ -f "$p" ] && grep -q "$MARK" "$p"
}

# Garante que podemos escrever em $1; cria o diretório pai.
claim() {
  local p="$1"
  if [ -e "$p" ] || [ -L "$p" ]; then
    if ! is_ours "$p" && [ "$FORCE" -ne 1 ]; then
      echo "erro: $p já existe e não é do dummy (use --force para sobrescrever)" >&2
      exit 1
    fi
    rm -f "$p"
  fi
  mkdir -p "$(dirname "$p")"
}

conf_get() { # arquivo chave
  [ -f "$1" ] || return 0
  sed -n "s|^$2=||p" "$1" | tail -1
}

# Modelo configurado para alvo+tier; vazio = herdar da sessão.
model_for() { # alvo tier
  local v
  v="$(conf_get "$CONF_USER" "$1.$2")"
  [ -n "$v" ] || v="$(conf_get "$CONF_DEFAULTS" "$1.$2")"
  [ -n "$v" ] || v="$(conf_get "$CONF_USER" "default.$2")"
  [ -n "$v" ] || v="$(conf_get "$CONF_DEFAULTS" "default.$2")"
  [ "$v" = "inherit" ] && v=""
  printf '%s' "$v"
}

agent_tier() { sed -n 's/^tier: *//p' "$DUMMY_HOME/agents/$1.md" | head -1; }

agent_model() { model_for "$CUR_TARGET" "$(agent_tier "$1")"; }

models_note() {
  local p s
  p="$(model_for "$CUR_TARGET" primary)"; s="$(model_for "$CUR_TARGET" secondary)"
  [ -n "$p" ] || p="o da sessão"
  [ -n "$s" ] || s="o da sessão"
  printf 'primário (reviews) = %s; secundário (autoria) = %s' "$p" "$s"
}

# Prompt portátil com DUMMY_HOME resolvido e {{ISSUE}} trocado por $1.
render_prompt() {
  sed -e "s|{{DUMMY_HOME}}|$DUMMY_HOME|g" -e "s|{{ISSUE}}|$1|g" \
    -e "s|{{MODELS}}|$(models_note)|g" \
    "$DUMMY_HOME/commands/dummy.portable.md"
}

record_state() {
  local line="$CUR_TARGET|$PROJECT"
  [ -f "$STATE" ] && grep -qxF "$line" "$STATE" && return 0
  printf '%s\n' "$line" >> "$STATE"
}

agent_desc() {
  sed -n 's/^description: *"\{0,1\}\(.*[^"]\)"\{0,1\} *$/\1/p' "$DUMMY_HOME/agents/$1.md" | head -1
}

# Corpo do agent sem frontmatter.
agent_body() {
  awk 'BEGIN{c=0} /^---[[:space:]]*$/ && c<2 {c++; next} c>=2 {print}' "$DUMMY_HOME/agents/$1.md"
}

is_reviewer() { case "$1" in *-review) return 0 ;; *) return 1 ;; esac; }

base_dir() { if [ -n "$PROJECT" ]; then printf '%s' "$PROJECT"; else printf '%s' "$HOME"; fi; }

need_global() {
  if [ -n "$PROJECT" ]; then
    warn "$1 só tem instalação por usuário; ignorando --project para ele"
  fi
}

ARGS_FREE="(o link que o usuário passou junto com este comando)"

# SKILL.md no padrão Agent Skills (Codex, Cursor, Cline).
write_skill() {
  local dest="$1" extra="${2:-}"
  claim "$dest"
  {
    printf -- '---\n'
    printf 'name: dummy\n'
    printf 'description: Leva uma issue do GitHub, crua, até um PR com spec, testes e implementação revisados (refina, spec + oráculo, review de spec, implementa, code review). Use só quando invocado explicitamente com um link de issue.\n'
    [ -n "$extra" ] && printf '%s\n' "$extra"
    printf -- '---\n\n'
    render_prompt "$ARGS_FREE"
    printf '\n<!-- %s -->\n' "$MARK"
  } > "$dest"
  record "$dest"
  say "  skill    $dest"
}

# ---------- alvos ----------

install_claude() {
  local root; root="$(base_dir)/.claude"
  local a dest m c cmd
  for a in $PHASE_AGENTS; do
    dest="$root/agents/$a.md"
    m="$(agent_model "$a")"
    claim "$dest"
    {
      # frontmatter original, trocando `tier:` por `model:` (se configurado)
      awk -v m="$m" 'BEGIN{c=0}
        /^---[[:space:]]*$/ { c++; if (c==2 && m!="") print "model: " m; print; next }
        c==1 && /^tier:/ { next }
        { print }' "$DUMMY_HOME/agents/$a.md"
      printf '\n<!-- %s -->\n' "$MARK"
    } > "$dest"
    record "$dest"
    say "  agent    $dest  [${m:-herda}]"
  done
  for c in dummy dummy-models; do
    cmd="$root/commands/$c.md"
    claim "$cmd"
    {
      sed "s|{{DUMMY_HOME}}|$DUMMY_HOME|g" "$DUMMY_HOME/commands/$c.md"
      printf '\n<!-- %s -->\n' "$MARK"
    } > "$cmd"
    record "$cmd"
    say "  comando  $cmd"
  done
  say "  uso:     /dummy <link da issue>   |   /dummy-models [<primário> <secundário>]"
}

install_codex() {
  local base; base="$(base_dir)"
  local a dest m
  write_skill "$base/.agents/skills/dummy/SKILL.md"
  for a in $PHASE_AGENTS; do
    dest="$base/.codex/agents/$a.toml"
    claim "$dest"
    {
      printf '# %s\n' "$MARK"
      printf 'name = "%s"\n' "$a"
      printf 'description = "%s"\n' "$(agent_desc "$a" | sed 's/"/\\"/g')"
      m="$(agent_model "$a")"
      if [ -n "$m" ]; then printf 'model = "%s"\n' "$m"; fi
      printf "developer_instructions = '''\n"
      agent_body "$a"
      printf "'''\n"
    } > "$dest"
    record "$dest"
    say "  agent    $dest"
  done
  say "  uso:     \$dummy <link da issue>   (ou /skills → dummy)"
}

install_cursor() {
  local root; root="$(base_dir)/.cursor"
  local a dest m
  write_skill "$root/skills/dummy/SKILL.md" "disable-model-invocation: true"
  for a in $PHASE_AGENTS; do
    dest="$root/agents/$a.md"
    claim "$dest"
    {
      printf -- '---\n'
      printf 'name: %s\n' "$a"
      printf 'description: "%s"\n' "$(agent_desc "$a" | sed 's/"/\\"/g')"
      m="$(agent_model "$a")"
      printf 'model: %s\n' "${m:-inherit}"
      if is_reviewer "$a"; then printf 'readonly: true\n'; fi
      printf -- '---\n'
      agent_body "$a"
      printf '\n<!-- %s -->\n' "$MARK"
    } > "$dest"
    record "$dest"
    say "  agent    $dest"
  done
  say "  uso:     /dummy <link da issue>"
  if [ -z "$PROJECT" ]; then
    say "  nota:    o CLI do Cursor só lê subagents do projeto; use --project DIR para tê-los no cursor-agent"
  fi
}

install_cline() {
  local root; root="$(base_dir)/.cline"
  write_skill "$root/skills/dummy/SKILL.md"
  say "  uso:     /dummy <link da issue>   (modo inline)"
}

install_gemini() {
  local root; root="$(base_dir)/.gemini"
  local a dest m cmd="$root/commands/dummy.toml"
  claim "$cmd"
  {
    printf '# %s\n' "$MARK"
    printf 'description = "dummy: issue do GitHub -> PR com spec, testes e implementação revisados"\n'
    printf "prompt = '''\n"
    render_prompt "{{args}}"
    printf "'''\n"
  } > "$cmd"
  record "$cmd"
  say "  comando  $cmd"
  for a in $PHASE_AGENTS; do
    dest="$root/agents/$a.md"
    claim "$dest"
    {
      printf -- '---\n'
      printf 'name: %s\n' "$a"
      printf 'description: "%s"\n' "$(agent_desc "$a" | sed 's/"/\\"/g')"
      m="$(agent_model "$a")"
      if [ -n "$m" ]; then printf 'model: %s\n' "$m"; fi
      printf -- '---\n'
      agent_body "$a"
      printf '\n<!-- %s -->\n' "$MARK"
    } > "$dest"
    record "$dest"
    say "  agent    $dest"
  done
  say "  uso:     /dummy <link da issue>   (rode /commands reload numa sessão aberta)"
}

install_opencode() {
  local root a dest cmd m
  if [ -n "$PROJECT" ]; then root="$PROJECT/.opencode"; else root="$HOME/.config/opencode"; fi
  cmd="$root/commands/dummy.md"
  claim "$cmd"
  {
    printf -- '---\n'
    printf 'description: "dummy: issue do GitHub -> PR com spec, testes e implementação revisados"\n'
    printf -- '---\n'
    render_prompt '$ARGUMENTS'
    printf '\n<!-- %s -->\n' "$MARK"
  } > "$cmd"
  record "$cmd"
  say "  comando  $cmd"
  for a in $PHASE_AGENTS; do
    dest="$root/agents/$a.md"
    claim "$dest"
    {
      printf -- '---\n'
      printf 'description: "%s"\n' "$(agent_desc "$a" | sed 's/"/\\"/g')"
      printf 'mode: subagent\n'
      m="$(agent_model "$a")"
      if [ -n "$m" ]; then printf 'model: %s\n' "$m"; fi
      printf -- '---\n'
      agent_body "$a"
      printf '\n<!-- %s -->\n' "$MARK"
    } > "$dest"
    record "$dest"
    say "  agent    $dest"
  done
  say "  uso:     /dummy <link da issue>"
}

install_goose() {
  need_global goose
  local dest="$HOME/.config/goose/recipes/dummy.yaml"
  claim "$dest"
  {
    printf '# %s\n' "$MARK"
    printf 'version: "1.0.0"\n'
    printf 'title: "dummy"\n'
    printf 'description: "Issue do GitHub -> PR com spec, testes e implementação revisados"\n'
    printf 'parameters:\n'
    printf '  - key: issue_url\n'
    printf '    input_type: string\n'
    printf '    requirement: required\n'
    printf '    description: "Link da issue do GitHub"\n'
    printf 'prompt: |\n'
    render_prompt "{{ issue_url }}" | sed 's/^/  /'
  } > "$dest"
  record "$dest"
  say "  recipe   $dest"
  say "  uso:     goose run --recipe $dest --params issue_url=<link da issue>"
  say "  slash:   para ter /dummy, adicione em ~/.config/goose/config.yaml:"
  say "             slash_commands:"
  say "               - command: \"dummy\""
  say "                 recipe_path: \"$dest\""
}

install_aider() {
  need_global aider
  local dest="$HOME/.local/bin/dummy-aider"
  claim "$dest"
  cat > "$dest" <<EOF
#!/usr/bin/env bash
# $MARK
# Wrapper do dummy para o Aider. Rode de dentro do repo alvo.
set -euo pipefail
DUMMY_HOME="$DUMMY_HOME"
issue="\${1:?uso: dummy-aider <link da issue> [opções do aider]}"
shift
tmp="\$(mktemp -d)"
trap 'rm -rf "\$tmp"' EXIT
gh issue view "\$issue" --comments > "\$tmp/issue.md"
{
  sed -e "s|{{DUMMY_HOME}}|\$DUMMY_HOME|g" -e "s|{{ISSUE}}|\$issue|g" \\
    -e "s|{{MODELS}}|$(models_note)|g" \\
    "\$DUMMY_HOME/commands/dummy.portable.md"
  cat <<'NOTE'

Limitação deste harness: o Aider não executa comandos de shell sugeridos pelo modelo.
- O playbook, os agents de fase, os profiles e a issue (issue.md) já estão no contexto como arquivos somente-leitura; não tente lê-los do disco.
- Rode em modo inline. Faça você as edições de arquivo (spec, oráculo, código).
- Onde o playbook pede gh, git ou execução de testes, não finja o resultado: pare a fase e liste, em "Comandos para o humano", os comandos exatos na ordem. O humano roda e devolve a saída.
NOTE
} > "\$tmp/prompt.md"
reads=(--read "\$DUMMY_HOME/docs/playbook.md" --read "\$tmp/issue.md")
for f in "\$DUMMY_HOME"/agents/*.md "\$DUMMY_HOME"/profiles/*.md; do reads+=(--read "\$f"); done
aider "\${reads[@]}" --message-file "\$tmp/prompt.md" "\$@"
EOF
  chmod +x "$dest"
  record "$dest"
  say "  wrapper  $dest"
  say "  uso:     dummy-aider <link da issue>   (de dentro do repo alvo; suporte parcial)"
  case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) warn "$HOME/.local/bin não está no PATH" ;; esac
}

install_generic() {
  need_global generic
  local dest="$DUMMY_HOME/dist/dummy.prompt.md"
  claim "$dest"
  {
    render_prompt "<cole aqui o link da issue>"
    printf '\n<!-- %s -->\n' "$MARK"
  } > "$dest"
  record "$dest"
  say "  prompt   $dest"
  say "  uso:     cole o conteúdo como primeira mensagem em qualquer agent com shell,"
  say "           trocando o placeholder pelo link da issue; ou referencie o arquivo"
  say "           no AGENTS.md do projeto: \"Para /dummy <issue>, siga $dest\""
}

# ---------- ações ----------

if [ "$ACTION" = "list" ]; then
  for t in $ALL_TARGETS; do
    [ "$t" = "generic" ] && continue
    if detected "$t"; then say "$t: detectado"; else say "$t: não encontrado"; fi
  done
  exit 0
fi

if [ "$ACTION" = "uninstall" ]; then
  [ -f "$MANIFEST" ] || { say "nada instalado por este instalador"; exit 0; }
  keep="$(mktemp)"
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    match=1
    if [ -n "$TARGETS" ]; then
      match=0
      for t in $TARGETS; do
        case "$t:$p" in
          claude:*/.claude/*|codex:*/.codex/*|codex:*/.agents/*|cursor:*/.cursor/*|cline:*/.cline/*|\
          gemini:*/.gemini/*|opencode:*/opencode/*|opencode:*/.opencode/*|goose:*/goose/*|\
          aider:*/dummy-aider|generic:*/dist/*) match=1 ;;
        esac
      done
    fi
    if [ "$match" -eq 1 ]; then
      if [ -e "$p" ] || [ -L "$p" ]; then
        if is_ours "$p"; then rm -f "$p"; say "removido $p"; else warn "mantido (alterado por fora): $p"; fi
      fi
      rmdir "$(dirname "$p")" 2>/dev/null || true
    else
      printf '%s\n' "$p" >> "$keep"
    fi
  done < "$MANIFEST"
  if [ -s "$keep" ]; then mv "$keep" "$MANIFEST"; else rm -f "$keep" "$MANIFEST"; fi
  if [ -f "$STATE" ]; then
    if [ -z "$TARGETS" ]; then
      rm -f "$STATE"
    else
      for t in $TARGETS; do
        grep -v "^$t|" "$STATE" > "$STATE.tmp" || true
        mv "$STATE.tmp" "$STATE"
      done
      [ -s "$STATE" ] || rm -f "$STATE"
    fi
  fi
  exit 0
fi

if [ "$ACTION" = "reapply" ]; then
  [ -f "$STATE" ] || { say "nada instalado para regerar"; exit 0; }
  while IFS='|' read -r t proj; do
    [ -n "$t" ] || continue
    if [ -n "$proj" ] && [ ! -d "$proj" ]; then warn "projeto sumiu, pulando: $proj"; continue; fi
    CUR_TARGET="$t"; PROJECT="$proj"
    say "[$t]${proj:+ (projeto $proj)}"
    "install_$t"
  done < "$STATE"
  exit 0
fi

if [ -z "$TARGETS" ]; then
  for t in $ALL_TARGETS; do
    if [ "$t" != "generic" ] && detected "$t"; then TARGETS="$TARGETS $t"; fi
  done
  if [ -z "$TARGETS" ]; then
    warn "nenhum CLI detectado; gerando só o prompt genérico"
    TARGETS="generic"
  fi
fi

command -v gh >/dev/null 2>&1 || warn "gh não encontrado: o loop depende do GitHub CLI autenticado"
command -v git >/dev/null 2>&1 || warn "git não encontrado"

for t in $TARGETS; do
  CUR_TARGET="$t"
  say "[$t]"
  "install_$t"
  record_state
done

say ""
say "DUMMY_HOME=$DUMMY_HOME (os arquivos instalados apontam para cá; não mova o repo sem reinstalar)"
say "Abra uma sessão nova do CLI para carregar o comando."
