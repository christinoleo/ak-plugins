#!/usr/bin/env bash
# Maestro daemon: deterministic dispatch loop for the maestro skill.
#
# Runs inside the master's tmux session. Every tick it:
#   1. reaps worker windows whose issue is closed. That is the worker's own
#      "done" signal: it merges its PR itself, and the merge closes the issue.
#      Nothing else closes a window: a needs-help session stays open so a
#      human can look at it.
#   2. optionally warns (label + comment, never a kill) when a worker has run
#      past --stale; off by default
#   3. requeues in-progress issues whose worker window vanished, once
#   4. marks issues whose "Blocked by #N" lines are all closed as ready
#   5. claims ready issues (ready -> in-progress) and spawns one claude
#      worker window per issue, up to --max-workers
#
# All state lives in GitHub labels; nothing is messaged to Claude sessions.
# Workers label needs-help when they want a decision; the master polls it.
#
# Spawned sessions get MAESTRO_ROLE=worker and MAESTRO_ISSUE in their
# environment; hooks/maestro-stopgate.sh reads them to gate Stop.
#
# Dependencies: bash 4, git, gh (its built-in --jq, no jq needed), tmux, flock.

set -euo pipefail

MAX_WORKERS=2
INTERVAL=30
STALE=0
REPO=""
ONCE=0
DRY=0
CLAUDE_ARGS="--model opus --dangerously-skip-permissions"

usage() {
  cat <<USAGE
usage: maestro-daemon.sh [options]

  --max-workers N      concurrent worker windows (default $MAX_WORKERS)
  --interval SECONDS   poll interval (default $INTERVAL)
  --stale SECONDS      warn with needs-help when a worker runs longer than this;
                       never kills it or touches its worktree (default off)
  --repo DIR           repo root (default: git toplevel of cwd)
  --claude-args "..."  flags for every spawned claude (default "$CLAUDE_ARGS")
  --once               run one tick and exit
  --dry-run            print actions without labelling or spawning
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --max-workers) MAX_WORKERS=$2; shift 2 ;;
    --interval) INTERVAL=$2; shift 2 ;;
    --stale) STALE=$2; shift 2 ;;
    --repo) REPO=$2; shift 2 ;;
    --claude-args) CLAUDE_ARGS=$2; shift 2 ;;
    --once) ONCE=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "${TMUX:-}" ] || { echo "run this inside the master's tmux session" >&2; exit 2; }
REPO=${REPO:-$(git rev-parse --show-toplevel)}
STATE="$REPO/.worktree/.maestro"
mkdir -p "$STATE"
LOG="$STATE/daemon.log"

exec 9>"$STATE/lock"
flock -n 9 || { echo "another daemon holds $STATE/lock" >&2; exit 1; }

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG"; }
run() { if [ "$DRY" = 1 ]; then log "dry: $*"; else "$@"; fi; }
now() { date +%s; }

# ---- GitHub helpers ---------------------------------------------------------

LABELS="ready in-progress needs-help task epic"
ensure_labels() {
  local l
  for l in $LABELS; do
    if [ "$DRY" = 1 ]; then log "dry: gh label create $l"; else gh label create "$l" --force --color ededed >/dev/null 2>&1 || true; fi
  done
}

ready_issues() {
  gh issue list --label ready --state open --search "sort:created-asc" --limit 50 \
    --json number,labels \
    --jq '.[] | select(any(.labels[]; .name == "in-progress" or .name == "needs-help") | not) | .number'
}

issue_state() { gh issue view "$1" --json state --jq .state 2>/dev/null || echo MISSING; }

# ---- tmux helpers -----------------------------------------------------------

win_exists() { tmux list-windows -F '#W' | grep -x "$1" >/dev/null; }
worker_windows() { tmux list-windows -F '#W' | grep '^mw-' || true; }

kill_win() {
  local name=$1 issue=${1#mw-} wt="$REPO/.worktree/${1#mw-}"
  win_exists "$name" && run tmux kill-window -t "=$name"
  rm -f "$STATE/$name.start" "$STATE/$name.warned" "$STATE/retry-$issue"
  [ -d "$wt" ] && run git -C "$REPO" worktree remove --force "$wt"
  run git -C "$REPO" branch -D "task/$issue" >/dev/null 2>&1 || true
  return 0
}

spawn() {
  local issue=$1 name="mw-$1"
  local cmd="env MAESTRO_ROLE=worker MAESTRO_ISSUE=$issue claude $CLAUDE_ARGS '/ak:maestro-worker $issue'"
  log "spawn $name: $cmd"
  if [ "$DRY" = 0 ]; then
    tmux new-window -d -n "$name" -c "$REPO" "$cmd"
    now >"$STATE/$name.start"
  fi
}

win_age() {
  local f="$STATE/$1.start"
  [ -f "$f" ] || { echo 0; return; }
  echo $(( $(now) - $(cat "$f") ))
}

needs_help() {
  local issue=$1 why=$2
  log "needs-help #$issue: $why"
  run gh issue edit "$issue" --add-label needs-help --remove-label in-progress --remove-label ready
  run gh issue comment "$issue" --body "maestro-daemon: needs help. $why"
}

# ---- tick phases ------------------------------------------------------------

reap_workers() {
  local w issue state
  for w in $(worker_windows); do
    issue=${w#mw-}
    state=$(issue_state "$issue")
    if [ "$state" != OPEN ]; then
      log "reap $w: issue $state"; kill_win "$w"; continue
    fi
    warn_stale "$w" "$issue"
  done
}

# Warn once per window, and only when --stale is set. The window keeps running.
warn_stale() {
  local w=$1 issue=$2
  [ "$STALE" -gt 0 ] || return 0
  [ -f "$STATE/$w.warned" ] && return 0
  [ "$(win_age "$w")" -gt "$STALE" ] || return 0
  touch "$STATE/$w.warned"
  log "stale #$issue: worker has run longer than ${STALE}s; it is still running."
  run gh issue edit "$issue" --add-label needs-help
  run gh issue comment "$issue" --body "maestro-daemon: worker has run longer than ${STALE}s without closing the issue; it is still running."
}

# An in-progress issue with no window lost its worker. Give it one retry,
# then ask for help.
requeue_orphans() {
  local issue retry
  for issue in $(gh issue list --label in-progress --state open --limit 50 --json number --jq '.[].number'); do
    win_exists "mw-$issue" && continue
    retry="$STATE/retry-$issue"
    if [ -f "$retry" ]; then
      needs_help "$issue" "worker disappeared twice without finishing."
      rm -f "$retry"
    else
      log "requeue #$issue: worker gone, retrying once"
      touch "$retry"
      run gh issue edit "$issue" --add-label ready --remove-label in-progress
    fi
  done
}

# Issues that say "Blocked by #N" and carry no maestro label become ready once
# every blocker is closed.
unblock_dependents() {
  local num body blockers b all_closed
  gh issue list --state open --limit 100 --search "\"Blocked by\" in:body" \
    --json number,body,labels \
    --jq '.[] | select(any(.labels[]; .name == "ready" or .name == "in-progress" or .name == "needs-help") | not) | "\(.number)\t\(.body | gsub("\n"; " "))"' |
  while IFS=$'\t' read -r num body; do
    blockers=$(grep -oiE 'blocked by[^.]*' <<<"$body" | grep -oE '#[0-9]+' | tr -d '#' | sort -u)
    [ -n "$blockers" ] || continue
    all_closed=1
    for b in $blockers; do
      [ "$(issue_state "$b")" = CLOSED ] || { all_closed=0; break; }
    done
    if [ "$all_closed" = 1 ]; then
      log "unblock #$num: blockers all closed"
      run gh issue edit "$num" --add-label ready
    fi
  done
}

dispatch() {
  local running issue
  running=$(worker_windows | wc -l)
  for issue in $(ready_issues); do
    [ "$running" -lt "$MAX_WORKERS" ] || break
    log "claim #$issue"
    run gh issue edit "$issue" --add-label in-progress --remove-label ready
    spawn "$issue"
    running=$((running + 1))
  done
}

tick() {
  reap_workers
  requeue_orphans
  unblock_dependents
  dispatch
}

# ---- main -------------------------------------------------------------------

cd "$REPO"
ensure_labels
log "start: max-workers=$MAX_WORKERS interval=${INTERVAL}s repo=$REPO dry=$DRY"
while :; do
  tick || log "tick failed: $?"
  [ "$ONCE" = 1 ] && break
  sleep "$INTERVAL"
done
