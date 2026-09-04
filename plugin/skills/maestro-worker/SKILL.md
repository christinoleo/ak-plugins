---
name: maestro-worker
description: Implement one GitHub issue as a maestro worker, from worktree to PR. The argument is the issue number.
disable-model-invocation: true
argument-hint: "<issue>"
---

You are a maestro worker. `$ARGUMENTS` is the GitHub issue to implement. The daemon that started you reads GitHub, not this terminal: your PR and its labels are your whole report, and it kills this session once the PR is ready. Your session sits at the repo root; the work happens in a worktree under `.worktree/<issue>`, which is gitignored.

## Pick up

1. `gh issue view <issue>`. Read it whole, and follow `Part of #<epic>` for context. When the issue is an architecture task (a deepening, a seam, an adapter), load the `codebase-design` skill first and use its vocabulary.
2. Check for a prior round with `gh pr list --head task/<issue> --state open`. An open draft PR means the integrator sent it back: create the worktree from the remote branch, read `gh pr view <pr> --comments`, and treat the rejection as the task.

   ```bash
   git fetch origin && git worktree add -B task/<issue> .worktree/<issue> origin/task/<issue>
   ```

   Otherwise start fresh:

   ```bash
   git fetch origin && git worktree add -b task/<issue> .worktree/<issue> origin/main
   ```

   From here on every command runs inside `.worktree/<issue>`. Install dependencies there if the project needs them.
3. If the issue lacks what you need to start, label it and stop. Do not guess.

   ```bash
   gh issue edit <issue> --add-label needs-help
   gh issue comment <issue> --body "Blocked: <what is missing>"
   ```

## Implement

4. Implement the issue.
5. Before committing, run this checklist in order:
   1. The project's lint and test suite, until both pass.
   2. `/simplify`, as a subagent: spawn an agent whose prompt is to invoke the skill on the working tree, so its output stays out of your context.
   3. `/code-review` at medium, as a subagent the same way. Fix what it finds.
   4. Lint and tests again.

   The suite is your whole verification; the browser belongs to the integrator.
6. Commit and `git push -u origin task/<issue>`.

If you are stuck after a real attempt, push what you have, open a draft PR, label the issue `needs-help` with a comment naming the blocker, remove the worktree as in step 9, and stop.

## Hand off

7. Run `/handoff` with the argument "integrator checking the PR for issue #<issue>". It writes a document for a fresh agent, and the integrator is that agent.
8. Open the PR as a draft, or update the existing one, with that document as the body. Start the body with `Closes #<issue>`. End it with a "Verify" section: the command that starts the dev server, the URL to open, and any state or account needed to see the change. Write "No UI change" when there is nothing to look at. Then label it:
   - `needs-browser` when the change is visible in a UI.
   - `needs-migration` when it adds or edits a database migration.

   A PR with neither label merges without anyone looking at it again.
9. Remove the worktree: `git worktree remove --force .worktree/<issue>`. Everything is pushed, so nothing is lost.
10. `gh pr ready <pr>`. This is the signal: the daemon merges it or hands it to the integrator, and ends this session. Stop.
