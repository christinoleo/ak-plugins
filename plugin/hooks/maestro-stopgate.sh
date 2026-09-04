#!/usr/bin/env bash
# Maestro stop gate hook for Claude Code.
#
# Registered via hooks.json for Stop. Fires in every session but does nothing
# unless the maestro daemon started the session with MAESTRO_ROLE set, so
# ordinary sessions never notice it.
#
# A worker may stop once its PR is ready (not a draft) or its issue carries
# needs-help. An integrator may stop once its PR is merged, closed, a draft,
# labelled needs-help, or stripped of needs-browser and needs-migration. Until
# then the hook blocks the stop with a reason, which puts the agent back to
# work. After MAX_BLOCKS blocks in a row it labels needs-help itself and lets
# the session end, so a confused agent cannot loop forever.
#
# Dependency-free on purpose: the payload fields are read with a bash regex,
# not jq, which is missing on some machines this plugin lands on.

set -euo pipefail

ROLE=${MAESTRO_ROLE:-}
[ -n "$ROLE" ] || exit 0

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

block() {
  local key=$1 reason=$2 n
  n=$(( $(cat "$STATE/stopgate-$key" 2>/dev/null || echo 0) + 1 ))
  echo "$n" >"$STATE/stopgate-$key"
  if [ "$n" -gt "$MAX_BLOCKS" ]; then
    rm -f "$STATE/stopgate-$key"
    return 1
  fi
  printf '{"decision":"block","reason":"maestro stop gate (%s/%s): %s"}\n' "$n" "$MAX_BLOCKS" "$reason"
  exit 0
}

allow() { rm -f "$STATE/stopgate-$1"; exit 0; }

has_label() { grep -x "$2" <<<"$1" >/dev/null; }

case "$ROLE" in
  worker)
    ISSUE=${MAESTRO_ISSUE:-}
    [ -n "$ISSUE" ] || exit 0
    labels=$(gh issue view "$ISSUE" --json labels --jq '.labels[].name' 2>/dev/null || true)
    has_label "$labels" needs-help && allow "$ISSUE"
    ready=$(gh pr list --head "task/$ISSUE" --state open --json isDraft --jq '.[] | select(.isDraft | not) | 1' 2>/dev/null || true)
    [ -n "$ready" ] && allow "$ISSUE"
    block "$ISSUE" "issue #$ISSUE has no ready PR yet. Finish the handoff: push, open or update the PR, add needs-browser or needs-migration if they apply, remove the worktree, then gh pr ready. If you are blocked, label the issue needs-help with a comment saying why." ||
      { gh issue edit "$ISSUE" --add-label needs-help >/dev/null 2>&1 || true
        gh issue comment "$ISSUE" --body "maestro stop gate: worker stopped $MAX_BLOCKS times without a ready PR." >/dev/null 2>&1 || true
        exit 0; }
    ;;
  integrator)
    PR=${MAESTRO_PR:-}
    [ -n "$PR" ] || exit 0
    info=$(gh pr view "$PR" --json state,isDraft,labels --jq '"\(.state) \(.isDraft)\n\(.labels[].name)"' 2>/dev/null || echo "MISSING false")
    state=${info%% *}; rest=${info#* }; draft=${rest%%$'\n'*}; labels=${rest#*$'\n'}
    [ "$state" = OPEN ] || allow "pr-$PR"
    [ "$draft" = true ] && allow "pr-$PR"
    has_label "$labels" needs-help && allow "pr-$PR"
    if ! has_label "$labels" needs-browser && ! has_label "$labels" needs-migration; then allow "pr-$PR"; fi
    block "pr-$PR" "PR #$PR still carries needs-browser or needs-migration. Either finish the checks and remove those labels so the daemon merges, or send it back: comment, gh pr ready --undo, and put the issue back to ready." ||
      { gh pr edit "$PR" --add-label needs-help >/dev/null 2>&1 || true
        gh pr comment "$PR" --body "maestro stop gate: integrator stopped $MAX_BLOCKS times without finishing." >/dev/null 2>&1 || true
        exit 0; }
    ;;
esac
exit 0
