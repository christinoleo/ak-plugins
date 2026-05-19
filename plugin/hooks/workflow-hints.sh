#!/usr/bin/env bash
# Workflow hints hook for Claude Code
# Injects next-step context based on tool/skill being used.
#
# Registered via hooks.json for PreToolUse matchers:
#   EnterPlanMode → injects /replan auto-run instruction
#   Skill         → injects next-step hint per skill

set -euo pipefail

INPUT=$(cat)

HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')

if [ "$HOOK_EVENT" != "PreToolUse" ]; then
  exit 0
fi

case "$TOOL_NAME" in
  EnterPlanMode)
    cat <<'JSON'
{
  "hookSpecificOutput": {
    "additionalContext": "WORKFLOW INSTRUCTION: When you finish writing your plan and are ready to call ExitPlanMode, you MUST first run the /replan coverage audit. This means: (1) Write your plan as normal, (2) Before calling ExitPlanMode, execute the /replan skill to score every requirement as Covered/Partial/Missing, (3) Fix any gaps found, (4) THEN call ExitPlanMode with the improved plan. Do NOT skip this step."
  }
}
JSON
    ;;
  Skill)
    SKILL_NAME=$(echo "$INPUT" | jq -r '.tool_input.skill // empty')
    case "$SKILL_NAME" in
      linus)
        cat <<'JSON'
{
  "hookSpecificOutput": {
    "additionalContext": "WORKFLOW HINT: After this code review is complete, suggest running /triage to walk through findings point-by-point with the user before making any fixes."
  }
}
JSON
        ;;
      triage)
        cat <<'JSON'
{
  "hookSpecificOutput": {
    "additionalContext": "WORKFLOW HINT: After triage decisions are made and fixes applied, suggest running /verify to do browser-based testing of the changes and related areas."
  }
}
JSON
        ;;
      replan)
        cat <<'JSON'
{
  "hookSpecificOutput": {
    "additionalContext": "WORKFLOW HINT: After the replan audit is approved and ExitPlanMode is called, suggest running /plan-to-issues to convert the plan into a trackable GitHub issue epic with tasks."
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
