---
name: maestro
description: Make this session the master orchestrator. It interviews requirements, files them as tasks, and runs a /loop that hands tasks to worker agents and finished work to an integrator.
disable-model-invocation: true
---

This session is the master orchestrator. It interviews, plans, and decides. Workers implement. The integrator tests and merges. Delegate every operational step to one of them, so this session spends its context on decisions only.

## Setup

Ask the user once and keep the answers for the session.

1. **Backlog.** GitHub Issues (the epic/task structure `/plan-to-issues` produces) or a local `TASKS.md` checklist.
2. **Workers.** How many, and which transport: Opus sessions in tmux over A2A (`SendMessage`), an agent team, or subagents.
3. **Worktrees.** With more than one worker, offer git worktrees if the project builds and tests in parallel checkouts. Otherwise recommend fewer workers on one checkout.
4. **Integrator.** With two or more workers on a GitHub backlog, offer one. It is an extra Opus session in tmux on its own checkout of main. Workers run the project's test suite in their worktree and open a PR. The integrator runs the tests again, verifies UI changes in the browser through the Chrome DevTools MCP (`/verify`), and merges when both pass. Browser verification is slow and memory-hungry, so one session does it for everyone.

## Intake

Run every requirement through the installed skills. `grilling` stress-tests the idea. `research` and `domain-modeling` fill gaps. `/replan` checks coverage. Then file the tasks with `/plan-to-issues` on a GitHub backlog, or append them to `TASKS.md` on a local one.

## Orchestration loop

Run `/loop`, self-paced. On each tick:

1. **Assign** the next ready task to an idle worker. A worker starts each task with an empty context, so the message carries everything: the task text, the branch or worktree, the test command, where to open the PR. On tmux, send with `notify_when_idle: true` and wait for the idle notice.
2. **Check** the running workers.
3. **Integrate.** Hand each finished PR to the integrator and wait for its verdict, merged or rejected with a reason. Forward a rejection to the worker that owns the task. Without an integrator, review and merge the PR and close the issue yourself. On a local backlog there is no integrator: commit the task and check its item off.
4. **Reset** the worker before its next task. On tmux, `ListAgents` shows each session's pane. Once the idle notice has arrived, run `tmux send-keys -t <pane> '/clear' Enter`, then list again and find the worker by pane, since `/clear` starts a new session under a possibly new name. `SendMessage` delivers text as context rather than keystrokes, so `/clear` sent that way is read as a message and does nothing.

New input from the user between ticks goes through Intake while the loop keeps running. Stop the loop when the backlog is empty, the integrator's queue is empty, and the user has nothing pending.
