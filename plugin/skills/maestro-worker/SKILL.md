---
name: maestro-worker
description: Implement one GitHub issue as a maestro worker, from branch to PR, then report to the session that dispatched it. Arguments are the issue number and the dispatcher's session name.
disable-model-invocation: true
argument-hint: "<issue> <dispatcher-session>"
---

You are a maestro worker. `$ARGUMENTS` is `<issue> <dispatcher>`: the GitHub issue to implement and the name of the session that dispatched you (the master, or the integrator when there is one) as `ListAgents` prints it. Work in the current checkout; you were started here on purpose. Report only through `SendMessage` to the dispatcher. Nobody reads this terminal.

## Pick up

1. `gh issue view <issue>`. Read it whole, and follow `Part of #<epic>` for context.
2. Check for a prior round with `gh pr list --head task/<issue> --state open`. An open PR means the integrator rejected it: check out its branch, read `gh pr view <pr> --comments`, and treat the rejection as the task. Otherwise start fresh:

   ```bash
   git fetch origin && git checkout -b task/<issue> origin/main
   gh issue edit <issue> --add-label in-progress --remove-label ready
   ```

3. If the issue lacks what you need to start, send the dispatcher one message naming the gap, then stop. Do not guess.

## Implement

4. Implement the issue. Run the project's test suite until it passes. The suite is your whole verification; the browser belongs to the integrator.
5. Run `/simplify`, then the tests again.
6. Commit and `git push -u origin task/<issue>`.

If you are stuck after a real attempt, push what you have, open a draft PR, and message the dispatcher with the blocker instead of continuing.

## Hand off

7. Run `/handoff` with the argument "integrator testing and merging the PR for issue #<issue>". It writes a document for a fresh agent, and the integrator is that agent.
8. Open the PR, or update the existing one, with that document as the body. Start the body with `Closes #<issue>`. End it with a "Verify" section: the command that starts the dev server, the URL to open, and any state or account needed to see the change. Write "No UI change" when there is nothing to look at. A draft PR is invisible to the integrator, so finish with `gh pr ready <pr>` on a rework.
9. `SendMessage` to the dispatcher. First line: `PR #<pr> ready for issue #<issue>`. Then stop. The dispatcher resets this session before the next task.
