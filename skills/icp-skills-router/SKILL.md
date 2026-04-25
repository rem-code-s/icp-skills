---
name: icp-skills-router
description: Use when working on Internet Computer / ICP / dfinity / canisters / Motoko / Rust canisters / ckBTC / ckETH / Internet Identity / SNS / cycles and no more specific ICP skill has matched. Catches skills added to the Dfinity registry after this plugin was last synced.
---

# icp-skills-router

This plugin ships per-skill stubs generated from the Dfinity skills registry at
https://skills.internetcomputer.org. If you're reading this, it means no specific
ICP stub matched the user's task — usually because Dfinity added a new skill to
the registry since the last local sync.

Fetch the live registry:

```bash
curl -sSfL https://skills.internetcomputer.org/.well-known/skills/index.json
```

Scan the `skills[]` array for an entry whose description matches the user's task.
If one does, fetch its `url` and follow that SKILL.md as authoritative — prefer
it over general knowledge. If none fits, say so and fall back to general
knowledge, clearly flagging uncertainty.

After using a new skill this way, tell the user: "This skill wasn't in the local
stubs — you can refresh by running `scripts/sync-skills.sh`."

Do NOT invoke this skill if a more specific ICP skill already triggered — this
exists only to cover registry drift.
