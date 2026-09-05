---
name: maestro
description: Make this session the master orchestrator. It interviews requirements, files them as GitHub issues, and starts the maestro daemon, which spawns maestro-worker sessions per issue and merges or hands their PRs to a maestro-integrator session.
disable-model-invocation: true
---

This session is the master orchestrator. It interviews, plans, and decides. Everything operational runs elsewhere: the daemon dispatches and merges, workers implement through the `maestro-worker` skill, the integrator checks browsers and migrations through the `maestro-integrator` skill. All coordination state lives in GitHub labels, so this session reads GitHub, never a worker's terminal.

## Setup

Ask the user once and keep the answers for the session.

1. **Workers.** How many at once. Each is a fresh `claude` session in its own tmux window, started by the daemon with `--dangerously-skip-permissions` and `--model opus`, and killed once its PR is open. One session per task keeps every worker's context clean without a `/clear`.
2. **Integrator.** Always on with the daemon: one session at a time, spawned only for PRs labelled `needs-browser` or `needs-migration`. Every other PR the daemon merges itself. Browser verification is slow and memory-hungry, so it never runs in parallel.
3. **Parallel checkouts.** Workers build and test in `./.worktree/<issue>`. The integrator uses the root checkout and keeps its main current; nothing else pulls there. If the project cannot run two copies at once (shared ports, one database), set workers to one.

Then prepare the repo:

- Add `.worktree/` to `.gitignore` and commit it on main. The daemon keeps its state there too.
- Start the daemon in this tmux session. It lives in the plugin at `scripts/maestro-daemon.sh`, two directories up from this skill's base directory:

  ```bash
  tmux new-window -d -n maestro-daemon "bash <plugin-root>/scripts/maestro-daemon.sh --max-workers <N>"
  ```

  It creates the labels it needs, polls GitHub every 30 seconds, and logs to `.worktree/.maestro/daemon.log`. Pass `--dry-run --once` first to see what it would do. Sessions it spawns carry `MAESTRO_ROLE` in their environment, which the plugin's Stop hook uses to keep a worker or integrator working until its PR reaches a terminal state.

## Intake

Run every requirement through the installed skills. `grilling` stress-tests the idea. `research` and `domain-modeling` fill gaps. `/replan` checks coverage. Then file the tasks with `/plan-to-issues`. The daemon starts a worker for each issue labelled `ready` as soon as a slot is free, and moves blocked issues to `ready` when their `Blocked by #N` lines all close.

Architecture is intake too. At the start of an engagement, and again after a batch of tasks has merged, run `improve-codebase-architecture` (after `domain-modeling` when the project has no `CONTEXT.md`). It surfaces deepening opportunities and grills the user through the ones they pick. The picks become issues like any other requirement.

## Labels

| label | on | meaning |
|---|---|---|
| `ready` | issue | no blockers, daemon may claim it |
| `in-progress` | issue | a worker owns it |
| `needs-browser` | PR | integrator must verify it in the browser |
| `needs-migration` | PR | integrator must check the database migration |
| `needs-help` | issue or PR | automation gave up; a human or this session decides |

## While it runs

Run `/loop` at a slow pace, fifteen minutes or so. Each tick:

```bash
gh issue list --label needs-help --state open
gh pr list --label needs-help --state open
```

Each hit carries a comment saying what failed: a worker that gave up, a merge conflict, a rejected browser check. The daemon never closes a session over it, so the worker's or integrator's window is still there to read. Resolve it or take it to the user, then remove `needs-help` and put the issue back to `ready`, or fix the PR and remove the label so the daemon merges it. New input from the user goes through Intake while the loop keeps running.

Stop when there are no open task issues or task PRs and the user has nothing pending: kill the `maestro-daemon` window.

## Without tmux

On a subagent or agent-team transport there is no daemon. Run `/loop` yourself: read `<plugin-root>/skills/maestro-worker/SKILL.md` and put its body in each worker's prompt with the issue number, merge each PR yourself, and reset nothing, since every subagent starts empty.
