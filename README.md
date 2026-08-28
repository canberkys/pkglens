# PkgLens

A native macOS app for managing all your package managers in one place.

PkgLens scans Homebrew, npm, pip, Cargo, and RubyGems — shows you what each package does, flags orphans and stale installs, detects outdated versions, and lets you uninstall with one click.

---

## Features

| | |
|---|---|
| **6 package managers** | Homebrew (formula + cask), npm (nvm-aware), pip, Cargo, RubyGems |
| **Update detection** | Parallel check across all managers; badge + one-click upgrade |
| **Orphan detection** | Homebrew `brew leaves`-based; bulk removal with confirmation |
| **Stale packages** | Flags installs untouched for 90+ days |
| **Install path** | Shows exact location; Reveal in Finder; lazy disk-size calculation |
| **Reverse deps** | "Needed By" — shows which Homebrew packages depend on this one |
| **Notes** | Per-package notes, persisted locally |
| **Uninstall history** | Last 5 removals shown in sidebar; full log at `~/.pkglens/history.json` |
| **Export** | Markdown or JSON snapshot of all installed packages |
| **Menu bar** | Quick stats; click any number to open the app with that filter active |

---

## Requirements

- macOS 14 Sonoma or later
- Swift 6.0+ (for building from source)

The following package managers are **optional** — PkgLens simply skips any that aren't installed:

- [Homebrew](https://brew.sh)
- Node.js / npm (including [nvm](https://github.com/nvm-sh/nvm))
- Python 3 / pip
- [Rust](https://rustup.rs) / Cargo
- Ruby / gem (system or Homebrew)

---

## Installation

### Build from source

```bash
git clone https://github.com/canberkys/pkglens.git
cd pkglens
swift build -c release
open .build/release/PkgLens
```

Or open in Xcode:

```bash
open Package.swift
```

---

## Usage

**Scanning** — launches automatically on open; ⌘R to refresh.

**Filtering** — use the sidebar to filter by package manager, or enable Orphans / Stale toggles. The search bar matches name and description.

**Update check** — click "Check Updates" in the toolbar. Outdated packages get a blue ↑ badge. Click "Update" in the detail panel to upgrade (Homebrew + npm supported).

**Uninstall** — select a package, click Uninstall in the detail panel, or right-click a row in the list.

**Bulk remove** — enable the Orphans filter, then click "Remove All Orphans". Only Homebrew formula orphans are included (npm/pip/gem global installs are excluded — there is no reliable dependency graph for them).

**Notes** — type in the Note field in the detail panel and press Return. Notes survive app restarts and are stored at `~/.pkglens/notes.json`.

**Export** — toolbar → Export → choose Markdown or JSON → Save.

---

## Data stored locally

```
~/.pkglens/
  history.json   # uninstall log
  notes.json     # per-package notes
```

No data is ever sent to a network. No tracking. No telemetry.

---

## Architecture

```
Sources/PkgLens/
  App/            PkgLensApp.swift — entry point, menu bar
  Models/         Package, PackageSource
  Services/       BrewService, NpmService, PipService, CargoService,
                  GemService, HistoryStore, NotesStore, ProcessRunner
  ViewModels/     PackagesViewModel (@MainActor ObservableObject)
  Views/          MainView, PackageListView, PackageDetailView,
                  UninstallConfirmView, SettingsView
```

- Swift 6 strict concurrency; all services are `actor`-isolated
- `ProcessRunner` uses `readabilityHandler` + `DispatchGroup` to avoid the 64 KB pipe-buffer limit on large subprocess output (e.g. `brew info --json=v2`)
- SwiftPM — no Xcode project file required

---

## Contributing

Bug reports and pull requests are welcome. Please open an issue before large changes.

---

## License

MIT — see [LICENSE](LICENSE).
