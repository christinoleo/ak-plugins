---
name: ak-help
description: |
  List every skill and command available here — installed from this marketplace or built into
  Claude Code — then say which ones apply to what is happening right now. Pass a task
  description to route that instead of the current conversation. Named ak-help because /help is
  Claude Code's own command.
---

# ak-help: what is installed, and what applies here

Answer two questions in one pass. What is available, and what should be used right now. The
second is the point; a bare inventory is something the user could get from `claude plugin list`.

## Step 1: enumerate what is actually installed

For plugin and local skills, do not answer from memory or from the skill list in your context.
That list is filtered and can lag behind what is on disk. Read the filesystem.

```bash
for root in ~/.claude/plugins/cache/*/*/*/ ~/.claude/skills/ .claude/skills/; do
  [ -d "$root" ] || continue
  find "$root" -name SKILL.md 2>/dev/null | while read -r f; do
    src=$(printf '%s' "$f" | sed -n 's|.*/cache/[^/]*/\([^/]*\)/[^/]*/.*|\1|p')
    [ -z "$src" ] && src=local
    name=$(sed -n 's/^name:[[:space:]]*//p' "$f" | head -1)
    desc=$(sed -n 's/^description:[[:space:]]*//p' "$f" | head -1 | cut -c1-120)
    printf '%s\t%s\t%s\n' "$src" "${name:-$(basename "$(dirname "$f")")}" "$desc"
  done
done | sort -u
```

Commands live beside the skills, so collect those too:

```bash
for d in ~/.claude/plugins/cache/*/*/*/commands/; do
  [ -d "$d" ] || continue
  src=$(printf '%s' "$d" | sed -n 's|.*/cache/[^/]*/\([^/]*\)/[^/]*/.*|\1|p')
  for f in "$d"*.md; do
    [ -f "$f" ] || continue
    printf '%s\t/%s\n' "$src" "$(basename "$f" .md)"
  done
done | sort -u
```

Claude Code also ships built-in skills inside the CLI itself (for example `/loop`, `/schedule`,
`/code-review`, `/simplify`, `/security-review`). Those never appear on disk under the plugin
cache, so the filesystem sweep cannot find them. For these, and only these, use the
available-skills list in your context: collect every skill that did not come from a plugin or a
local skills directory and label its source `builtin`. Note in the output that built-ins vary
with the installed CLI version, so another machine may have a different set.

Two things worth checking, because both change the answer:

- A plugin in the marketplace that is not installed here has no skills to recommend. If the user
  seems to expect one, say it is not installed and give them the `claude plugin install` line.
- The installed version can trail the repo you are sitting in. If the working directory is the
  marketplace source and `plugin/skills/` holds skills the cache does not, say so. Recommending a
  skill the user cannot invoke yet wastes their time.

## Step 2: work out what the user is actually doing

With `$ARGUMENTS`, route that task. Without it, read the conversation and name the current task in
one sentence before recommending anything. Getting this wrong makes every recommendation wrong, so
state it and let the user correct you.

Look for the concrete shape of the work, not its topic. "Working on auth" routes nowhere. "About
to restructure how auth state is stored, across about fifteen call sites" routes to a design skill,
a blast-radius check, and a principle about migrating callers.

## Step 3: recommend

At most five, ranked, most applicable first. Fewer is better than padding.

```
## Current task
[One sentence. What the user is doing right now.]

## Applies here

| Skill | Source | Why now | What it does to your work |
|-------|--------|---------|---------------------------|
| `/x` | ak | [the specific trigger you saw, not a paraphrase of the description] | [what changes if they run it] |

## Also installed, not for this
[One line per near-miss that the user might have expected to see, with why it does not fit.
Skip this section when there are no near misses.]
```

Rules for the recommendations:

- Point at the trigger you actually observed. "You are about to write a migration across many
  files" beats "this skill is for migrations."
- Say what running it changes. A skill that would tell them something they already decided is not
  a recommendation.
- Rank on fit, not on which plugin owns it. A `mattpocock-skills` skill that fits better than an
  `ak` one goes first.
- Never invent a name. Every skill you name must have come out of Step 1's output.
- Principle skills are reference material, not actions. Group them into one row rather than
  listing six.

## When nothing fits

Say so in one line and stop. "Nothing installed fits this; it is a plain edit" is a useful answer
and the most common correct one for small work. Do not reach for the nearest-sounding skill to
avoid an empty table.

If the gap looks real and recurring, that is worth one line too, pointing at
`/automate-me` or `writing-for-agents` for capturing it as a new skill.

## Notes

- `mattpocock-skills` ships `ask-matt`, which routes over that plugin's skills only. This command
  covers every installed plugin, so prefer it when the user does not know which plugin owns what.
- Read `plugin/skills/ATTRIBUTION.md` when the user asks where a vendored skill came from or why a
  related one is missing.
