---
name: verify
description: |
  Browser-based verification of implemented changes and related functionality. Generates a
  test checklist from what changed, gets user approval, then systematically tests each item
  using Chrome DevTools. Run after implementation is complete.
---

# Verify: Browser-Based Testing

Systematically verify that implemented changes work correctly AND haven't broken related
functionality. Use the browser (Chrome DevTools MCP) to test everything visually.

## Phase 1: Build the Checklist

Analyze what was implemented by examining:

1. **Git diff** — `git diff` and `git log` to see what files changed
2. **Conversation history** — What features/fixes were implemented
3. **GitHub issues** — If tracking with gh issues, check what was closed this session via `gh issue list --search 'closed:>=<date>'`

From this, build two categories of test items:

### Direct Changes (must pass)
Things that were explicitly changed or added:
- New UI elements visible and functional
- Modified behavior working as expected
- Fixed bugs no longer reproducing
- API endpoints returning correct data

### Related Areas (regression check)
Functionality connected to what changed:
- Adjacent UI components still rendering correctly
- Navigation flows that touch modified pages
- Data that feeds into or out of modified components
- Edge cases: empty states, error states, loading states

### Checklist Format

```
## Verification Checklist

### Direct Changes
- [ ] DC1: [Description] — [how to test]
- [ ] DC2: [Description] — [how to test]
- [ ] DC3: [Description] — [how to test]

### Related Areas
- [ ] RA1: [Description] — [what to check]
- [ ] RA2: [Description] — [what to check]

Total: [N] items ([X] direct, [Y] related)
```

## Phase 2: User Approval

Present the checklist and ask:
- "Anything missing from this list?"
- "Any items you want to skip?"
- "What URL should I start at?"

Adjust the checklist based on feedback before proceeding.

## Phase 3: Execute Tests

For each checklist item, using Chrome DevTools:

1. **Navigate** to the relevant page
2. **Take a snapshot** to understand the current state
3. **Interact** — click, fill forms, navigate as needed to test the item
4. **Take a screenshot** if something looks wrong or noteworthy
5. **Record result:**

```
### DC1: [Description]
**Status:** ✅ Pass / ❌ Fail / ⚠️ Partial
**What I did:** [actions taken]
**Result:** [what happened]
**Screenshot:** [if relevant]
```

### Testing Strategy

- **Don't rush.** Take snapshots before and after actions
- **Check visual state** — elements visible, correct text, proper styling
- **Check interactions** — buttons work, forms submit, navigation flows
- **Check data** — correct values displayed, updates persist
- **Check edge cases** — empty lists, long text, missing data
- **Check console** — note any errors or warnings (use list_console_messages)

## Phase 4: Results Report

After all items tested:

```
## Verification Results

| # | Item | Status | Notes |
|---|------|--------|-------|
| DC1 | ... | ✅ | Works as expected |
| DC2 | ... | ❌ | Button doesn't respond to click |
| RA1 | ... | ⚠️ | Works but layout shifted slightly |

### Summary
✅ Passed: X/N
❌ Failed: Y/N
⚠️ Partial: Z/N

### Failures (need fixing):
1. DC2: [what's wrong and likely cause]

### Warnings (may need attention):
1. RA1: [what's off and whether it matters]
```

## Phase 5: Handle Failures

For any ❌ or ⚠️ items:
- Describe what went wrong clearly
- Suggest the likely cause (based on what you saw + the code changes)
- Ask if the user wants to fix now or defer

If fixing now, apply fixes and re-test those specific items.

## Rules

- ALWAYS build and present the checklist BEFORE testing. No ad-hoc wandering
- Test BOTH direct changes and related areas. Skipping regression checks defeats the purpose
- Take snapshots liberally. Visual state is the primary evidence
- If the dev server isn't running, check and start it before testing
- Don't test implementation details (internal state, console logs) unless relevant to a bug
- If a page requires auth or specific state, ask the user how to set that up
- Report failures factually. Don't apologize or hedge — state what's broken
