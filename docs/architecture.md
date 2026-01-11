---
summary: "Architecture overview: modules, entry points, and data flow."
read_when:
  - Reviewing architecture before feature work
  - Refactoring app structure, app lifecycle, or module boundaries
---

# Architecture overview

## Modules
- `Sources/TokenStatsCore`: fetch + parse (Codex RPC, PTY runner, Claude probes, OpenAI web scraping, status polling).
- `Sources/TokenStats`: state + UI (UsageStore, SettingsStore, StatusItemController, menus, icon rendering).
- `Sources/TokenStatsWidget`: WidgetKit extension wired to the shared snapshot.
- `Sources/TokenStatsCLI`: bundled CLI for `tokenstats` usage/status output.
- `Sources/TokenStatsMacros`: SwiftSyntax macros for provider registration.
- `Sources/TokenStatsMacroSupport`: shared macro support used by app/core/CLI targets.
- `Sources/TokenStatsClaudeWatchdog`: helper process for stable Claude CLI PTY sessions.
- `Sources/TokenStatsClaudeWebProbe`: CLI helper to diagnose Claude web fetches.

## Entry points
- `TokenStatsApp`: SwiftUI keepalive + Settings scene.
- `AppDelegate`: wires status controller, Sparkle updater, notifications.

## Data flow
- Background refresh → `UsageFetcher`/provider probes → `UsageStore` → menu/icon/widgets.
- Settings toggles feed `SettingsStore` → `UsageStore` refresh cadence + feature flags.

## Concurrency & platform
- Swift 6 strict concurrency enabled; prefer Sendable state and explicit MainActor hops.
- macOS 14+ targeting; avoid deprecated APIs when refactoring.

See also: `docs/providers.md`, `docs/refresh-loop.md`, `docs/ui.md`.
