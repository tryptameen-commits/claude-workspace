# Claude Code Workspace

A portable, shareable copy of a fully loaded [Claude Code](https://claude.com/claude-code) setup —
skills, plugins, MCP servers, hooks, commands, and config. Clone it, run one script, and your
Claude Code looks like the source machine.

> **No secrets are in this repo.** Every API key, credential, and personal data file has been
> stripped. Anywhere a key is required, you add **your own** via `.env` — see [Bring your own keys](#bring-your-own-keys).

## What you get

| Layer | Count | Source |
|---|---|---|
| **Personal skills** (vendored, verbatim) | **52** | `claude/skills/` in this repo |
| **Plugin skills** (design-ops, ui-design, carta-crm, legalzoom, vanta, …) | ~200 | installed by `setup.sh` from 3 marketplaces |
| **Built-in skills** (code-review, verify, run, security-review, …) | several | ship with Claude Code itself |
| **Slash commands** | 13 | `claude/commands/` |
| **Plugins** | 14 (13 enabled) | `plugins/plugins.json` |
| **Plugin marketplaces** | 3 | `plugins/marketplaces.json` |
| **MCP servers** | lean-ctx, magic, waveforge (+ plugin MCPs) | `claude/mcp/mcpServers.template.json` |
| **Hooks** | lean-ctx observe/rewrite/redirect | `claude/settings.json` + `claude/hooks/` |

Together these reproduce the full skill set (the "272 skills" = vendored + plugin-provided + Claude Code built-ins).

## Quick start

```bash
git clone <this-repo-url> claude-workspace
cd claude-workspace
cp .env.example .env        # then edit .env and add your own keys (optional)
./setup.sh                  # installs everything into ~/.claude
```

Restart Claude Code, then verify with `/plugin`, `/mcp`, and `/skills`.

`setup.sh` is idempotent and **backs up** any `settings.json` it would overwrite
(`settings.json.pre-workspace-<timestamp>`).

Requirements: the `claude` CLI on your PATH, plus `jq` (for plugin/MCP automation). Without
them, file copying still works and the script prints manual fallback steps.

## Bring your own keys

Copy `.env.example` → `.env` and fill in only what you use:

| Variable | For | Get it |
|---|---|---|
| `MAGIC_API_KEY` | `magic` MCP (21st.dev UI component generator) | https://21st.dev |
| `WAVEFORGE_VENV_PYTHON` | `waveforge` MCP (local sound engine) | path to your Waveforge venv python |
| `CLAUDE_VERIFIER_*` | optional Claude Code web auto-login | usually not needed |

Plugin MCPs (**carta-crm, legalzoom, vanta**) authenticate interactively inside Claude Code
(run their `authenticate` tool) — no keys needed here.

## Local-tool dependencies (require extra setup)

A few items depend on software that won't exist on a fresh machine. They're included and
documented, but need you to install the underlying tool:

- **lean-ctx** — the context-runtime MCP **and** the hooks in `settings.json` depend on the
  `lean-ctx` binary. Install it (see the `lean-ctx` skill) or the hooks safely no-op / remove
  the `hooks` block from `settings.json`.
- **waveforge** — a local Python sound engine; set `WAVEFORGE_VENV_PYTHON` or skip it.
- **magic** — needs `MAGIC_API_KEY` (free-tier key from 21st.dev).

## Repo layout

```
claude-workspace/
├── README.md
├── setup.sh                 # installer (idempotent, backs up)
├── .env.example             # copy to .env, add your keys
├── .gitignore               # blocks secrets & runtime state
├── claude/                  # → merged into ~/.claude
│   ├── CLAUDE.md            # global instructions
│   ├── settings.json        # plugins, hooks, permissions, theme (sanitized)
│   ├── rules/               # rule files referenced by CLAUDE.md
│   ├── commands/            # 13 slash commands
│   ├── hooks/               # lean-ctx hook scripts
│   ├── skills/              # 52 vendored skills
│   └── mcp/
│       └── mcpServers.template.json   # MCP defs with ${ENV} placeholders
└── plugins/
    ├── marketplaces.json    # 3 marketplaces to register
    └── plugins.json         # 14 plugins to install
```

## What was deliberately excluded (and why)

To keep this safe to share publicly, the following were **not** copied from the source `~/.claude`:

- `.credentials.json`, `.claude.json` — OAuth tokens + full personal project history
- `settings.json` `env` block — contained plaintext login credentials (replaced by `.env`)
- `magic` MCP `API_KEY` — replaced by `${MAGIC_API_KEY}`
- `projects/`, `memory/`, `sessions/`, `history.jsonl`, caches, backups, telemetry — personal/runtime state

## Manual fallback (no jq / no CLI automation)

In Claude Code, run `/plugin`, add the three marketplaces from `plugins/marketplaces.json`,
then install each id in `plugins/plugins.json`. For MCP servers, use
`claude/mcp/mcpServers.template.json` as a guide and add each with `claude mcp add-json` or `/mcp`.

## License

[MIT](LICENSE) — covers the workspace configuration, installer, and original content authored
for this repository. Vendored skills under `claude/skills/` and any plugins installed by
`setup.sh` are the work of their respective authors and remain subject to their own licenses.
