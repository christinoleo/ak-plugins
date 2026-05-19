#!/usr/bin/env bash
# Manually bump the ak plugin version in both plugin.json and marketplace.json.
# Usage: ./scripts/bump.sh patch|minor|major
# Useful when you want to bump out-of-band of a commit, or pre-bump before
# committing (which makes the pre-commit hook skip its auto-bump).

set -e

BUMP="${1:-patch}"
case "$BUMP" in
  major|minor|patch) ;;
  *) echo "usage: $0 patch|minor|major" >&2; exit 1 ;;
esac

REPO_ROOT=$(git rev-parse --show-toplevel)
PLUGIN_JSON="$REPO_ROOT/plugin/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$REPO_ROOT/.claude-plugin/marketplace.json"

CURRENT=$(python3 -c "import json; print(json.load(open('$PLUGIN_JSON'))['version'])")
IFS='.' read -r MAJ MIN PAT <<< "$CURRENT"
case "$BUMP" in
  major) MAJ=$((MAJ + 1)); MIN=0; PAT=0 ;;
  minor) MIN=$((MIN + 1)); PAT=0 ;;
  patch) PAT=$((PAT + 1)) ;;
esac
NEW="$MAJ.$MIN.$PAT"

python3 <<PY
import json
for path, is_marketplace in (("$PLUGIN_JSON", False), ("$MARKETPLACE_JSON", True)):
    with open(path) as f:
        d = json.load(f)
    if is_marketplace:
        for p in d.get("plugins", []):
            if p.get("name") == "ak":
                p["version"] = "$NEW"
    else:
        d["version"] = "$NEW"
    with open(path, "w") as f:
        json.dump(d, f, indent=2)
        f.write("\n")
PY

echo "ak: $CURRENT -> $NEW ($BUMP)"
