#!/usr/bin/env bash
#
#  setup.sh — install this Claude Code workspace onto the current machine.
#
#  What it does:
#    1. Backs up any existing ~/.claude config it would overwrite
#    2. Copies skills / commands / rules / hooks / CLAUDE.md / settings.json into ~/.claude
#    3. Registers the plugin marketplaces and installs the plugins (-> the bulk of the 272 skills)
#    4. Registers the user-scope MCP servers, substituting YOUR keys from .env
#
#  Safe to re-run. Nothing here contains secrets — you provide your own via .env.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SRC="$REPO_DIR/claude"

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

# ── 0. preflight ────────────────────────────────────────────────────────────
have claude || warn "The 'claude' CLI was not found on PATH. File copy will still run, but plugin/MCP registration will be skipped — install Claude Code first, then re-run."

# ── 1. load .env (optional) ─────────────────────────────────────────────────
if [ -f "$REPO_DIR/.env" ]; then
  say "Loading .env"
  set -a; . "$REPO_DIR/.env"; set +a
else
  warn "No .env found. Copy .env.example -> .env and add your keys for MCP servers that need them."
fi

# ── 2. copy config into ~/.claude (with backup) ─────────────────────────────
mkdir -p "$CLAUDE_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
backup() { [ -e "$1" ] && { mv "$1" "$1.pre-workspace-$STAMP"; warn "Backed up existing $(basename "$1") -> $(basename "$1").pre-workspace-$STAMP"; }; return 0; }

say "Installing skills, commands, rules, hooks, CLAUDE.md"
mkdir -p "$CLAUDE_DIR/skills" "$CLAUDE_DIR/commands" "$CLAUDE_DIR/rules" "$CLAUDE_DIR/hooks"
cp -R "$SRC/skills/."   "$CLAUDE_DIR/skills/"
cp -R "$SRC/commands/." "$CLAUDE_DIR/commands/"
cp -R "$SRC/rules/."    "$CLAUDE_DIR/rules/"
cp -R "$SRC/hooks/."    "$CLAUDE_DIR/hooks/"
chmod +x "$CLAUDE_DIR"/hooks/* 2>/dev/null || true
cp "$SRC/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"

backup "$CLAUDE_DIR/settings.json"
cp "$SRC/settings.json" "$CLAUDE_DIR/settings.json"
say "Wrote settings.json (plugins enabled, hooks, permissions, theme)"

# ── 3. marketplaces + plugins ───────────────────────────────────────────────
if have claude && have jq; then
  say "Registering plugin marketplaces"
  jq -r '.marketplaces[] | .ref' "$REPO_DIR/plugins/marketplaces.json" | while read -r ref; do
    claude plugin marketplace add "$ref" 2>/dev/null && echo "   + $ref" \
      || warn "could not add marketplace $ref (may already exist) — add via /plugin if needed"
  done

  say "Installing plugins (provides the marketplace-sourced skills)"
  jq -r '.plugins[] | .id' "$REPO_DIR/plugins/plugins.json" | while read -r id; do
    claude plugin install "$id" 2>/dev/null && echo "   + $id" \
      || warn "could not install $id — install via /plugin install $id"
  done
else
  warn "Skipping plugin install (need both 'claude' and 'jq'). Install jq, or add plugins interactively:"
  warn "  In Claude Code run: /plugin   then add the marketplaces in plugins/marketplaces.json and install plugins/plugins.json"
fi

# ── 4. MCP servers ──────────────────────────────────────────────────────────
if have claude; then
  say "Registering MCP servers from template (.env values substituted)"
  TPL="$SRC/mcp/mcpServers.template.json"

  add_mcp() {  # name  json
    printf '%s' "$2" | claude mcp add-json "$1" - --scope user 2>/dev/null \
      && echo "   + mcp: $1" || warn "could not register mcp '$1' — see README to add manually"
  }

  # lean-ctx (local tool; only if installed)
  if have lean-ctx; then
    add_mcp "lean-ctx" "$(jq -c --arg d "$HOME/.config/lean-ctx" '{command:"lean-ctx",env:{LEAN_CTX_DATA_DIR:$d}}' <<<'{}')"
  else
    warn "lean-ctx not installed — skipping its MCP + the hooks in settings.json will no-op. See the 'lean-ctx' skill to install, or remove the 'hooks' block from settings.json."
  fi

  # magic (needs MAGIC_API_KEY)
  if [ -n "${MAGIC_API_KEY:-}" ]; then
    add_mcp "magic" "$(jq -nc --arg k "$MAGIC_API_KEY" '{type:"stdio",command:"npx",args:["-y","@21st-dev/magic@latest"],env:{API_KEY:$k}}')"
  else
    warn "MAGIC_API_KEY not set in .env — skipping 'magic' MCP. Get a key at https://21st.dev"
  fi

  # waveforge (local venv)
  if [ -n "${WAVEFORGE_VENV_PYTHON:-}" ] && [ -x "${WAVEFORGE_VENV_PYTHON:-/nonexistent}" ]; then
    add_mcp "waveforge" "$(jq -nc --arg p "$WAVEFORGE_VENV_PYTHON" '{type:"stdio",command:$p,args:["-m","waveforge.mcp_server"],env:{}}')"
  else
    warn "WAVEFORGE_VENV_PYTHON not set/executable — skipping 'waveforge' MCP (local tool)."
  fi
else
  warn "Skipping MCP registration (no 'claude' CLI). Template: claude/mcp/mcpServers.template.json"
fi

say "Done. Restart Claude Code, then run /mcp and /plugin to verify."
