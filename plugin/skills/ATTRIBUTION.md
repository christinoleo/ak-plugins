# Third-party skill attribution

Most skills in this directory, and the one agent in `plugin/agents/`, are vendored from
**pstack**, a Cursor plugin by Lauren Tan, published at
<https://github.com/cursor/plugins/tree/main/pstack> and licensed under the MIT License. The
full license text is kept alongside this file as `LICENSE.pstack`.

## What was taken

Twenty `principle-*` skills, plus `architect`, `arena`, `automate-me`, `blast-radius`, `bro`,
`create-verification-skill`, `explain-work`, `figure-it-out`, `how`, `interrogate`,
`maintain-verification-skill`, `no-comments`, `recall`, `reflect`, `show-me-your-work`, `swarm`,
`technical-writing`, `typescript-best-practices`, `unslop`, and `why`. The `comment-sicko` agent
came across too, since `no-comments` spawns it.

## What was left behind

- `poteto-mode` and its 40-odd playbooks. The largest thing upstream ships and the one with the
  most to port: it depends on the separate `cursor-team-kit` plugin for `deslop`, `control-ui`,
  and `control-cli`, routes every subagent through a `poteto-agent` wrapper, and its Autonomy
  section grants blanket approval for external actions ("use any MCP tool", team chat and ticket
  updates proceed without asking). That last part is a policy decision rather than a porting
  problem, and it was made deliberately: this plugin does not ship a blanket grant over external
  systems. The parts of poteto-mode worth having are its principles index and its playbook
  routing, and the twenty `principle-*` skills carry the first of those on their own.
- `setup-pstack`. Its entire job is writing a global always-applied rule that pins each role to a
  model slug. Every slug it knows about belongs to a different vendor's catalog, and the skills
  that read it have been ported to Claude Code model tiers, so there is nothing left for it to
  configure.
- `principle-never-block-on-the-human`. It instructs the agent to act first and explain
  afterwards, which conflicts with ordinary change-control expectations.
- `tdd`. The `mattpocock-skills` plugin ships a fuller one under the same name.
- The `benny` automations. A Slack-to-pull-request pipeline that needs its own security review
  before anyone points it at a real workspace.
- `poteto-mode/scripts/`. Installs npm dependencies at run time and drives force-push and
  worktree-deletion flows. The one script that did come across is
  `show-me-your-work/scripts/log.sh`, reviewed separately below.

## Local modifications

Everything vendored got the same two ports where it needed them. Third-party model slugs
(`grok-*`, `gpt-*`) became Claude Code model tiers, and Cursor paths (`.cursor/skills/`,
`~/.cursor/rules/`, `~/.cursor/projects/<slug>/agent-transcripts/`) became their `.claude/`
equivalents. Where a skill got reviewer or candidate diversity by mixing model vendors, that
diversity now comes from an assigned lens or a distinct starting constraint, because one vendor
is all this plugin has. Beyond that:

- `how` and `interrogate` moved from Cursor's subagent API to Claude Code's. Reviewer and critic
  independence now comes from assigned lenses.
- `architect` had its Phase B rewritten. It ran through `arena` with an uncapped runner list;
  it now spawns three runners directly, each with a different starting constraint and its own
  output path. Its Phase A called `why` to recover the rationale behind an existing shape; it now
  names concrete sources (git history, the PRs that introduced the files, ADRs) and says to flag
  what it cannot find rather than assume it away.
- `arena` and `swarm` were capped. Upstream took N from the user with no ceiling and no cost
  disclosure. `arena` defaults to three runners, `swarm` caps at twelve workers, and both have to
  state N and the reason when they go higher. `swarm` also lost `environment: "cloud"`, which has
  no Claude Code equivalent, so its workers run locally.
- `automate-me` was ported off Cursor's built-in `create-skill`, which has no Claude Code
  equivalent. Authoring routes to `writing-for-agents` in the `mattpocock-skills` plugin.
  `AskQuestion` became `AskUserQuestion` (`allow_multiple` became `multiSelect`, four options
  rather than six), and the worked example changed from `poteto-mode` to this plugin's `caveman`.
- `reflect` was ported the same way, including its skill-detection paths, and its substantive-edit
  branch now hands off to `writing-for-agents` instead of `create-skill`.
- `why` gained an untrusted-input guard. Its investigators fan out across Slack, Linear, Notion,
  Sentry, Datadog, and Databricks, and upstream's investigator prompt had no instruction to treat
  what comes back as data. The reviewer prompts in `reflect` already carried that guard; `why` now
  matches them.
- `figure-it-out` lost its citation of `principle-never-block-on-the-human` and its instruction to
  read poteto-mode's principles index, which point at things not vendored here.
- `teach` was renamed `explain-work`. Its job is explaining a body of work in this codebase, which
  is a different job from the `teach` in `mattpocock-skills`, and two skills cannot share a name.
- `comment-sicko`'s agent name was lowercased to `comment-sicko` so `subagent_type` resolves.
- `show-me-your-work`'s transcript audit moved to `~/.claude/projects/<project-slug>/`, and its
  mandatory cross-model review became a reviewer with an assigned skeptic's lens.

## The one vendored script

`show-me-your-work/scripts/log.sh` was reviewed line by line and exercised against crafted input.
It runs no commands, reaches no network, and passes every value through `printf '%s'` rather than
interpolating it, so shell metacharacters, format specifiers, and embedded newlines are all stored
as literal text. Tabs and newlines collapse to spaces, which is what stops a crafted cell from
forging an extra row in an append-only log.

One hole was found and fixed. Upstream prefixes any cell starting with `=`, `+`, `-`, or `@` with
an apostrophe so a reviewer opening the log in a spreadsheet cannot trigger formula execution.
That check ran against the raw cell, so a value with a leading space (`" =1+1"`) slipped through
while a spreadsheet still parsed it as a formula. The check now ignores leading blanks.

Any further script coming across from upstream gets the same treatment before it lands.
- `create-verification-skill` and `maintain-verification-skill` had their em dashes removed, the
  one rule from `unslop` that upstream does not apply to itself everywhere. No wording beyond the
  punctuation changed.
