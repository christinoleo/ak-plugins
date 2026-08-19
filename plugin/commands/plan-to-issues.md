---
name: plan-to-issues
description: |
  Convert an approved plan into a GitHub Issues epic with tasks. Detects parallel vs sequential
  phases from plan structure and sets dependencies accordingly. Run after /replan approval.
---

# Plan to GitHub Issues: epic plus tasks

Convert the current approved plan into a GitHub Issues epic with properly structured tasks and
dependencies. This bridges the gap between "we know what to do" and "let's track execution."

## Step 1: find the plan

Locate the plan file:
- Check the most recent plan: `ls -t ~/.claude/plans/*.md | head -1`
- If argument provided (`$ARGUMENTS`), use that path instead
- Read the plan file completely

If no plan file exists, check the conversation history for the most recently approved plan
(from ExitPlanMode). Use that content directly.

## Step 2: parse the plan

Extract from the plan:

1. **Title.** First heading or `# Plan:` line
2. **Summary.** Content under `## Summary` or the first paragraph
3. **Phases/Steps.** Each `### Phase N:`, `### N.`, or numbered section
4. **Files affected.** Any file paths mentioned (include in epic description)
5. **Dependency structure.** Determine what depends on what:

### Detecting parallel vs sequential

- **Sequential indicators:** "after", "then", "once X is done", "depends on", numbered order
  with no contrary signals
- **Parallel indicators:** "simultaneously", "independently", "can be done in parallel",
  tasks in different domains (e.g., frontend + backend), tasks touching unrelated files
- **When ambiguous:** Default to sequential, but flag it and ask the user

Build a dependency graph, not just a linear chain.

## Step 3: create tasks first

For each phase/step in the plan, create a task issue:

```bash
gh issue create --title "[Phase title]" --label task --body "[first paragraph of phase content].

Part of #<epic-id-placeholder>"
```

- Use the first paragraph as the description (keep it scannable)
- Preserve any acceptance criteria or specific requirements in the body
- If a phase has sub-steps, include them as a checklist in the body
- Capture each created issue number from the output

Tasks that have no blockers should also receive the `ready` label:

```bash
gh issue edit <task-id> --add-label ready
```

Tasks that are blocked should mention "Blocked by #<other-id>" in their body and stay without
the `ready` label.

## Step 4: create the epic

Now create the epic with a task list referencing every task issue created in Step 3. GitHub
will auto-track completion of `- [ ]` items that reference issue numbers.

```bash
gh issue create --title "[Plan Title]" --label epic --body "[summary]

Files: [list affected files]

## Tasks
- [ ] #<task1-id>
- [ ] #<task2-id>
- [ ] #<task3-id>

## Dependencies
- #<task2-id> blocked by #<task1-id>
- #<task3-id> ready (parallel with #<task4-id>)
"
```

Capture the epic ID from the output.

## Step 5: backfill parent reference

For each task created in Step 3, edit its body to replace `<epic-id-placeholder>` with the
real epic number from Step 4:

```bash
gh issue edit <task-id> --body "[body with Part of #<epic-id> filled in]"
```

This gives every task a back-link to its epic via the body, and the epic auto-tracks task
completion via its task list.

## Step 6: report

Output a clear summary:

```
Created from: [filename or "conversation plan"]

Epic: [title] (#<epic-id>)
  ├── [Phase 1] (#<id>) ready
  ├── [Phase 2] (#<id>) blocked by #<phase1-id>
  ├── [Phase 3] (#<id>) ready, parallel with Phase 4
  ├── [Phase 4] (#<id>) ready, parallel with Phase 3
  └── [Phase 5] (#<id>) blocked by #<phase3-id>, #<phase4-id>

Dependency graph:
  Phase 1 → Phase 2
  Phase 1 → Phase 3 ┐
  Phase 1 → Phase 4 ┤→ Phase 5
                     ┘

Total: [N] tasks ([M] ready, [K] blocked)
Run `gh issue list --label ready --state open` to start working.
```

## Rules

- Preserve the original plan file. Never modify or delete it
- Task descriptions use first paragraph only unless there are critical details
- When in doubt about parallel vs sequential, ASK. Wrong dependencies waste time
- If the plan has no clear phases (just a wall of text), break it into logical chunks and
  confirm the breakdown with the user before creating issues
