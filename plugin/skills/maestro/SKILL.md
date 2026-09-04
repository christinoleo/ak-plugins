---
name: maestro
description: Make this session the master orchestrator. It interviews requirements, files them as tasks, and drives maestro-worker sessions, either through its own /loop or through a maestro-integrator session that runs the loop for it.
disable-model-invocation: true
---

This session is the master orchestrator. It interviews, plans, and decides. Workers implement through the `maestro-worker` skill. The integrator dispatches, tests, and merges through the `maestro-integrator` skill. Delegate every operational step to one of them, so this session spends its context on decisions only.

## Setup

Ask the user once and keep the answers for the session.

1. **Backlog.** GitHub Issues (the epic/task structure `/plan-to-issues` produces) or a local `TASKS.md` checklist.
2. **Workers.** How many, and which transport: Opus sessions in tmux over A2A (`SendMessage`), an agent team, or subagents. On tmux, each worker is a `claude` session started inside its own checkout, in its own pane.
3. **Worktrees.** With more than one worker, offer one git worktree per worker if the project builds and tests in parallel checkouts. Otherwise recommend fewer workers on one checkout.
4. **Integrator.** With two or more workers on a GitHub backlog, offer one. It is an extra Opus session in tmux, started inside its own checkout of main. It runs the operations loop: it assigns issues to workers, resets them between tasks, verifies UI changes in the browser, fixes what is local, and merges. Verification is split once: workers run lint, tests, `/simplify`, and `/code-review`; the integrator runs the browser; nobody watches CI or deployments. Browser verification is slow and memory-hungry, so one session does it for everyone.

Get this session's own name from the first line of `ListAgents`. `ListAgents` also shows each local session's tmux pane, which is how workers are addressed on tmux.

## Intake

Run every requirement through the installed skills. `grilling` stress-tests the idea. `research` and `domain-modeling` fill gaps. `/replan` checks coverage. Then file the tasks with `/plan-to-issues` on a GitHub backlog, or append them to `TASKS.md` on a local one.

Architecture is intake too. At the start of an engagement, and again after a batch of tasks has merged, run `improve-codebase-architecture` (after `domain-modeling` when the project has no `CONTEXT.md`). It surfaces deepening opportunities and grills the user through the ones they pick. The picks become issues like any other requirement, and workers implement them.

## With an integrator

Invoke it once and do not loop:

```bash
tmux send-keys -t <integrator-pane> '/maestro-integrator <master> <worker-pane> <worker-pane> ...' Enter
```

From then on this session reacts. New input from the user goes through Intake and lands in the backlog, where the integrator picks it up. A worker blocker forwarded by the integrator is a decision: resolve it or take it to the user, then reply to the integrator. Merge and rejection reports need no action. When the integrator reports the backlog drained and the user has nothing pending, message it to stop.

## Without an integrator

Run `/loop`, self-paced. A worker runs one task per invocation and stops, so this loop drives everything. On each tick:

1. **Assign** the next ready task to an idle worker. On tmux, run `tmux send-keys -t <pane> '/maestro-worker <issue> <master>' Enter`, then `SendMessage` to the worker with `notify_when_idle: true` and no message, so a silent stop still reaches you. On a subagent or team transport, read `${CLAUDE_PLUGIN_ROOT}/skills/maestro-worker/SKILL.md` and put its body in the prompt with the same two arguments. On a local backlog, replace the issue number with the task text and its `TASKS.md` line.
2. **Check** the running workers. A worker's report arrives as a `SendMessage` whose first line names its PR or its blocker. A blocker is a decision: resolve it or take it to the user, then reassign.
3. **Integrate.** Review and merge the PR and close the issue. On a local backlog, commit the task and check its item off.
4. **Reset** a worker before its next task. On tmux, once the idle notice has arrived, run `tmux send-keys -t <pane> '/clear' Enter`, then list again and find the session by pane, since `/clear` starts a new session under a possibly new name. `SendMessage` delivers text as context rather than keystrokes, so a `/clear` or a skill invocation sent that way is read as a message and does nothing.

New input from the user between ticks goes through Intake while the loop keeps running. Stop the loop when the backlog is empty and the user has nothing pending.
