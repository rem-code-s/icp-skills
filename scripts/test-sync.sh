#!/usr/bin/env bash
# Integration test for sync-skills.sh. Copies the plugin layout to a temp dir,
# points sync at a fixture index.json, and asserts expected behaviors:
#   1. Generates a stub per registry entry with correct name + description.
#   2. Leaves icp-skills-router/ untouched.
#   3. Is idempotent (second run produces zero diff).
#   4. Prunes stubs whose names are no longer in the registry.
#   5. --dry-run writes no files.

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Mirror the real plugin skeleton into the temp dir.
mkdir -p "$WORK/skills/icp-skills-router"
cp "$PLUGIN_ROOT/skills/icp-skills-router/SKILL.md" "$WORK/skills/icp-skills-router/SKILL.md"
mkdir -p "$WORK/scripts"
cp "$PLUGIN_ROOT/scripts/sync-skills.sh" "$WORK/scripts/sync-skills.sh"
chmod +x "$WORK/scripts/sync-skills.sh"

fail() { echo "FAIL: $1" >&2; exit 1; }

# --- Assertion 1: generates stubs from index.json ---
export ICP_SKILLS_INDEX_URL="file://$PLUGIN_ROOT/tests/fixtures/index.json"
(cd "$WORK" && ./scripts/sync-skills.sh)

[[ -f "$WORK/skills/fake-alpha/SKILL.md" ]] || fail "fake-alpha stub not created"
[[ -f "$WORK/skills/fake-beta/SKILL.md"  ]] || fail "fake-beta stub not created"
grep -q '^name: fake-alpha$' "$WORK/skills/fake-alpha/SKILL.md" || fail "fake-alpha name wrong"
grep -q '^description: Fake skill alpha for test purposes' "$WORK/skills/fake-alpha/SKILL.md" \
  || fail "fake-alpha description wrong"

# --- Assertion 2: router untouched ---
grep -q '^name: icp-skills-router$' "$WORK/skills/icp-skills-router/SKILL.md" \
  || fail "router was modified"

# --- Assertion 3: idempotent ---
checksum_before="$(find "$WORK/skills" -type f -name SKILL.md -exec md5 -q {} \; 2>/dev/null \
                   | sort | md5 -q 2>/dev/null \
                   || find "$WORK/skills" -type f -name SKILL.md -exec md5sum {} \; | sort | md5sum)"
(cd "$WORK" && ./scripts/sync-skills.sh)
checksum_after="$(find "$WORK/skills" -type f -name SKILL.md -exec md5 -q {} \; 2>/dev/null \
                  | sort | md5 -q 2>/dev/null \
                  || find "$WORK/skills" -type f -name SKILL.md -exec md5sum {} \; | sort | md5sum)"
[[ "$checksum_before" == "$checksum_after" ]] || fail "sync not idempotent"

# --- Assertion 4: prunes removed skills ---
export ICP_SKILLS_INDEX_URL="file://$PLUGIN_ROOT/tests/fixtures/index-pruned.json"
(cd "$WORK" && ./scripts/sync-skills.sh)
[[ ! -d "$WORK/skills/fake-beta" ]] || fail "fake-beta not pruned"
[[ -f "$WORK/skills/fake-alpha/SKILL.md" ]] || fail "fake-alpha deleted by prune"
[[ -f "$WORK/skills/icp-skills-router/SKILL.md" ]] || fail "router deleted by prune"

# --- Assertion 5: --dry-run writes nothing ---
WORK2="$(mktemp -d)"
trap 'rm -rf "$WORK" "$WORK2"' EXIT
mkdir -p "$WORK2/skills/icp-skills-router" "$WORK2/scripts"
cp "$PLUGIN_ROOT/skills/icp-skills-router/SKILL.md" "$WORK2/skills/icp-skills-router/SKILL.md"
cp "$PLUGIN_ROOT/scripts/sync-skills.sh" "$WORK2/scripts/sync-skills.sh"
chmod +x "$WORK2/scripts/sync-skills.sh"
export ICP_SKILLS_INDEX_URL="file://$PLUGIN_ROOT/tests/fixtures/index.json"
(cd "$WORK2" && ./scripts/sync-skills.sh --dry-run >/dev/null)
[[ ! -d "$WORK2/skills/fake-alpha" ]] || fail "dry-run created fake-alpha"
[[ ! -d "$WORK2/skills/fake-beta"  ]] || fail "dry-run created fake-beta"

echo "OK: sync-skills.sh passes all assertions."
