---
name: caveman-off
description: |
  Turn off the always-on caveman register permanently, across every future session.
  Use when you want normal prose back for a while — writing docs, pairing with someone
  else, or any stretch where terse replies get in the way.
---

Run this, exactly as written:

```bash
echo off > ~/.claude/ak-caveman.state
```

Then:

1. Drop the caveman register immediately. Reply in normal prose for the rest of this session.
2. Confirm to the user in one short line that caveman is off for this session **and** every future one.
3. Tell them `/caveman-on` restores the default.

Do not edit the skill file, the hook, or `hooks.json` — the state file is the whole switch.
