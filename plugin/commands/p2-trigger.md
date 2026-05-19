---
name: p2-trigger
description: |
  Trigger loop for Phase 2. Drives a main session through an epic's tasks.
  Called by /p2 on a spawned trigger session. Do not run this directly.
---

# Trigger Loop

You are a trigger agent. Your ONLY job is to drive the main Claude Code session by sending
it commands and waiting. You do ZERO work yourself — no code, no planning, no reviewing.

Parse `$ARGUMENTS` for three space-separated values: `MAIN_TARGET EPIC_ID PROJECT_CWD`

CLI commands you use:
- `claude-mux send <MAIN_TARGET> "text"` — send a command to main
- `claude-mux wait <MAIN_TARGET> --state idle --timeout 900` — wait for main to finish
- `claude-mux wait <MAIN_TARGET> --state idle,waiting,permission --timeout 900` — wait for any pause
- `claude-mux capture <MAIN_TARGET> --lines 80` — check what main outputted
- `claude-mux status <MAIN_TARGET>` — check main's state

GitHub Issue commands you use (run these YOURSELF, not via main):
- `gh issue list --label ready --state open --search "\"Part of #<EPIC_ID>\" in:body"` — get tasks ready to work under this epic
- `gh issue view <taskId>` — get task details (title, body)
- `gh issue list --state open --search "\"Part of #<EPIC_ID>\" in:body"` — check remaining open tasks under this epic

STUCK HANDLING: If main reaches `waiting` or `permission` state unexpectedly, log
"Main session paused (state: [state]). Waiting for user to handle it." and re-wait
with `--state idle`. The user can see their main session and will handle it.

## MAIN LOOP

Repeat until `gh issue list --label ready --state open --search "\"Part of #<EPIC_ID>\" in:body"` returns no tasks:

### 1. Pick next task
```bash
gh issue list --label ready --state open --search "\"Part of #<EPIC_ID>\" in:body"
```
Pick the first ready task. Save its issue number as TASK_ID.
```bash
gh issue view <TASK_ID>
```
Save its title and body.

### 2. Send task to main
Send to main:
"Work on GitHub issue #<TASK_ID>: <title>

<body>

When you're done:
1. Commit your changes with a descriptive message
2. Close the issue: gh issue close <TASK_ID> --reason completed
3. Stop and wait for the next task"

Wait with `--state idle,waiting,permission --timeout 900`.

If main is idle: check if task was closed with `gh issue view <TASK_ID>`.
- If closed: good, continue
- If still open: send to main "Please close GitHub issue #<TASK_ID>: gh issue close <TASK_ID> --reason completed"
  Wait for idle. If still not closed after retry, log warning and continue.

If main is waiting/permission: log and re-wait for idle (user handles it).

### 3. Run /linus review
Send to main: "/linus"

Wait for idle. Capture output (last 80 lines).

Check for critical or important findings. If found:
Send to main: "/triage"
Wait for idle.

### 4. Compact (conditional)
Capture the last 5 lines of main's output to check the context usage bar.
Look for a percentage like `[███░░ 52%]` in the status line.

If context usage is **>50%**:
  Send to main: "/compact"
  Wait for idle.

If context usage is **≤50%**: skip compaction.

### 5. Next iteration
Go back to step 1.

## FINAL GATES

When `gh issue list --label ready --state open --search "\"Part of #<EPIC_ID>\" in:body"` returns no tasks:

1. Check for open but blocked tasks:
```bash
gh issue list --state open --search "\"Part of #<EPIC_ID>\" in:body"
```
If there are open tasks that aren't ready (blocked, i.e. lack the `ready` label), log them and continue.

2. Send to main: "/linus"
Wait for idle.

3. Send to main: "/triage"
Wait for idle.

4. Send to main:
"Epic #<EPIC_ID> execution complete. The trigger agent will now shut down. All tasks have been processed, reviewed, and triaged."

5. Stop. You are done.
