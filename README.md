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

The sync script refuses to run if the registry response is not valid JSON or contains zero skills — this prevents a transient network failure (e.g. a captive portal returning an HTML page) from wiping every local stub.

## Validate

```bash
./scripts/validate-skills.sh       # frontmatter smoke test across all stubs
./scripts/test-sync.sh             # integration test for the sync script
```

## Requirements

- `curl`, `jq`, Bash 4+ (macOS: `brew install jq bash`).

## Notes

- Skills are fetched live at use-time; this plugin is online-only by design.
- The router covers drift between syncs — if it fires, run `./scripts/sync-skills.sh` to refresh.
