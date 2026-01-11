# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
# Full dev loop: kill old instances, build, test, package, relaunch
./Scripts/compile_and_run.sh

# Quick build (debug)
swift build

# Release build
swift build -c release

# Run tests
swift test

# Package app bundle locally
./Scripts/package_app.sh
# Ad-hoc signing (no Apple Developer account):
CODEXBAR_SIGNING=adhoc ./Scripts/package_app.sh

# Launch existing app (no rebuild)
./Scripts/launch.sh

# Format and lint (run before commits)
swiftformat Sources Tests
swiftlint --strict
```

## Architecture

### Module Structure

- **TokenStatsCore**: Fetch + parse logic (provider probes, RPC, PTY runners, web scraping, status polling). Shared by app, CLI, and widget.
- **TokenStats**: SwiftUI/AppKit menu bar app (UsageStore, SettingsStore, StatusItemController, icon rendering, preferences UI).
- **TokenStatsCLI**: Bundled CLI (`tokenstats`) for scripting and CI usage/status output.
- **TokenStatsWidget**: WidgetKit extension wired to shared snapshot.
- **TokenStatsMacros** / **TokenStatsMacroSupport**: SwiftSyntax macros for provider registration.
- **TokenStatsClaudeWatchdog**: Helper process for stable Claude CLI PTY sessions.

### Entry Points

- `TokenStatsApp.swift`: SwiftUI app with keepalive + Settings scene.
- `AppDelegate`: Wires StatusItemController, Sparkle updater, notifications.

### Data Flow

Background refresh → `UsageFetcher`/provider probes → `UsageStore` → menu/icon/widgets.
Settings toggles feed `SettingsStore` → `UsageStore` refresh cadence + feature flags.

### Provider Pattern

Providers live in `Sources/TokenStats/Providers/<ProviderName>/`:
- `*ProviderImplementation.swift`: Implements `ProviderImplementation` protocol
- `*LoginFlow.swift`: Optional auth flow UI

Provider core logic (fetchers, parsers) lives in `Sources/TokenStatsCore/Providers/`.

## Code Style

- Swift 6 strict concurrency enabled; prefer Sendable state and explicit MainActor hops.
- 4-space indent, 120-char line limit.
- Explicit `self` is intentional—do not remove.
- Use `@Observable` models with `@State` ownership and `@Bindable` in views; avoid `ObservableObject`/`@StateObject`.
- Maintain existing `// MARK:` organization.
- macOS 14+ targeting; favor modern macOS 15+ APIs when refactoring.

## Testing

- Tests in `Tests/TokenStatsTests/*Tests.swift` follow `FeatureNameTests` naming with `test_caseDescription` methods.
- Add fixtures for new parsing/formatting scenarios.
- Always run `swift test` before handoff.

## Provider Data Isolation

Keep provider data siloed: when rendering usage or account info for a provider (Claude vs Codex), never display identity/plan fields sourced from a different provider.

## Relaunch After Edits

After code changes affecting the app, rebuild and restart to avoid running stale binaries:
```bash
./Scripts/compile_and_run.sh
```

## Release Process

See `docs/RELEASING.md`. Key scripts:
- `./Scripts/sign-and-notarize.sh` – build, sign, notarize universal binary
- `./Scripts/make_appcast.sh` – generate Sparkle feed

Release script should run in foreground (don't background it).
