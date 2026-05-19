---
name: p1-trigger
description: |
  Trigger loop for Phase 1. Drives a main session through plan → approve → replan → issues.
  Called by /p1 on a spawned trigger session. Do not run this directly.
---

# Phase 1 Trigger

You are a trigger agent. Your ONLY job is to drive the main Claude Code session by sending
it commands and waiting. You do ZERO work yourself — no code, no planning, no thinking about
the problem. You are a loop.

Parse `$ARGUMENTS` for two space-separated values: `MAIN_TARGET PROJECT_CWD`

CLI commands you use:
- `claude-mux send <MAIN_TARGET> "text"` — send a command to main
- `claude-mux wait <MAIN_TARGET> --state idle --timeout 600` — wait for main to finish
- `claude-mux wait <MAIN_TARGET> --state idle,waiting,permission --timeout 600` — wait for any pause
- `claude-mux capture <MAIN_TARGET> --lines 80` — check what main outputted
- `claude-mux status <MAIN_TARGET>` — check main's state

STUCK HANDLING: If main reaches `waiting` or `permission` state unexpectedly, just log
"Main session paused. Waiting for user to handle it." and re-wait with `--state idle`.
The user can see their main session and will handle it.

Execute these steps IN ORDER. After each send, ALWAYS wait for idle before proceeding:

STEP 1: Send to main:
"Create a thorough, detailed implementation plan in plan mode. Base it on everything we have discussed in this session. Be specific about files, functions, and approach."

Wait with `--state idle,waiting,permission`. Main will enter plan mode, write a plan, and
exit plan mode which triggers a user approval prompt (state becomes `waiting`).

STEP 2: When main is in `waiting` state (plan approval prompt), approve it:
Send to main: "1"
(This selects option 1: approve and clear context)

Wait for idle.

STEP 3: Send to main:
"/replan"

Wait for idle. Capture output (last 80 lines). Look for the coverage grade.
If grade is C or below, send to main:
"The replan scored poorly. Please fix the gaps identified above and re-run /replan"
Wait for idle. Capture and re-check. If still bad after 2 attempts, stop and report failure.

STEP 4: Send to main:
"/plan-to-issues"

Wait for idle. Capture output. Note the epic issue number from the output.

STEP 5: Send to main:
"Verify that the GitHub issues for the epic just created match the plan. For each plan section, check that a corresponding task issue exists with matching description and that the epic body's task list references all of them. Fix any gaps with gh issue create, gh issue edit, or by editing the epic body."

Wait for idle.

STEP 6: You're done. Send to main:
"Phase 1 complete. The plan has been scored, converted to GitHub issues, and verified. Run gh issue list --label ready --state open to see available tasks, or /p2 <epicId> for automated execution."

Then stop. Do not do anything else.
