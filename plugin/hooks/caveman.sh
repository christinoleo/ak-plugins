#!/usr/bin/env bash
# Caveman auto-activation hook for Claude Code.
#
# Registered via hooks.json for SessionStart. Injects the caveman register at
# the top of every session, so the mode is on by default instead of waiting for
# the human to type /caveman.
#
# The rules are NOT duplicated here. This script reads them out of
# skills/caveman/SKILL.md — the skill file stays the single source of truth, so
# editing the skill changes the always-on behaviour too.
#
# Off switch, in order of blast radius:
#   - "stop caveman" / "normal mode" in chat  -> off for the rest of this session
#   - /caveman-off                            -> off in every future session
#   - /caveman-on                             -> back to the default (on)
#
# The persistent switch is the presence of STATE_FILE containing "off".
#
# Deliberately dependency-free: SessionStart takes plain stdout as context, so
# there is no JSON to build and no jq to call. jq is not installed on every
# machine this plugin lands on — see workflow-hints.sh, which needs it.

set -euo pipefail

STATE_FILE="${HOME}/.claude/ak-caveman.state"
SKILL_FILE="${CLAUDE_PLUGIN_ROOT:-}/skills/caveman/SKILL.md"

# Persistently disabled — inject nothing.
if [ -f "$STATE_FILE" ] && [ "$(tr -d '[:space:]' <"$STATE_FILE")" = "off" ]; then
  exit 0
fi

# No skill file means nothing to assert. Stay silent rather than guess at rules.
if [ ! -f "$SKILL_FILE" ]; then
  exit 0
fi

# Strip the YAML frontmatter; the body is the register itself.
BODY=$(awk 'BEGIN{n=0} /^---[[:space:]]*$/{n++; next} n>=2{print}' "$SKILL_FILE")

if [ -z "${BODY//[[:space:]]/}" ]; then
  exit 0
fi

cat <<PREAMBLE
CAVEMAN MODE IS ACTIVE FOR THIS SESSION. It was switched on automatically, not by the user typing /caveman. Follow the register below from your first reply onward.

Read the scope section carefully: it governs chat only, and must never touch files, commits, issue bodies, or anything published.

If the user says "stop caveman" or "normal mode", drop the register for the rest of this session and tell them /caveman-off makes that permanent.

$BODY
PREAMBLE
