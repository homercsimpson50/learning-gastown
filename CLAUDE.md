# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is a **documentation-only** repository containing learning notes about [Gas Town](https://github.com/gastownhall/gastown) (multi-agent orchestration framework) and [Beads](https://github.com/gastownhall/beads) (distributed graph issue tracker). Both projects are by Steve Yegge.

There is no source code to build, test, or lint. The repo consists of markdown documentation.

## Key Context

- Gas Town and Beads are **Go projects** — if adding code examples, use Go conventions
- The upstream repos are under the `gastownhall` GitHub org (mirrors of `steveyegge/` repos)
- Steve Yegge's blog post documenting the v1.0 journey: https://steve-yegge.medium.com/gas-town-from-clown-show-to-v1-0-c239d9a407ec
- This repo belongs to GitHub user `homercsimpson50`

## When Updating Content

- Verify claims against the upstream repos before adding — architecture and APIs change frequently (both projects hit v1.0 on 2026-04-03)
- Gas Town's domain vocabulary is specific (Mayor, Polecats, Rigs, Convoys, etc.) — use terms consistently as defined in the upstream `docs/glossary.md`
- Beads has two storage modes (embedded/server) — distinguish between them when discussing Dolt integration
