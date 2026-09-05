#!/usr/bin/env bash
# Maestro stop gate hook for Claude Code.
#
# Registered via hooks.json for Stop. Fires in every session but does nothing
# unless the maestro daemon started the session with MAESTRO_ROLE=worker, so
# ordinary sessions never notice it.
#
# A worker may stop once its issue is closed (its own merge closed it) or
# carries needs-help. Until then the hook blocks the stop with a reason, which
# puts the agent back to work. After MAX_BLOCKS blocks in a row it labels
# needs-help itself and lets the session end, so a confused agent cannot loop
# forever.
#
# Dependency-free on purpose: the payload fields are read with a bash regex,
# not jq, which is missing on some machines this plugin lands on.

set -euo pipefail

[ "${MAESTRO_ROLE:-}" = worker ] || exit 0
ISSUE=${MAESTRO_ISSUE:-}
[ -n "$ISSUE" ] || exit 0

MAX_BLOCKS=3
INPUT=$(cat)

json_str() {
  local key="$1" re
  re="\"${key}\"[[:space:]]*:[[:space:]]*\"(([^\"\\]|\\.)*)\""
  if [[ $INPUT =~ $re ]]; then printf '%s' "${BASH_REMATCH[1]}"; fi
}

[ "$(json_str hook_event_name)" = Stop ] || exit 0

REPO=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
STATE="$REPO/.worktree/.maestro"
mkdir -p "$STATE"
COUNT="$STATE/stopgate-$ISSUE"

info=$(gh issue view "$ISSUE" --json state,labels --jq '"\(.state)\n\(.labels[].name)"' 2>/dev/null || echo MISSING)
state=${info%%$'\n'*}
labels=${info#*$'\n'}

if [ "$state" != OPEN ] || grep -x needs-help <<<"$labels" >/dev/null; then
  rm -f "$COUNT"
  exit 0
fi

n=$(( $(cat "$COUNT" 2>/dev/null || echo 0) + 1 ))
echo "$n" >"$COUNT"
if [ "$n" -gt "$MAX_BLOCKS" ]; then
  rm -f "$COUNT"
  gh issue edit "$ISSUE" --add-label needs-help >/dev/null 2>&1 || true
  gh issue comment "$ISSUE" --body "maestro stop gate: worker stopped $MAX_BLOCKS times without closing the issue." >/dev/null 2>&1 || true
  exit 0
fi

printf '{"decision":"block","reason":"maestro stop gate (%s/%s): issue #%s is still open. Finish it: verify, push, open the PR, rebase on main, and merge with gh pr merge --squash --delete-branch. If it needs a decision (migration, unsafe rebase, blocked), label the issue needs-help with a comment saying why."}\n' "$n" "$MAX_BLOCKS" "$ISSUE"
