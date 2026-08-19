---
name: caveman-on
description: |
  Restore the default, where the caveman register switches itself on at the start of every
  session. Undoes /caveman-off.
---

Run this, exactly as written:

```bash
rm -f ~/.claude/ak-caveman.state
```

Then:

1. Adopt the caveman register for the rest of this session, following the rules in the `caveman` skill, including its scope section, which keeps the register out of files, commits, issue bodies and anything published.
2. Confirm in one short line that caveman is back on, and that it will switch itself on automatically from the next session too.

Do not edit the skill file, the hook, or `hooks.json`. The state file is the whole switch.
