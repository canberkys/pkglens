# Changelog

All notable changes to PkgLens are documented here.  
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

---

## [1.0.3] — 2026-09-02

### Changed

- Signed and notarized with Apple Developer ID — no more Gatekeeper warning on first launch
- Version bump to reflect official distribution status

---

## [1.0.2] — 2026-08-28

### Added

- **Dashboard strip** — four tappable stat tiles (Total, Updates, New, Orphans) at the top of the sidebar; each navigates to the matching filter
- **Collections** — group packages into named collections with custom SF Symbol icons and colors; persisted to `~/.pkglens/collections.json`
- **Inline changelog** — per-package version history fetched from GitHub Releases or registry APIs (npm time dict fallback); pre-release and platform-specific versions filtered out; "Release Notes" link per entry
- **Recently Added filter** — "New" tile and sidebar filter show packages installed in the last 7 days
- **Upgrade All extended** — bulk upgrade now covers pip, gem, and Cargo in addition to Homebrew and npm

### Changed

- Sort picker moved above the package list for contextual placement; removed from window toolbar
- ⌘F toggles search field on/off (previously only activated it); switching sidebar filters clears search text automatically
- Left color stripe removed from package rows for a cleaner look
- Version history entries show a "Release Notes" capsule button linking to the release URL when available

### Fixed

- npm changelog fetcher now uses GitHub Releases API (`per_page=50`) and falls back to npm time dict; platform-specific version strings (e.g. `0.150.1-win32-arm64`) are filtered before display
- Collection creation sheet no longer opens and closes multiple times when adding a new collection
- Upgrade All was previously limited to Homebrew and npm; all sources now supported

---

## [1.0.1] — 2026-08-28

### Fixed

- npm `upgrade` command now passes the node bin directory in `PATH` so `npm install -g` targets the correct runtime prefix instead of falling back to the system npm

---

## [1.0.0] — 2026-08-28

### Added

**Package scanning**
- Homebrew formula scanning via `brew info --json=v2 --installed` + `brew leaves`
- Homebrew cask scanning with install timestamps
- npm global package scanning (nvm-aware — reads filesystem directly, bypasses PATH conflicts)
- pip package scanning via `pip list --format=json --not-required` (falls back to full list on older pip)
- Cargo installed binary scanning via `cargo install --list`
- RubyGems scanning via `gem list --local`

**Package detail**
- Two-column detail layout: metadata left, path/dependencies right
- Install path display with Reveal in Finder button
- Lazy disk-size calculation (`du -sh`) on demand
- "Needed By" section — Homebrew reverse dependency lookup via `brew uses --installed`
- Per-package notes (persisted to `~/.pkglens/notes.json`)
- Homepage link

**Update detection**
- Parallel update check: Homebrew (`brew outdated --json`), npm (`npm outdated -g --json`), pip (`pip list --outdated --format=json`), gem (`gem outdated`)
- Outdated badge (↑) in list rows
- Update-available banner in detail view with one-click upgrade (Homebrew + npm)
- Toolbar button shows update count when updates are found

**Uninstall & history**
- One-click uninstall for all supported package managers
- Uninstall confirmation sheet with command preview
- Bulk orphan removal (Homebrew formula only, with confirmation)
- Uninstall history persisted to `~/.pkglens/history.json`
- "Recent Removals" section in sidebar (last 5)

**Filtering & navigation**
- Sidebar source filter (All / per-manager)
- Orphans-only toggle (Homebrew only — derived from `brew leaves`)
- Stale packages toggle (orphan + not updated in 90+ days)
- Full-text search across name and description
- Sort: Name A→Z, Name Z→A, Newest First, By Source
- Active-filter empty state with "Clear Filters" button

**Menu bar**
- Package count badge in menu bar icon
- Clickable stats: opens app with matching filter applied
- Refresh action from menu bar
- Keyboard shortcut ⌘Q to quit

**Export**
- Markdown export (table per package manager)
- JSON export (structured, sorted keys)

**Other**
- Right-click context menu on list rows: Copy Name, Copy Version, Reveal in Finder, Uninstall
- Settings window (About + keyboard shortcuts reference)
- macOS 14 Sonoma minimum deployment target
- Swift 6 strict concurrency, all services as actors

### Technical

- `ProcessRunner` with `readabilityHandler` + `DispatchGroup` to handle large subprocess output (brew JSON > 64 KB pipe limit)
- `SourceFilter` enum replacing `Optional<PackageSource>` to fix SwiftUI List nil-tag selection bug
- `openWindow(id: "main")` for menu-bar → window restoration
- Atomic file writes for history and notes stores
- Per-source update-version matching to prevent cross-manager name collisions

---

[1.0.2]: https://github.com/canberkys/pkglens/releases/tag/v1.0.2
[1.0.1]: https://github.com/canberkys/pkglens/releases/tag/v1.0.1
[1.0.0]: https://github.com/canberkys/pkglens/releases/tag/v1.0.0
