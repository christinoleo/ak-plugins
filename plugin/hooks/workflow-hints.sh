#!/usr/bin/env bash
# Workflow hints hook for Claude Code
# Injects next-step context based on tool/skill being used.
#
# Registered via hooks.json for PreToolUse matchers:
#   EnterPlanMode → injects /replan auto-run instruction
#   Skill         → injects next-step hint per skill
#
# Dependency-free: the three fields we need are plain string values, so they are
# pulled out with a bash regex rather than jq. This script used to call jq and
# died with exit 127 on any machine without it, which included the machine it
# was written on, so no hint ever fired. Keep it that way: core bash only.

set -euo pipefail

INPUT=$(cat)

# Extract the string value of a JSON key from $INPUT.
# Handles backslash escapes inside the value; good enough for the identifier-ish
# values in a hook payload (tool names, skill names). Returns empty if absent.
json_str() {
  local key="$1" re
  re="\"${key}\"[[:space:]]*:[[:space:]]*\"(([^\"\\]|\\.)*)\""
  if [[ $INPUT =~ $re ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  fi
}

HOOK_EVENT=$(json_str hook_event_name)
TOOL_NAME=$(json_str tool_name)

if [ "$HOOK_EVENT" != "PreToolUse" ]; then
  exit 0
fi

case "$TOOL_NAME" in
  EnterPlanMode)
    cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "WORKFLOW INSTRUCTION: When you finish writing your plan and are ready to call ExitPlanMode, you MUST first run the /replan coverage audit. This means: (1) Write your plan as normal, (2) Before calling ExitPlanMode, execute the /replan skill to score every requirement as Covered/Partial/Missing, (3) Fix any gaps found, (4) THEN call ExitPlanMode with the improved plan. Do NOT skip this step."
  }
}
JSON
    ;;
  Skill)
    # .tool_input.skill, the only "skill" key a Skill payload carries.
    SKILL_NAME=$(json_str skill)
    case "$SKILL_NAME" in
      linus)
        cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "WORKFLOW HINT: After this code review is complete, suggest running /triage to walk through findings point-by-point with the user before making any fixes."
  }
}
JSON
        ;;
      triage)
        cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "WORKFLOW HINT: After triage decisions are made and fixes applied, suggest running /verify to do browser-based testing of the changes and related areas."
  }
}
JSON
        ;;
      replan)
        cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "additionalContext": "WORKFLOW HINT: If this replan ran in plan mode, then once the audit is approved and ExitPlanMode is called, suggest running /plan-to-issues to convert the plan into a trackable GitHub issue epic with tasks. If it ran in delivered mode, there is no plan to convert, so suggest /verify instead once the delta is applied."
  }
}
JSON
        ;;
      *)
        # No hint for other skills
        exit 0
        ;;
    esac
    ;;
  *)
    # No hint for other tools
    exit 0
    ;;
esac
