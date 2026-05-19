# ak-plugins

Personal Claude Code plugin marketplace — dev workflow commands plus curated picks from other marketplaces.

## Plugins in this marketplace

| Plugin | Source | What it is |
|--------|--------|------------|
| `ak` | this repo (`./plugin`) | Dev workflow commands (this README's commands section) |
| `mattpocock-skills` | `christinoleo/skills` (fork of `mattpocock/skills`) | Matt Pocock skills bundle with our caveman fork |
| `frontend-design` | `anthropics/claude-plugins-official` (git-subdir) | Anthropic frontend-design plugin |
| `plugin-dev` | `anthropics/claude-code` (git-subdir) | Toolkit for developing Claude Code plugins |
| `hookify` | `anthropics/claude-code` (git-subdir) | Generate custom hooks from rules |

## `ak` commands

| Command | Description |
|---------|-------------|
| `/bcheck` | Pick up a GitHub issue, assess context sufficiency, start coding or enter plan mode |
| `/linus` | Linus Torvalds-style code review with sub-agent investigation |
| `/triage` | Walk through review findings point-by-point, decide and execute fixes |
| `/verify` | Browser-based verification of changes using Chrome DevTools |
| `/replan` | Audit plan coverage against requirements, rewrite to 100% |
| `/redelta` | Audit delivered work against requirements, produce delta to reach 100% |
| `/plan-to-issues` | Convert approved plan into a GitHub Issues epic with tasks and dependencies |
| `/p1` | Phase 1 orchestration: plan → replan → plan-to-issues (spawns trigger agent) |
| `/p1-trigger` | Trigger loop for Phase 1 (called by /p1, do not run directly) |
| `/p2` | Phase 2 orchestration: execute epic tasks with review between each (spawns trigger agent) |
| `/p2-trigger` | Trigger loop for Phase 2 (called by /p2, do not run directly) |

## `ak` hooks

**workflow-hints.sh** — PreToolUse hook that injects next-step context:
- After `EnterPlanMode`: reminds to run `/replan` before exiting plan mode
- After `/linus`: suggests `/triage`
- After `/triage`: suggests `/verify`
- After `/replan`: suggests `/plan-to-issues`

## Install

```bash
claude plugin marketplace add christinoleo/ak-plugins
claude plugin install ak@ak-plugins
claude plugin install mattpocock-skills@ak-plugins
claude plugin install frontend-design@ak-plugins
claude plugin install plugin-dev@ak-plugins
claude plugin install hookify@ak-plugins
```

## Develop

Edit commands in `plugin/commands/`, then commit. Consumers run `claude plugin update <name>@ak-plugins` to pull.

### Version bump (automatic)

A `pre-commit` git hook in `.githooks/pre-commit` auto-bumps the `ak` plugin version when committing changes to `plugin/**` or `.claude-plugin/marketplace.json`. Bump type from Conventional Commits subject (read from `.git/COMMIT_EDITMSG`):

- `<type>(scope)!:` or `BREAKING CHANGE` → major
- `feat(scope):` → minor
- anything else → patch

Skip with `AK_NO_BUMP=1 git commit ...`.

**One-time setup after clone:**

```bash
git config core.hooksPath .githooks
```

(Git doesn't allow versioned hooks to auto-activate; the config above points to the in-repo hook dir.)

## Structure

```
ak-plugins/
├── .claude-plugin/
│   └── marketplace.json       # Marketplace catalog
├── .githooks/
│   └── pre-commit             # Auto version-bump hook
├── plugin/                    # The `ak` plugin
│   ├── .claude-plugin/
│   │   └── plugin.json
│   ├── commands/              # Slash commands
│   └── hooks/
│       ├── hooks.json
│       └── workflow-hints.sh
└── README.md
```
