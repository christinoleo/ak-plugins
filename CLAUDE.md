# ak-plugins — Claude Code instructions

Project-level guidance for Claude Code working in this repo.

## What this repo is

A personal Claude Code plugin marketplace. The `ak-plugins` marketplace catalogs five plugins:

- `ak` — our own dev workflow plugin (commands in `plugin/commands/`)
- `mattpocock-skills` — fork-pulled from `christinoleo/skills` (upstream `mattpocock/skills`)
- `frontend-design` — git-subdir from `anthropics/claude-plugins-official`
- `plugin-dev` — git-subdir from `anthropics/claude-code`

Three installation targets stay in sync: this machine (local), `distilo`, `engage` (both via SSH).

## Workflow rules

### Editing the `ak` plugin

The `ak` plugin lives at `plugin/`. When committing changes there:

- The `pre-commit` hook auto-bumps the **patch** version in both `plugin/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` so consumers' `claude plugin update ak@ak-plugins` detects the change.
- For minor or major bumps, run `AK_BUMP=minor git commit ...` or `AK_BUMP=major git commit ...`.
- To skip the bump (e.g. for hook fixes, docs-only commits inside `plugin/`), use `AK_BUMP=skip` or `AK_NO_BUMP=1`.
- For out-of-band bumps without committing, run `./scripts/bump.sh patch|minor|major`.
- If the staged diff already changes `"version"`, the hook detects this and skips its auto-bump.

The hook is registered via `git config core.hooksPath .githooks`. Re-run that command after a fresh clone.

### Adding a plugin to the marketplace

`.claude-plugin/marketplace.json` is the catalog. Add an entry with one of:

- `"source": "./local-path"` for plugins living in this repo
- `"source": { "source": "github", "repo": "owner/repo" }` for a whole-repo external plugin
- `"source": { "source": "git-subdir", "url": "...", "path": "plugins/x", "ref": "main" }` for a subdir of another repo

Validate before commit:

```bash
claude plugin validate /home/christinoleo/Projects/ak-plugins
```

Adding a plugin entry counts as a `plugin/` change for the version hook only if it also touches `plugin/`; marketplace.json changes are filtered into the same auto-bump path.

### Multi-machine rollout

After pushing a change that affects the marketplace, propagate to remotes:

```bash
ssh distilo 'bash -lc "claude plugin marketplace update ak-plugins && claude plugin update ak@ak-plugins"'
ssh engage  'bash -lc "claude plugin marketplace update ak-plugins && claude plugin update ak@ak-plugins"'
```

The marketplaces sometimes cache stale content in `~/.claude/plugins/marketplaces/ak-plugins/`. If `claude plugin update` reports "already at latest" but you know it isn't, force a `git pull` in that directory:

```bash
ssh distilo 'bash -lc "cd ~/.claude/plugins/marketplaces/ak-plugins && git pull origin main"'
```

### `ak` commands use GitHub Issues, not Beads

The plugin used to depend on the `bd` (Beads) CLI; that was swapped out in v1.1.0 for the `gh issue` CLI. Epic/task structure now uses:

- Epic issues labeled `epic` with a task list `- [ ] #<task-id>` in the body
- Task issues labeled `task` with `Part of #<epic-id>` in the body
- `ready` label = no blockers; remove on `in-progress`
- `gh issue list --label ready --state open --search "\"Part of #<EPIC>\" in:body"` is the "ready under this epic" query

Do not reintroduce `bd` references when editing commands.

### Plugins we do NOT want

- `hookify` from `anthropics/claude-code` was removed from the marketplace because its `pretooluse.py` import path breaks under the plugin manager's versioned cache layout. If upstream fixes it, the entry can be re-added.

## Caveman scope (when active)

If `caveman` mode is active in the session, it governs conversation only. **Never apply caveman register to files** in this repo — commands, command descriptions, README, plugin.json descriptions, and CLAUDE.md are all artifacts read by other people and other agents. Write them in normal prose regardless of conversation register.
