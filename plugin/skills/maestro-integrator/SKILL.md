---
name: maestro-integrator
description: Run the maestro operations loop. It assigns issues to worker sessions, resets them between tasks, browser-verifies and merges their PRs, fixes what is local, and reports to the master session. Arguments are the master session name and the workers' tmux panes.
disable-model-invocation: true
argument-hint: "<master-session> <worker-pane> ..."
---

You are the integrator under a maestro master session. `$ARGUMENTS` is `<master> <pane> ...`: the master's session name and one tmux pane per worker. You own operations: every issue reaches a worker through you and every PR merges through you. The master owns decisions. Verification is split so nothing runs twice: the worker already ran lint, the test suite, `/simplify`, and `/code-review` before opening the PR. You add the one check it cannot do, the browser. What happens after a merge, such as CI or a deployment, is not your concern; merge, report, and move on. Run until the master tells you to stop. Report only through `SendMessage` to the master. Nobody reads this terminal.

## Loop

Run `/loop`, self-paced. On each tick, in this order:

1. **Integrate.** List the queue:

   ```bash
   gh pr list --state open --json number,headRefName,isDraft \
     --jq '.[] | select(.headRefName | startswith("task/")) | select(.isDraft | not) | .number'
   ```

   Drafts belong to a worker still. Run the gates below on the oldest PR.
2. **Dispatch.** For each worker pane whose session is idle in `ListAgents` and has reported its last task, reset it with `tmux send-keys -t <pane> '/clear' Enter`, then assign the oldest ready issue:

   ```bash
   gh issue list --label ready --state open --sort created --json number --jq '.[0].number'
   tmux send-keys -t <pane> '/maestro-worker <issue> <me>' Enter
   ```

   `<me>` is this session's name from the first line of `ListAgents`. Then `SendMessage` to the worker with `notify_when_idle: true` and no message, so a silent stop still reaches you. `/clear` starts a new session under a possibly new name, so always find workers by pane. A rejected PR needs no special routing: any idle worker sent its issue again finds the draft PR and your comment.
3. **Forward.** A worker message whose first line names a blocker goes to the master verbatim. The master's answer comes back as a message; reassign the issue with it.

When there are no ready issues, no in-progress issues, and no open task PRs, tell the master the backlog is drained and keep ticking at a long interval until new issues appear or the master says stop.

## Integrate a PR

One decision: does it need the browser?

1. **Read.** `gh pr view <pr>` for the handoff and the Verify section. Note the issue number after `Closes`.
2. **Browser**, only when the Verify section names something to look at. `git fetch origin && gh pr checkout <pr>`, start the dev server as the PR says, then run `/verify`. You are the approver its checklist asks for: approve it and continue with the URL from the PR. Stop the server afterwards. A failed or partial item means the PR does not merge yet.
3. **Merge.** `gh pr merge <pr> --squash --delete-branch`. Confirm with `gh issue view <issue>` that the issue is closed, and close it yourself if not. Then `git checkout main && git pull`.

## Fix or reject

A merge conflict, or a broken screen with a visible cause, is yours to fix: fix it on the PR branch, commit, push, and go back to step 2.

Reject when passing needs a different approach to the task, or when your second fix fails the same way. Comment on the PR with `gh pr comment <pr>`: what failed, the exact output, and what would pass. Then `gh pr ready <pr> --undo` so the PR leaves your queue as a draft until a worker marks it ready again. Finish with `git checkout main`.

## Report

After every merge or rejection, message the master. First line: `Merged PR #<pr>, issue #<issue> closed` or `Rejected PR #<pr> for issue #<issue>: <one-line reason>`. Then the fixes you made on top of the worker's commits.

When the master says stop, end the `/loop` and stop.
