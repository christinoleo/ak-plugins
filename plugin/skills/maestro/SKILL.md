---
name: maestro
description: Make this session the master orchestrator. It interviews requirements, files them as GitHub issues, and starts the maestro daemon, which spawns one maestro-worker session per issue. Workers implement, verify, and merge on their own and label needs-help when a decision is needed.
disable-model-invocation: true
---

This session is the master orchestrator. It interviews, plans, and decides. The daemon dispatches. Workers implement and merge through the `maestro-worker` skill. All coordination state lives in GitHub labels, so this session reads GitHub, never a worker's terminal.

## Setup

Ask the user once and keep the answers for the session.

1. **Workers.** How many at once. The daemon starts each one as a fresh `claude` session in its own tmux window, named `mw-<issue>-<title>`, with `--dangerously-skip-permissions` and `--model opus`, and kills it once its issue is closed. One session per task keeps every worker's context clean.
2. **Parallel checkouts.** Workers build, test, and run dev servers in `./.worktree/<issue>`. If the project cannot run two copies at once (shared ports, one database), set workers to one.

Then prepare the repo:

- Add `.worktree/` to `.gitignore` and commit it on main. The daemon keeps its state there too.
- Start the daemon in this tmux session. It lives in the plugin at `scripts/maestro-daemon.sh`, two directories up from this skill's base directory:

  ```bash
  tmux new-window -d -n maestro-daemon "bash <plugin-root>/scripts/maestro-daemon.sh --max-workers <N>"
  ```

  It creates the labels it needs, polls GitHub every 30 seconds, and logs to `.worktree/.maestro/daemon.log`. Pass `--dry-run --once` first to see what it would do. Sessions it spawns carry `MAESTRO_ROLE` in their environment. The plugin's Stop hook reads it and keeps a worker working until its issue is closed or it has asked for help.

## Intake

Stress-test each requirement with `grilling`, then file the tasks with `/plan-to-issues`. The daemon starts a worker for each issue labelled `ready` as soon as a slot is free, and moves blocked issues to `ready` when their `Blocked by #N` lines all close. Reach for `research`, `domain-modeling`, or `/replan` when a requirement is unclear, not as a fixed step.

## Labels

| label | meaning |
|---|---|
| `ready` | no blockers, daemon may claim it |
| `in-progress` | a worker owns it |
| `needs-help` | the worker wants a decision from this session or the user |

Workers merge their own PRs. They stop and label `needs-help` instead when the change carries a database migration, when a rebase would risk dropping someone else's work, or when they are stuck. Nobody re-verifies a merged PR. When something on main turns out broken, file an issue and it becomes a task like any other.

## While it runs

Run `/loop` at a slow pace, fifteen minutes or so. Each tick:

```bash
gh issue list --label needs-help --state open
```

Each hit carries a comment saying what the worker needs. The daemon never closes a session over it, so the worker's window is still there to read. Decide, or take it to the user. Then either finish the task yourself (merge the PR, close the issue) or remove `needs-help` and put the issue back to `ready` so a fresh worker picks it up with your comment. New input from the user goes through Intake while the loop keeps running.

Once there are no open task issues and the user has nothing pending, kill the `maestro-daemon` window.

## Without tmux

On a subagent or agent-team transport there is no daemon. Run `/loop` yourself: read `<plugin-root>/skills/maestro-worker/SKILL.md` and put its body in each worker's prompt with the issue number.
