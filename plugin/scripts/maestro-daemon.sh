#!/usr/bin/env bash
# Maestro daemon: deterministic dispatch and merge loop for the maestro skill.
#
# Runs inside the master's tmux session. Every tick it:
#   1. reaps worker windows whose PR is open or whose issue is closed or stuck
#   2. flags workers that ran past --stale as needs-help
#   3. claims ready issues (ready -> in-progress) and spawns one claude
#      worker window per issue, up to --max-workers
#   4. merges task PRs that need no human-shaped check, and spawns one
#      integrator window at a time for PRs labelled needs-browser or
#      needs-migration (the integrator works in the root checkout; workers
#      use worktrees under .worktree/)
#   5. after a merge, marks issues whose "Blocked by #N" lines are all
#      closed as ready
#
# Anything it cannot resolve gets the needs-help label and a comment. All state
# lives in GitHub labels; nothing is messaged to Claude sessions. The master
# polls needs-help on its own.
#
# Dependencies: bash 4, git, gh (its built-in --jq, no jq needed), tmux, flock.

set -euo pipefail

MAX_WORKERS=2
INTERVAL=30
STALE=7200
REPO=""
ONCE=0
DRY=0
CLAUDE_ARGS="--model opus --dangerously-skip-permissions"

usage() {
  cat <<USAGE
usage: maestro-daemon.sh [options]

  --max-workers N      concurrent worker windows (default $MAX_WORKERS)
  --interval SECONDS   poll interval (default $INTERVAL)
  --stale SECONDS      kill a worker running longer than this (default $STALE)
  --repo DIR           repo root (default: git toplevel of cwd)
  --claude-args "..."  flags for every spawned claude (default "$CLAUDE_ARGS")
  --once               run one tick and exit
  --dry-run            print actions without labelling, merging, or spawning
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

LABELS="ready in-progress needs-browser needs-migration needs-help task epic"
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
issue_has_label() { gh issue view "$1" --json labels --jq ".labels[].name" 2>/dev/null | grep -x "$2" >/dev/null; }

# open PRs from task/* branches: "<pr> <issue> <draft> <labels,comma>"
task_prs() {
  gh pr list --state open --limit 100 --json number,headRefName,isDraft,labels \
    --jq '.[] | select(.headRefName | startswith("task/")) |
          "\(.number) \(.headRefName | ltrimstr("task/")) \(.isDraft) \([.labels[].name] | join(","))"'
}

pr_for_issue() {
  gh pr list --state all --head "task/$1" --limit 1 --json number --jq '.[0].number // empty'
}

# ---- tmux helpers -----------------------------------------------------------

win_exists() { tmux list-windows -F '#W' | grep -x "$1" >/dev/null; }
windows_with_prefix() { tmux list-windows -F '#W' | grep "^$1" || true; }
kill_win() {
  local name=$1 wt
  win_exists "$name" && run tmux kill-window -t "=$name"
  rm -f "$STATE/$name.start"
  case "$name" in
    mw-*) wt="$REPO/.worktree/${name#mw-}"
          [ -d "$wt" ] && run git -C "$REPO" worktree remove --force "$wt" ;;
    mi-*) # the integrator works in the root checkout; leave it on main
          run git -C "$REPO" checkout -q main || true ;;
  esac
  return 0
}

spawn() {
  local name=$1 skill=$2 arg=$3
  local cmd="claude $CLAUDE_ARGS '/ak:$skill $arg'"
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
  local kind=$1 num=$2 why=$3
  log "needs-help $kind #$num: $why"
  if [ "$kind" = issue ]; then
    run gh issue edit "$num" --add-label needs-help --remove-label in-progress --remove-label ready
    run gh issue comment "$num" --body "maestro-daemon: needs help. $why"
  else
    run gh pr edit "$num" --add-label needs-help
    run gh pr comment "$num" --body "maestro-daemon: needs help. $why"
  fi
}

# ---- tick phases ------------------------------------------------------------

reap_workers() {
  local w issue pr state
  for w in $(windows_with_prefix mw-); do
    issue=${w#mw-}
    state=$(issue_state "$issue")
    pr=$(pr_for_issue "$issue")
    if [ "$state" != OPEN ]; then
      log "reap $w: issue $state"; kill_win "$w"; continue
    fi
    if issue_has_label "$issue" needs-help; then
      log "reap $w: issue needs-help"; kill_win "$w"; continue
    fi
    if [ -n "$pr" ] && [ "$(gh pr view "$pr" --json isDraft --jq .isDraft)" = false ]; then
      log "reap $w: PR #$pr open"; kill_win "$w"; continue
    fi
    if [ "$(win_age "$w")" -gt "$STALE" ]; then
      needs_help issue "$issue" "worker ran longer than ${STALE}s without opening a PR."
      kill_win "$w"
    fi
  done
}

reap_integrators() {
  local w pr state draft
  for w in $(windows_with_prefix mi-); do
    pr=${w#mi-}
    state=$(gh pr view "$pr" --json state,isDraft --jq '"\(.state) \(.isDraft)"' 2>/dev/null || echo "MISSING false")
    draft=${state#* }; state=${state% *}
    if [ "$state" != OPEN ] || [ "$draft" = true ]; then
      log "reap $w: PR $state draft=$draft"; kill_win "$w"; continue
    fi
    if gh pr view "$pr" --json labels --jq '.labels[].name' | grep -x needs-help >/dev/null; then
      log "reap $w: PR needs-help"; kill_win "$w"; continue
    fi
    if [ "$(win_age "$w")" -gt "$STALE" ]; then
      needs_help pr "$pr" "integrator ran longer than ${STALE}s."
      kill_win "$w"
    fi
  done
}

# An in-progress issue with no window and no open PR lost its worker. Give it
# one retry, then ask for help.
requeue_orphans() {
  local issue pr retry
  for issue in $(gh issue list --label in-progress --state open --limit 50 --json number --jq '.[].number'); do
    win_exists "mw-$issue" && continue
    pr=$(pr_for_issue "$issue")
    [ -n "$pr" ] && [ "$(gh pr view "$pr" --json state --jq .state)" = OPEN ] && continue
    retry="$STATE/retry-$issue"
    if [ -f "$retry" ]; then
      needs_help issue "$issue" "worker disappeared twice without opening a PR."
      rm -f "$retry"
    else
      log "requeue #$issue: worker gone, retrying once"
      touch "$retry"
      run gh issue edit "$issue" --add-label ready --remove-label in-progress
    fi
  done
}

dispatch() {
  local running issue
  running=$(windows_with_prefix mw- | wc -l)
  for issue in $(ready_issues); do
    [ "$running" -lt "$MAX_WORKERS" ] || break
    log "claim #$issue"
    run gh issue edit "$issue" --add-label in-progress --remove-label ready
    spawn "mw-$issue" maestro-worker "$issue"
    running=$((running + 1))
  done
}

unblock_dependents() {
  local closed=$1 num body blockers b all_closed
  gh issue list --state open --limit 100 --search "\"Blocked by\" in:body" \
    --json number,body,labels \
    --jq '.[] | select(any(.labels[]; .name == "ready" or .name == "in-progress" or .name == "needs-help") | not) | "\(.number)\t\(.body | gsub("\n"; " "))"' |
  while IFS=$'\t' read -r num body; do
    blockers=$(grep -oiE 'blocked by[^.]*' <<<"$body" | grep -oE '#[0-9]+' | tr -d '#' | sort -u)
    grep -x "$closed" <<<"$blockers" >/dev/null || continue
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

merge_pr() {
  local pr=$1 issue=$2 mergeable out
  mergeable=$(gh pr view "$pr" --json mergeable --jq .mergeable)
  if [ "$mergeable" = CONFLICTING ]; then
    needs_help pr "$pr" "merge conflict with main; rebase or resolve by hand."
    return
  fi
  log "merge PR #$pr (issue #$issue)"
  if [ "$DRY" = 1 ]; then log "dry: gh pr merge $pr --squash --delete-branch"; return; fi
  if out=$(gh pr merge "$pr" --squash --delete-branch 2>&1); then
    if [ "$(issue_state "$issue")" = OPEN ]; then
      gh issue close "$issue" --comment "Merged in #$pr." >/dev/null
    fi
    gh issue edit "$issue" --remove-label in-progress >/dev/null 2>&1 || true
    git -C "$REPO" branch -D "task/$issue" >/dev/null 2>&1 || true
    rm -f "$STATE/retry-$issue"
    unblock_dependents "$issue"
  else
    needs_help pr "$pr" "gh pr merge failed: $out"
  fi
}

integrate() {
  local line pr issue draft labels
  while read -r line; do
    [ -n "$line" ] || continue
    read -r pr issue draft labels <<<"$line"
    [ "$draft" = false ] || continue
    case ",$labels," in
      *,needs-help,*) continue ;;
      *,needs-browser,*|*,needs-migration,*)
        win_exists "mi-$pr" && continue
        [ -z "$(windows_with_prefix mi-)" ] || continue
        spawn "mi-$pr" maestro-integrator "$pr"
        ;;
      *) merge_pr "$pr" "$issue" ;;
    esac
  done <<<"$(task_prs)"
}

tick() {
  reap_workers
  reap_integrators
  requeue_orphans
  integrate
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
