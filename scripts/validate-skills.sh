#!/usr/bin/env bash
# Validates every skills/*/SKILL.md has:
#   - YAML frontmatter delimited by --- lines
#   - `name:` matching the parent directory name
#   - `description:` that is non-empty
# Exits 0 on success, 1 on first failure. Intended for manual + CI smoke use.

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILLS_DIR="$PLUGIN_ROOT/skills"

if [[ ! -d "$SKILLS_DIR" ]]; then
  echo "No skills/ directory at $SKILLS_DIR" >&2
  exit 1
fi

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

shopt -s nullglob
count=0
for skill_dir in "$SKILLS_DIR"/*/; do
  count=$((count + 1))
  dir_name="$(basename "$skill_dir")"
  skill_file="$skill_dir/SKILL.md"

  [[ -f "$skill_file" ]] || fail "$dir_name: missing SKILL.md"

  # Require a closed frontmatter block (two --- markers). Without this check,
  # an unclosed frontmatter would cause the awk extractor below to read the
  # entire body and silently pass validation.
  marker_count="$(awk '/^---$/{c++} END{print c+0}' "$skill_file")"
  (( marker_count >= 2 )) || fail "$dir_name: frontmatter not closed (need two --- markers)"

  # Extract frontmatter block (lines between first two --- markers).
  frontmatter="$(awk '
    /^---$/ { c++; if (c==2) exit; next }
    c==1   { print }
  ' "$skill_file")"

  [[ -n "$frontmatter" ]] || fail "$dir_name: missing or empty frontmatter"

  name_line="$(printf '%s\n' "$frontmatter" | grep -m 1 -E '^name:' || true)"
  desc_line="$(printf '%s\n' "$frontmatter" | grep -m 1 -E '^description:' || true)"

  [[ -n "$name_line" ]] || fail "$dir_name: frontmatter missing 'name:'"
  [[ -n "$desc_line" ]] || fail "$dir_name: frontmatter missing 'description:'"

  # Strip the key prefix and any trailing \r (CRLF-safe for files touched by Windows editors).
  name_val="$(printf '%s' "$name_line" | sed -E 's/^name:[[:space:]]*//; s/\r$//')"
  desc_val="$(printf '%s' "$desc_line" | sed -E 's/^description:[[:space:]]*//; s/\r$//')"

  [[ "$name_val" == "$dir_name" ]] || fail "$dir_name: name '$name_val' does not match dir '$dir_name'"
  [[ -n "$desc_val"            ]] || fail "$dir_name: description is empty"
done

echo "OK: $count skill(s) validated."
