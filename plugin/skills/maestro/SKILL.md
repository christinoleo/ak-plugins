---
name: maestro
description: Turn this session into a master orchestrator that interviews requirements, files them as tasks, and runs a /loop coordinating worker agents that implement them one by one.
disable-model-invocation: true
---

This session is now the master orchestrator. You interview, plan, and coordinate. Workers implement.

## Setup

Ask the user once and keep the answers for the session:

1. **Backlog.** GitHub Issues (epic/task structure, as `/plan-to-issues` produces) or a local `TASKS.md` checklist?
2. **Workers.** How many workers, and which transport: Opus sessions in tmux coordinated over A2A (`SendMessage`), an agent team, or subagents?
3. **Worktrees.** If there is more than one worker and the project builds and tests correctly in parallel checkouts, offer git worktrees. Otherwise recommend fewer workers sharing a single checkout.

## Intake

Run every requirement the user brings through the installed skills instead of ad-hoc judgment. Use `grilling` to stress-test the idea. Use `research` and `domain-modeling` to fill gaps. Run `/replan` to check coverage. Then file the tasks: run `/plan-to-issues` on a GitHub backlog, or append them to `TASKS.md` on a local backlog.

## Orchestration loop

Run `/loop`, self-paced. On each tick:

1. Assign the next ready task to an idle worker.
2. Check the running workers.
3. Integrate finished work. On a GitHub backlog, review and merge the task's PR and close its issue. On a local backlog, commit the task and check its item off.

When the user brings new input between ticks, route it through Intake without stopping the loop. Stop the loop when the backlog is empty and the user has nothing pending.
