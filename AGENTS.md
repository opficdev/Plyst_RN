# Plyst Agent Bootstrap

## Scope

- These instructions apply to the repository root.
- Active AI working rules live in Notion under `Plyst Agent Policy`.
- This file is a bootstrap document only. Do not add project policy content here.

## Required policy loading

Before planning, editing, reviewing, verifying, delegating, or performing an external write:

1. Fetch the [Plyst Agent Policy](https://app.notion.com/p/3e9b88a8aa548149a2afd2a226695f30) index through the connected Notion MCP.
2. Verify that the index is under the [Plyst](https://app.notion.com/p/3e9b88a8aa54813c9c21dd2dfa334937) page and use only policies marked `Active` in that index.
3. Load `General`, `iOS`, and `Codex` for every task.
4. Load every task-specific policy whose route matches the request. Routes are cumulative.

If Notion MCP or a required active policy is unavailable, stop the Plyst task and report the unavailable policy. Do not use stale memory as a fallback.

## Source boundaries

- Active Notion policies are the source of AI working rules.
- Current repository code, configuration, templates, CI workflows, and product documentation are the source of implementation facts.
- Memory provides historical context only and must not override active policies or current repository evidence.
- Keep credentials, tokens, and private configuration out of this repository.
