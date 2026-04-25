# icp-skills Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local Claude Code plugin (`icp-skills`) that mirrors the Dfinity skills registry at https://skills.internetcomputer.org as a set of per-skill stubs plus a fallback router, letting Claude automatically consult live Dfinity guidance for ICP topics.

**Architecture:** Pure-skills plugin. Per-skill stubs (one per registry entry) carry verbatim descriptions from `index.json` for precise matcher triggering; each stub body tells Claude to `curl` the live SKILL.md at use-time. A hand-written `icp-skills-router` skill handles ICP topics not covered by any stub (e.g. newly-added registry entries). A shell sync script regenerates the stubs from `index.json` on demand; a validator script smoke-tests frontmatter.

**Tech Stack:** Claude Code plugin manifest, Markdown + YAML frontmatter for skills, Bash + `curl` + `jq` for scripts. No runtime dependencies beyond `curl` (for the skills themselves) and `jq` (for the sync script).

**Project context:** Working directory is `/Users/remcodes/Documents/Claude/Plugin`. Not a git repo (user chose "local only"). Plan uses "Save file" instead of commit steps — if user later inits git, they can squash in a single commit.

---

## File Structure

Files this plan creates, and each file's single responsibility:

| Path | Responsibility |
|---|---|
| `.claude-plugin/plugin.json` | Plugin manifest (name, version, description). |
| `skills/icp-skills-router/SKILL.md` | Hand-written fallback skill: fetches `index.json` when no stub matched. Never touched by sync. |
| `scripts/sync-skills.sh` | Fetches `index.json` and regenerates `skills/<name>/SKILL.md` for every entry. Prunes removed skills. Idempotent. Honors `ICP_SKILLS_INDEX_URL` for test overrides. |
| `scripts/validate-skills.sh` | Smoke-checks every `skills/*/SKILL.md`: valid frontmatter, `name` matches dir, `description` present. |
| `scripts/test-sync.sh` | Integration test for `sync-skills.sh` using a fixture `index.json`. |
| `tests/fixtures/index.json` | Fixture registry used by `test-sync.sh`. Two fake skills. |
| `tests/fixtures/index-pruned.json` | Fixture with one skill removed — used to test pruning. |
| `skills/<name>/SKILL.md` (×N) | Generated stub per registry entry. Produced by Task 5. |
| `README.md` | How to install, use, sync, and validate the plugin. |

---

### Task 1: Plugin manifest

**Files:**
- Create: `.claude-plugin/plugin.json`

- [ ] **Step 1: Create the manifest**

Write `/Users/remcodes/Documents/Claude/Plugin/.claude-plugin/plugin.json`:

```json
{
  "name": "icp-skills",
  "version": "0.1.0",
  "description": "Ambient access to the Dfinity Internet Computer skills registry (https://skills.internetcomputer.org). Claude automatically consults live Dfinity guidance for ICP topics like canisters, Motoko, Rust canisters, ckBTC, Internet Identity, and SNS."
}
```

- [ ] **Step 2: Verify the JSON parses**

Run: `jq . /Users/remcodes/Documents/Claude/Plugin/.claude-plugin/plugin.json`
Expected: pretty-printed JSON, exit 0.

- [ ] **Step 3: Save**

File is saved.

---

### Task 2: Router skill

**Files:**
- Create: `skills/icp-skills-router/SKILL.md`

- [ ] **Step 1: Create the router skill**

Write `/Users/remcodes/Documents/Claude/Plugin/skills/icp-skills-router/SKILL.md`. Note: the body contains a fenced code block — use a literal four-backtick outer fence OR escape carefully. Content below uses the **raw bytes** to write (the inner three-backtick fence is part of the body):

```
---
name: icp-skills-router
description: Use when working on Internet Computer / ICP / dfinity / canisters / Motoko / Rust canisters / ckBTC / ckETH / SNS / cycles and no more specific ICP skill has matched. Catches skills added to the Dfinity registry after this plugin was last synced.
---

# icp-skills-router

This plugin ships per-skill stubs generated from the Dfinity skills registry at
https://skills.internetcomputer.org. If you're reading this, it means no specific
ICP stub matched the user's task — usually because Dfinity added a new skill to
the registry since the last local sync.

Fetch the live registry:

` ``bash
curl -sSfL https://skills.internetcomputer.org/.well-known/skills/index.json
` ``

Scan the `skills[]` array for an entry whose description matches the user's task.
If one does, fetch its `url` and follow that SKILL.md as authoritative — prefer
it over general knowledge. If none fits, say so and fall back to general
knowledge, clearly flagging uncertainty.

After using a new skill this way, tell the user: "This skill wasn't in the local
stubs — you can refresh by running `scripts/sync-skills.sh`."

Do NOT invoke this skill if a more specific ICP skill already triggered — this
exists only to cover registry drift.
```

**Important:** in the actual file, the ` `` ` sequences are real triple-backticks. The space after the first backtick in this plan is just to prevent this plan's own fence from closing. Strip the spaces when writing.

- [ ] **Step 2: Verify frontmatter parses**

Run:
```bash
head -4 /Users/remcodes/Documents/Claude/Plugin/skills/icp-skills-router/SKILL.md
```
Expected: first line `---`, then `name: icp-skills-router`, then `description: Use when working on Internet Computer ...`, then `---`.

- [ ] **Step 3: Save**

File is saved.

---

### Task 3: Frontmatter validator — write test, then script

**Files:**
- Create: `scripts/validate-skills.sh`

- [ ] **Step 1: Write a failing expectation by hand**

Before writing the validator, run the check you expect the validator to perform, manually:

```bash
cd /Users/remcodes/Documents/Claude/Plugin
ls skills/
```
Expected: only `icp-skills-router`.

```bash
awk '/^---$/{c++; next} c==1' skills/icp-skills-router/SKILL.md | head -3
```
Expected: lines starting with `name: icp-skills-router` and `description: Use when ...`.

If the above prints what's expected, the validator has a clear target behavior: "for every `skills/*/SKILL.md`, frontmatter must define `name` matching dir and non-empty `description`."

- [ ] **Step 2: Write the validator script**

Write `/Users/remcodes/Documents/Claude/Plugin/scripts/validate-skills.sh`:

```bash
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

  # Extract frontmatter block (lines between first two --- markers).
  frontmatter="$(awk '
    /^---$/ { c++; if (c==2) exit; next }
    c==1   { print }
  ' "$skill_file")"

  [[ -n "$frontmatter" ]] || fail "$dir_name: missing or empty frontmatter"

  name_line="$(printf '%s\n' "$frontmatter" | grep -E '^name:' || true)"
  desc_line="$(printf '%s\n' "$frontmatter" | grep -E '^description:' || true)"

  [[ -n "$name_line" ]] || fail "$dir_name: frontmatter missing 'name:'"
  [[ -n "$desc_line" ]] || fail "$dir_name: frontmatter missing 'description:'"

  name_val="$(printf '%s' "$name_line" | sed -E 's/^name:[[:space:]]*//')"
  desc_val="$(printf '%s' "$desc_line" | sed -E 's/^description:[[:space:]]*//')"

  [[ "$name_val" == "$dir_name" ]] || fail "$dir_name: name '$name_val' does not match dir '$dir_name'"
  [[ -n "$desc_val"            ]] || fail "$dir_name: description is empty"
done

echo "OK: $count skill(s) validated."
```

- [ ] **Step 3: Make executable and run**

```bash
chmod +x /Users/remcodes/Documents/Claude/Plugin/scripts/validate-skills.sh
/Users/remcodes/Documents/Claude/Plugin/scripts/validate-skills.sh
```
Expected: `OK: 1 skill(s) validated.` (only the router exists at this point).

- [ ] **Step 4: Sanity-check failure mode**

Temporarily break the router's name to ensure the validator actually fails:

```bash
sed -i.bak 's/name: icp-skills-router/name: wrong-name/' /Users/remcodes/Documents/Claude/Plugin/skills/icp-skills-router/SKILL.md
/Users/remcodes/Documents/Claude/Plugin/scripts/validate-skills.sh || echo "validator correctly failed"
mv /Users/remcodes/Documents/Claude/Plugin/skills/icp-skills-router/SKILL.md.bak /Users/remcodes/Documents/Claude/Plugin/skills/icp-skills-router/SKILL.md
/Users/remcodes/Documents/Claude/Plugin/scripts/validate-skills.sh
```
Expected: first run prints `FAIL: icp-skills-router: name 'wrong-name' does not match dir 'icp-skills-router'` then `validator correctly failed`; restore; second run prints `OK: 1 skill(s) validated.`

- [ ] **Step 5: Save**

Files saved.

---

### Task 4: Sync script — fixtures + test harness first (TDD)

**Files:**
- Create: `tests/fixtures/index.json`
- Create: `tests/fixtures/index-pruned.json`
- Create: `scripts/test-sync.sh`

- [ ] **Step 1: Write the primary fixture**

Write `/Users/remcodes/Documents/Claude/Plugin/tests/fixtures/index.json`:

```json
{
  "skills": [
    {
      "name": "fake-alpha",
      "description": "Fake skill alpha for test purposes. Use when testing sync behavior.",
      "url": "https://example.invalid/.well-known/skills/fake-alpha/SKILL.md"
    },
    {
      "name": "fake-beta",
      "description": "Fake skill beta for test purposes. Use when testing prune behavior.",
      "url": "https://example.invalid/.well-known/skills/fake-beta/SKILL.md"
    }
  ]
}
```

- [ ] **Step 2: Write the pruned fixture**

Write `/Users/remcodes/Documents/Claude/Plugin/tests/fixtures/index-pruned.json`:

```json
{
  "skills": [
    {
      "name": "fake-alpha",
      "description": "Fake skill alpha for test purposes. Use when testing sync behavior.",
      "url": "https://example.invalid/.well-known/skills/fake-alpha/SKILL.md"
    }
  ]
}
```

- [ ] **Step 3: Write the test harness**

Write `/Users/remcodes/Documents/Claude/Plugin/scripts/test-sync.sh`:

```bash
#!/usr/bin/env bash
# Integration test for sync-skills.sh. Copies the plugin layout to a temp dir,
# points sync at a fixture index.json, and asserts expected behaviors:
#   1. Generates a stub per registry entry with correct name + description.
#   2. Leaves icp-skills-router/ untouched.
#   3. Prunes stubs whose names are no longer in the registry.
#   4. Is idempotent (second run produces zero diff).

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

echo "OK: sync-skills.sh passes all assertions."
```

- [ ] **Step 4: Make executable and run — expect failure (script doesn't exist yet)**

```bash
chmod +x /Users/remcodes/Documents/Claude/Plugin/scripts/test-sync.sh
/Users/remcodes/Documents/Claude/Plugin/scripts/test-sync.sh || echo "test correctly failed (script missing)"
```
Expected: fails with a "No such file" or "cp: ...sync-skills.sh" error, confirming the harness fires before the implementation exists. This is the red step of red-green-refactor.

- [ ] **Step 5: Save**

All three files saved.

---

### Task 5: Sync script — implementation to make the test pass

**Files:**
- Create: `scripts/sync-skills.sh`

- [ ] **Step 1: Write the sync script**

Write `/Users/remcodes/Documents/Claude/Plugin/scripts/sync-skills.sh`:

```bash
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

# Collect registry names.
mapfile -t registry_names < <(printf '%s' "$index_json" | jq -r '.skills[].name')

added=0; updated=0; removed=0; unchanged=0

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

echo "sync complete — added: $added, updated: $updated, unchanged: $unchanged, removed: $removed"
```

- [ ] **Step 2: Make executable**

```bash
chmod +x /Users/remcodes/Documents/Claude/Plugin/scripts/sync-skills.sh
```

- [ ] **Step 3: Run the test harness — expect PASS**

```bash
/Users/remcodes/Documents/Claude/Plugin/scripts/test-sync.sh
```
Expected: `OK: sync-skills.sh passes all assertions.`

If any assertion fails, debug by running the relevant sub-command manually against `$WORK` (add `set -x` at top of `sync-skills.sh` temporarily).

- [ ] **Step 4: Save**

File saved.

---

### Task 6: Generate the real stubs against the live registry

**Files:**
- Create (generated): `skills/<name>/SKILL.md` × N (19 at time of writing)

- [ ] **Step 1: Dry-run against live registry**

```bash
cd /Users/remcodes/Documents/Claude/Plugin
./scripts/sync-skills.sh --dry-run
```
Expected: `would add:` for each of the 19 current registry entries; `unchanged: 0, removed: 0`. If network blocks, rerun when possible — stubs are required for a useful plugin.

- [ ] **Step 2: Real run**

```bash
./scripts/sync-skills.sh
```
Expected: `sync complete — added: 19, updated: 0, unchanged: 0, removed: 0` (number may vary if Dfinity has added/removed skills since 2026-04-24).

- [ ] **Step 3: Spot-check a generated stub**

```bash
cat /Users/remcodes/Documents/Claude/Plugin/skills/motoko/SKILL.md
```
Expected: frontmatter with `name: motoko` and a description starting "Motoko language pitfalls and modern syntax for the Internet Computer."; body containing the `curl ... motoko/SKILL.md` line.

- [ ] **Step 4: Run validator across all stubs**

```bash
./scripts/validate-skills.sh
```
Expected: `OK: 20 skill(s) validated.` (19 stubs + 1 router). Adjust expected count to match actual registry.

- [ ] **Step 5: Save**

Generated files saved.

---

### Task 7: README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write the README**

Write `/Users/remcodes/Documents/Claude/Plugin/README.md`:

```markdown
# icp-skills — Claude Code plugin

Ambient access to the [Dfinity Internet Computer skills registry](https://skills.internetcomputer.org) from Claude Code. When you work on ICP topics (canisters, Motoko, ckBTC, Internet Identity, SNS, cycles, etc.), Claude's skill matcher fires the matching stub, which tells Claude to fetch the live Dfinity SKILL.md and follow it.

## How it works

- **Per-skill stubs** (`skills/<name>/SKILL.md`): one per entry in the registry's `index.json`. Each stub's frontmatter `description` is copied verbatim from the registry, giving the skill matcher precise triggers. The body instructs Claude to `curl` the live SKILL.md and follow it — no content is vendored, because the registry updates frequently.
- **Router skill** (`skills/icp-skills-router/SKILL.md`): hand-written fallback for ICP topics no stub matched (usually because Dfinity added a new skill since you last synced). It fetches `index.json` at use-time and looks for a match.

## Install (local)

This plugin isn't published yet. To try it locally, point Claude Code at this directory.

## Sync stubs with the live registry

```bash
./scripts/sync-skills.sh           # fetch index.json, write/update/prune stubs
./scripts/sync-skills.sh --dry-run # show what would change, write nothing
```

## Validate

```bash
./scripts/validate-skills.sh       # frontmatter smoke test across all stubs
./scripts/test-sync.sh             # integration test for the sync script
```

## Requirements

- `curl`, `jq`, Bash 4+ (macOS: `brew install jq bash`).

## Notes

- Skills are fetched live at use-time; this plugin is online-only by design.
- The router covers drift between syncs — if it fires, run `scripts/sync-skills.sh` to refresh.
```

- [ ] **Step 2: Save**

File saved.

---

### Task 8: End-to-end manual smoke test

No new files. Verify the plugin actually does what it's for.

- [ ] **Step 1: Confirm final layout**

```bash
find /Users/remcodes/Documents/Claude/Plugin -maxdepth 3 -type f \
  \( -name '*.json' -o -name '*.md' -o -name '*.sh' \) | sort
```
Expected: manifest, README, docs/superpowers/**, router SKILL, ~19 stub SKILLs, three scripts, two fixtures.

- [ ] **Step 2: Re-run all checks**

```bash
cd /Users/remcodes/Documents/Claude/Plugin
./scripts/validate-skills.sh
./scripts/test-sync.sh
./scripts/sync-skills.sh --dry-run   # should be a no-op
```
Expected: validator OK; test-sync OK; dry-run shows `added: 0, updated: 0` (non-zero `unchanged`, `removed: 0`).

- [ ] **Step 3: Load the plugin in Claude Code and try a canonical prompt**

Install the plugin locally (per Claude Code docs for local plugins), then in a fresh Claude Code session ask:

> "How do I persist canister state across upgrades in Rust?"

Expected: Claude invokes the `stable-memory` skill, the stub instructs it to fetch the live SKILL.md, and the answer reflects that fetched guidance (mentioning `StableBTreeMap`, `MemoryManager`, etc.).

- [ ] **Step 4: Try a drift-style prompt**

Ask something ICP-ish that won't match a specific stub, e.g.:

> "Is there any IC-specific guidance I should follow for this project?"

Expected: `icp-skills-router` fires; Claude fetches `index.json`, summarizes what's available, and offers to consult a specific skill if the topic narrows.

- [ ] **Step 5: Report results**

Note any stub that triggered incorrectly or failed to trigger. If found, either (a) the registry description is ambiguous → open an issue upstream with Dfinity; or (b) router description needs more ICP surface terms → adjust `skills/icp-skills-router/SKILL.md`.

---

## Self-review

**Spec coverage:**

| Spec section | Covered by |
|---|---|
| `plugin.json` manifest | Task 1 |
| Per-skill stub contract | Tasks 5 (script renders template), 6 (generation) |
| Router skill | Task 2 |
| `sync-skills.sh` | Tasks 4 (test harness), 5 (implementation) |
| Idempotency | Task 4 assertion 3 |
| Pruning | Task 4 assertion 4 |
| Router never touched by sync | Task 4 assertion 2 |
| Frontmatter smoke test | Task 3 |
| `--dry-run` flag | Tasks 5 (implementation), 6 + 8 (exercised) |
| Manual end-to-end | Task 8 |
| Failure modes (non-zero exit) | `set -euo pipefail` in all scripts; Task 3 step 4 exercises a failure |

All spec requirements have an implementing task. No gaps found.

**Placeholders:** None. Every code block is complete. No "TODO", "implement later", or "similar to Task N" references.

**Type/name consistency checks:**

- Directory name `icp-skills-router` used identically in Task 2, Task 4 assertion 2, Task 5 (`ROUTER_NAME`). ✓
- Env var `ICP_SKILLS_INDEX_URL` used identically in Task 4 (test) and Task 5 (script). ✓
- Fixture skill names `fake-alpha`, `fake-beta` used consistently across fixtures and assertions. ✓
- `scripts/sync-skills.sh`, `scripts/validate-skills.sh`, `scripts/test-sync.sh` paths used consistently. ✓
- Stub template in Task 5's `render_stub` matches the spec's stub contract. ✓
