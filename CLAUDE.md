# Plyst RN Claude Code Bootstrap

## Scope

- These instructions apply to the repository root.
- Active AI working rules live in Notion under `Plyst RN Agent Policy`.
- This file is a bootstrap document only. Do not add project policy content here.

## Required policy loading

Before planning, editing, reviewing, verifying, delegating, or performing an external write:

1. Fetch the [Plyst RN Agent Policy](https://app.notion.com/p/3f1b88a8aa5481159150e7be1c0b1313) index through the connected Notion MCP.
2. Verify that the index is under the [Plyst RN](https://app.notion.com/p/3f1b88a8aa5481f4938cc2484f4fd5c7) page and use only policies marked `Active` in that index.
3. Load `General`, `iOS`, `React Native`, and `Claude Code` for every task.
4. Load every task-specific policy whose route matches the request. Routes are cumulative.

If Notion MCP or a required active policy is unavailable, stop the Plyst RN task and report the unavailable policy. Do not use stale memory as a fallback.

## Source boundaries

- Active Notion policies are the source of AI working rules.
- Current repository code, configuration, templates, CI workflows, and product documentation are the source of implementation facts.
- Active Notion policies and current repository evidence take precedence over global Claude memory and global `~/.claude` instructions.
- Keep credentials, tokens, and private configuration out of this repository.
