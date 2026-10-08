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
#   4. claims frontier issues (adds in-progress) and spawns one claude
#      worker window per issue, up to --max-workers
#
# The labels follow the mattpocock-skills triage vocabulary, so tickets filed
# by /to-tickets and /plan-to-issues feed the daemon alike. ready-for-agent
# means a ticket is specified well enough for an agent, blocked or not.
# Blocking lives only in GitHub's native issue dependencies. The frontier is
# computed every tick, never stored in a label: open, ready-for-agent, no open
# blocker, and not claimed.
#
# Workers label needs-help when they want a decision; the master polls it.
# An issue labelled ready-for-human is someone else's — a person's hands-on
# task, or the master's own — and no phase below claims or requeues it.
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

LABELS="ready-for-agent ready-for-human in-progress needs-help task epic"
ensure_labels() {
  local l
  for l in $LABELS; do
    if [ "$DRY" = 1 ]; then log "dry: gh label create $l"; else gh label create "$l" --force --color ededed >/dev/null 2>&1 || true; fi
  done
}

frontier() {
  gh issue list --label ready-for-agent --state open --limit 50 \
    --search "-is:blocked -label:in-progress -label:needs-help -label:ready-for-human sort:created-asc" \
    --json number --jq '.[].number'
}

# Search results lag label and state changes by a few seconds, so a claim
# re-reads the issue directly before taking it.
claimable() {
  gh issue view "$1" --json state,labels \
    --jq '.state == "OPEN" and (any(.labels[]; .name == "in-progress" or .name == "needs-help" or .name == "ready-for-human") | not)' \
    2>/dev/null | grep -qx true
}

issue_state() { gh issue view "$1" --json state --jq .state 2>/dev/null || echo MISSING; }

# ---- tmux helpers -----------------------------------------------------------

# Worker windows are named mw-<issue>-<slug of the issue title>, so the tmux
# status bar says what each one is doing. Only the number is load-bearing.
win_name() { tmux list-windows -F '#W' | grep -m1 "^mw-$1\(-\|\$\)" || true; }
win_exists() { [ -n "$(win_name "$1")" ]; }
worker_issues() { tmux list-windows -F '#W' | sed -n 's/^mw-\([0-9]*\).*/\1/p'; }

slug() { tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]\+/-/g; s/^-//; s/-$//' | cut -c1-30 | sed 's/-$//'; }

kill_win() {
  local issue=$1 name wt="$REPO/.worktree/$1"
  name=$(win_name "$issue")
  [ -n "$name" ] && run tmux kill-window -t "=$name"
  rm -f "$STATE/mw-$issue.start" "$STATE/mw-$issue.warned" "$STATE/retry-$issue"
  [ -d "$wt" ] && run git -C "$REPO" worktree remove --force "$wt"
  run git -C "$REPO" branch -D "task/$issue" >/dev/null 2>&1 || true
  return 0
}

spawn() {
  local issue=$1 title name
  title=$(gh issue view "$issue" --json title --jq .title 2>/dev/null | slug)
  name="mw-$issue${title:+-$title}"
  local cmd="env MAESTRO_ROLE=worker MAESTRO_ISSUE=$issue claude $CLAUDE_ARGS '/ak:maestro-worker $issue'"
  log "spawn $name: $cmd"
  if [ "$DRY" = 0 ]; then
    tmux new-window -d -n "$name" -c "$REPO" "$cmd"
    now >"$STATE/mw-$issue.start"
  fi
}

win_age() {
  local f="$STATE/mw-$1.start"
  [ -f "$f" ] || { echo 0; return; }
  echo $(( $(now) - $(cat "$f") ))
}

needs_help() {
  local issue=$1 why=$2
  log "needs-help #$issue: $why"
  run gh issue edit "$issue" --add-label needs-help --remove-label in-progress
  run gh issue comment "$issue" --body "maestro-daemon: needs help. $why"
}

# ---- tick phases ------------------------------------------------------------

reap_workers() {
  local issue state
  for issue in $(worker_issues); do
    state=$(issue_state "$issue")
    if [ "$state" != OPEN ]; then
      log "reap #$issue: issue $state"; kill_win "$issue"; continue
    fi
    warn_stale "$issue"
  done
}

# Warn once per window, and only when --stale is set. The window keeps running.
warn_stale() {
  local issue=$1
  [ "$STALE" -gt 0 ] || return 0
  [ -f "$STATE/mw-$issue.warned" ] && return 0
  [ "$(win_age "$issue")" -gt "$STALE" ] || return 0
  touch "$STATE/mw-$issue.warned"
  log "stale #$issue: worker has run longer than ${STALE}s; it is still running."
  run gh issue edit "$issue" --add-label needs-help
  run gh issue comment "$issue" --body "maestro-daemon: worker has run longer than ${STALE}s without closing the issue; it is still running."
}

# An in-progress issue with no window lost its worker. Give it one retry,
# then ask for help. One moved to ready-for-human was taken back on purpose.
requeue_orphans() {
  local issue retry
  for issue in $(gh issue list --label in-progress --state open --limit 50 --json number,labels \
    --jq '.[] | select(any(.labels[]; .name == "ready-for-human") | not) | .number'); do
    win_exists "$issue" && continue
    retry="$STATE/retry-$issue"
    if [ -f "$retry" ]; then
      needs_help "$issue" "worker disappeared twice without finishing."
      rm -f "$retry"
    else
      log "requeue #$issue: worker gone, retrying once"
      touch "$retry"
      run gh issue edit "$issue" --remove-label in-progress
    fi
  done
}

dispatch() {
  local running issue
  running=$(worker_issues | wc -l)
  for issue in $(frontier); do
    [ "$running" -lt "$MAX_WORKERS" ] || break
    win_exists "$issue" && continue
    claimable "$issue" || continue
    log "claim #$issue"
    run gh issue edit "$issue" --add-label in-progress
    spawn "$issue"
    running=$((running + 1))
  done
}

tick() {
  reap_workers
  requeue_orphans
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
