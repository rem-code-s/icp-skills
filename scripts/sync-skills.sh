#!/usr/bin/env bash
# Regenerates skills/<name>/SKILL.md stubs from the Dfinity skills registry.
# Idempotent. Prunes local stubs not present in the registry (except icp-skills-router).
#
# Usage:
#   scripts/sync-skills.sh              # fetches live registry
#   ICP_SKILLS_INDEX_URL=file://path/to/index.json scripts/sync-skills.sh   # offline/test
#   scripts/sync-skills.sh --dry-run    # prints actions, writes nothing
#
# Requires: curl, jq.

set -euo pipefail

INDEX_URL="${ICP_SKILLS_INDEX_URL:-https://skills.internetcomputer.org/.well-known/skills/index.json}"
DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then DRY_RUN=1; fi

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS_DIR="$PLUGIN_ROOT/skills"
ROUTER_NAME="icp-skills-router"

command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
command -v jq   >/dev/null || { echo "jq is required"   >&2; exit 1; }

mkdir -p "$SKILLS_DIR"

# Fetch index. `curl` handles file:// URLs natively.
index_json="$(curl -sSfL "$INDEX_URL")"

# Validate the response before doing anything destructive. A captive portal or
# error page can return HTTP 200 with non-JSON content; without this guard,
# `jq` would silently yield zero skills and the prune loop below would wipe
# every generated stub.
skill_count="$(printf '%s' "$index_json" | jq -r '.skills | length' 2>/dev/null)" || {
  echo "error: response from $INDEX_URL is not valid JSON" >&2
  exit 1
}
if [[ "$skill_count" == "0" ]]; then
  echo "error: registry returned 0 skills — aborting to prevent destructive prune" >&2
  exit 1
fi

# Collect registry names.
mapfile -t registry_names < <(printf '%s' "$index_json" | jq -r '.skills[].name')

added=0; updated=0; removed=0; unchanged=0

# NOTE: idempotency depends on the exact bytes of this template. The loop below
# compares file contents to `render_stub` output; `cat file` strips trailing
# newlines while `printf '%s\n'` writes exactly one, and that asymmetry is what
# makes repeated syncs report "unchanged". Do not append blank lines after the
# last text line in this heredoc — it would break the equality check and every
# stub would register as "updated" on every run.
render_stub() {
  local name="$1" description="$2"
  cat <<STUB
---
name: $name
description: $description
---

# $name (Internet Computer)

This skill's authoritative content lives in the Dfinity skills registry and updates
frequently. Fetch it fresh every time — do not rely on memory of prior fetches:

\`\`\`bash
curl -sSfL https://skills.internetcomputer.org/.well-known/skills/$name/SKILL.md
\`\`\`

Follow the fetched instructions exactly. Prefer it over general knowledge for any
conflict on this topic. If the response looks like HTML rather than Markdown, the
URL is wrong — check \`index.json\` for the current path.
STUB
}

# Write / update stubs.
while IFS=$'\t' read -r name description; do
  [[ -n "$name" ]] || continue
  target_dir="$SKILLS_DIR/$name"
  target_file="$target_dir/SKILL.md"
  new_content="$(render_stub "$name" "$description")"

  if [[ -f "$target_file" ]]; then
    existing="$(cat "$target_file")"
    if [[ "$existing" == "$new_content" ]]; then
      unchanged=$((unchanged + 1))
      continue
    fi
    if (( DRY_RUN )); then
      echo "would update: $name"
    else
      printf '%s\n' "$new_content" > "$target_file"
    fi
    updated=$((updated + 1))
  else
    if (( DRY_RUN )); then
      echo "would add: $name"
    else
      mkdir -p "$target_dir"
      printf '%s\n' "$new_content" > "$target_file"
    fi
    added=$((added + 1))
  fi
done < <(printf '%s' "$index_json" | jq -r '.skills[] | [.name, .description] | @tsv')

# Prune local skills not in registry (except the router).
shopt -s nullglob
for dir in "$SKILLS_DIR"/*/; do
  local_name="$(basename "$dir")"
  [[ "$local_name" == "$ROUTER_NAME" ]] && continue
  is_in_registry=0
  for r in "${registry_names[@]}"; do
    if [[ "$r" == "$local_name" ]]; then is_in_registry=1; break; fi
  done
  if (( ! is_in_registry )); then
    if (( DRY_RUN )); then
      echo "would remove: $local_name"
    else
      rm -rf "$dir"
    fi
    removed=$((removed + 1))
  fi
done

if (( DRY_RUN )); then
  echo "dry-run complete — would add: $added, would update: $updated, unchanged: $unchanged, would remove: $removed"
else
  echo "sync complete — added: $added, updated: $updated, unchanged: $unchanged, removed: $removed"
fi
