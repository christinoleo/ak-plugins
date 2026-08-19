# ak-plugins

Personal Claude Code plugin marketplace. Dev workflow commands plus curated picks from other marketplaces.

## Plugins in this marketplace

| Plugin | Source | What it is |
|--------|--------|------------|
| `ak` | this repo (`./plugin`) | Dev workflow commands (this README's commands section) |
| `mattpocock-skills` | `christinoleo/skills` (fork of `mattpocock/skills`) | Matt Pocock skills bundle, tracked clean against upstream |
| `frontend-design` | `anthropics/claude-plugins-official` (git-subdir) | Anthropic frontend-design plugin |
| `plugin-dev` | `anthropics/claude-code` (git-subdir) | Toolkit for developing Claude Code plugins |

## `ak` commands

| Command | Description |
|---------|-------------|
| `/ak-help` | List every installed skill and command, and say which ones apply to what you are doing now |
| `/bcheck` | Pick up a GitHub issue, assess context sufficiency, start coding or enter plan mode |
| `/linus` | Linus Torvalds-style code review with sub-agent investigation |
| `/triage` | Walk through review findings point-by-point, decide and execute fixes |
| `/verify` | Browser-based verification of changes using Chrome DevTools |
| `/replan` | Audit coverage against requirements and rewrite to 100%. Scores the plan by default, or the delivered work with `/replan delivered` |
| `/plan-to-issues` | Convert approved plan into a GitHub Issues epic with tasks and dependencies |
| `/caveman-off` | Stop caveman switching itself on, in this and every future session |
| `/caveman-on` | Restore the default, where caveman auto-activates each session |

## `ak` skills

| Skill | Description |
|-------|-------------|
| `/caveman` | Ultra-compressed conversation register that drops filler while keeping technical accuracy. Chat only, never applies to files, commits, issues or anything published. **On by default**: the `SessionStart` hook activates it every session, so typing `/caveman` is only ever a re-assert. Say "stop caveman" to drop it for this session, or `/caveman-off` to stop it coming back. |

### Vendored engineering skills

Forty skills and one agent vendored from
[pstack](https://github.com/cursor/plugins/tree/main/pstack) (MIT, Lauren Tan). See
`plugin/skills/ATTRIBUTION.md` for what was taken, what was left behind and why, and every change
made when porting them from Cursor to Claude Code.

| Skill | Description |
|-------|-------------|
| `principle-*` (20) | Short engineering rules the agent reads when the matching situation comes up: sizing a diff, choosing a data structure, placing validation, verifying work, sequencing commits |
| `/architect` | Sketch types, signatures, and module boundaries before code, from three competing design runners |
| `/arena` | Run N candidates at one task, pick a base, graft the best of the losers into it |
| `/swarm` | Fan out parallel workers over slices, races, or gauntlets, and return one report |
| `/how` | Explain how a subsystem works, with parallel explorers and an optional architectural critique |
| `/why` | Trace design rationale across source control, tickets, docs, chat, observability, and error tracking |
| `/explain-work` | Explain a body of work plainly, weaving `how` and `why` into one explanation |
| `/blast-radius` | Find what a change breaks elsewhere, and prove it by running code |
| `/interrogate` | Four independent reviewers challenge a change, each through a different lens |
| `/no-comments` | Spawn the `comment-sicko` agent, then act on what it finds |
| `/figure-it-out` | Design a bespoke, auditable playbook when no narrower one fits |
| `/show-me-your-work` | Append-only TSV decision log for long or unattended runs |
| `/recall` | Reconstruct what you were working on from your own chat history and the shared record |
| `/reflect` | Three reviewers mine a session for durable lessons, then synthesize them into skill edits |
| `/create-verification-skill` | Generate a project-local skill that drives your real app to prove behavior |
| `/maintain-verification-skill` | Keep that verification skill and its feature map honest |
| `/automate-me` | Mine your history and preferences into a personal `-mode` skill |
| `/technical-writing` | Write docs, RFCs, readmes, and PR descriptions |
| `/typescript-best-practices` | TypeScript patterns, with a longer reference file |
| `/bro` | Restate the last message in plain language, no jargon |
| `unslop` | Cut AI tells from any writing |

## `ak` agents

**comment-sicko.** A deranged comment-hater that `/no-comments` spawns. Feed it a diff and it
hunts narration, banners, commented-out corpses, and workaround sermons. Legal headers, public
API contracts, lint suppressions with a faulty rule, and constraint links survive.

## `ak` hooks

**caveman.sh.** SessionStart hook that switches the caveman register on at the top of every session. It reads the rules straight out of `plugin/skills/caveman/SKILL.md`, so the skill file stays the single source of truth. Silent when `~/.claude/ak-caveman.state` contains `off` (written by `/caveman-off`). Dependency-free bash.

**workflow-hints.sh.** PreToolUse hook that injects next-step context:
- After `EnterPlanMode`: reminds to run `/replan` before exiting plan mode
- After `/linus`: suggests `/triage`
- After `/triage`: suggests `/verify`
- After `/replan`: suggests `/plan-to-issues` in plan mode, `/verify` in delivered mode

## Install

```bash
claude plugin marketplace add christinoleo/ak-plugins
claude plugin install ak@ak-plugins
claude plugin install mattpocock-skills@ak-plugins
claude plugin install frontend-design@ak-plugins
claude plugin install plugin-dev@ak-plugins
```

## Develop

Edit commands in `plugin/commands/`, then commit. Consumers run `claude plugin update <name>@ak-plugins` to pull.

### Version bump

A `pre-commit` git hook in `.githooks/pre-commit` auto-bumps the `ak` plugin version (`plugin.json` + `marketplace.json` together) when commits touch `plugin/**` or `.claude-plugin/marketplace.json`.

- default: **patch** bump
- `AK_BUMP=minor git commit ...` → minor
- `AK_BUMP=major git commit ...` → major
- `AK_BUMP=skip` (or `AK_NO_BUMP=1`) → no bump

If the staged diff already includes a `version` change, the hook skips (you already bumped manually).

For out-of-band bumps without committing right away:

```bash
./scripts/bump.sh patch    # or minor / major
```

The hook cannot reliably read the in-progress commit message across `-m` and editor flows, so Conventional Commits subjects are not parsed. Use `AK_BUMP=...` for non-patch bumps.

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
│   └── pre-commit             # Auto patch version-bump hook
├── scripts/
│   └── bump.sh                # Manual version bump helper
├── plugin/                    # The `ak` plugin
│   ├── .claude-plugin/
│   │   └── plugin.json
│   ├── commands/              # Slash commands
│   └── hooks/
│       ├── hooks.json
│       └── workflow-hints.sh
└── README.md
```
