import SwiftUI

enum SortOrder: String, CaseIterable {
    case nameAsc   = "Name A→Z"
    case nameDesc  = "Name Z→A"
    case dateDesc  = "Newest First"
    case source    = "By Source"
}

// Wrapping source selection in a non-optional enum avoids the SwiftUI List
// bug where .tag(nil) items are never highlighted or re-selectable.
enum SourceFilter: Hashable, Sendable {
    case all
    case source(PackageSource)
    case updates
}

@MainActor
final class PackagesViewModel: ObservableObject {
    @Published var packages: [Package] = []
    @Published var isLoading = false
    @Published var loadingStatus = ""
    @Published var errors: [String] = []
    @Published var searchText = ""
    @Published var selectedFilter: SourceFilter = .all
    @Published var showOrphansOnly = false
    @Published var showStaleOnly   = false
    @Published var sortOrder: SortOrder = .nameAsc
    @Published var isCheckingUpdates = false
    @Published var updateCount = 0
    @Published var notes: [String: String] = [:]
    @Published var recentRemovals: [HistoryStore.Entry] = []

    private let brew      = BrewService()
    private let npm       = NpmService()
    private let pip       = PipService()
    private let cargo     = CargoService()
    private let gem       = GemService()
    private let history   = HistoryStore()
    private let notesStore = NotesStore()

    var filtered: [Package] {
        var result = packages.filter { pkg in
            let matchesSearch = searchText.isEmpty
                || pkg.name.localizedCaseInsensitiveContains(searchText)
                || pkg.description.localizedCaseInsensitiveContains(searchText)
            let matchesSource: Bool = {
                switch selectedFilter {
                case .all:            return true
                case .source(let s): return pkg.source == s
                case .updates:        return pkg.isOutdated
                }
            }()
            // Orphan/stale toggles don't narrow the Updates view — you want all
            // outdated packages regardless of those quick filters.
            let matchesOrphan: Bool
            let matchesStale: Bool
            if case .updates = selectedFilter {
                matchesOrphan = true
                matchesStale  = true
            } else {
                matchesOrphan = !showOrphansOnly || pkg.isOrphan
                matchesStale  = !showStaleOnly   || pkg.isStale
            }
            return matchesSearch && matchesSource && matchesOrphan && matchesStale
        }

        switch sortOrder {
        case .nameAsc:  result.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .nameDesc: result.sort { $0.name.localizedCompare($1.name) == .orderedDescending }
        case .dateDesc: result.sort {
            switch ($0.installedDate, $1.installedDate) {
            case (let a?, let b?): return a > b
            case (nil, _):         return false
            case (_, nil):         return true
            }
        }
        case .source: result.sort {
            $0.source.rawValue == $1.source.rawValue
                ? $0.name.localizedCompare($1.name) == .orderedAscending
                : $0.source.rawValue < $1.source.rawValue
        }
        }
        return result
    }

    var orphanCount: Int { packages.filter(\.isOrphan).count }
    var staleCount: Int  { packages.filter(\.isStale).count }
    func count(for source: PackageSource) -> Int { packages.filter { $0.source == source }.count }

    // MARK: - Load

    func loadAll() async {
        isLoading     = true
        loadingStatus = "Scanning packages…"
        errors        = []
        await brew.invalidateCache()

        async let brewPkgs  = load(label: "Homebrew") { try await self.brew.loadAll() }
        async let npmPkgs   = load(label: "npm")      { try await self.npm.loadInstalledPackages() }
        async let pipPkgs   = load(label: "pip")      { try await self.pip.loadInstalledPackages() }
        async let cargoPkgs = load(label: "Cargo")    { try await self.cargo.loadInstalledPackages() }
        async let gemPkgs   = load(label: "RubyGems") { try await self.gem.loadInstalledPackages() }

        let all = await brewPkgs + npmPkgs + pipPkgs + cargoPkgs + gemPkgs
        packages      = all.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        loadingStatus = ""
        isLoading     = false

        // Restore persisted notes and history on first load
        let allNotes = await notesStore.allNotes()
        notes = allNotes
        recentRemovals = await history.recent()
    }

    // MARK: - Update Detection

    func checkForUpdates() async {
        isCheckingUpdates = true
        async let brewUpdates = (try? await brew.checkUpdates()) ?? [:]
        async let npmUpdates  = (try? await npm.checkUpdates())  ?? [:]
        async let pipUpdates  = (try? await pip.checkUpdates())  ?? [:]
        async let gemUpdates  = (try? await gem.checkUpdates())  ?? [:]
        let (b, n, p2, g) = await (brewUpdates, npmUpdates, pipUpdates, gemUpdates)

        // Apply updates per-source to avoid cross-source name collisions
        // (e.g. a brew formula and a pip package both named "git").
        packages = packages.map { pkg in
            var p = pkg
            let key = pkg.name.lowercased()
            switch pkg.source {
            case .brewFormula, .brewCask:
                // brew checkUpdates keys by exact name (not lowercased), so try both.
                p.latestVersion = b[pkg.name] ?? b[key]
            case .npm:
                p.latestVersion = n[key]
            case .pip:
                p.latestVersion = p2[key]
            case .gem:
                p.latestVersion = g[key]
            case .cargo:
                break  // cargo has no checkUpdates yet
            }
            return p
        }
        updateCount       = packages.filter(\.isOutdated).count
        isCheckingUpdates = false
    }

    // MARK: - Per-package version check

    func checkVersion(for package: Package) async {
        var latest: String? = nil
        let key = package.name.lowercased()
        switch package.source {
        case .brewFormula, .brewCask:
            let updates = (try? await brew.checkUpdates()) ?? [:]
            latest = updates[package.name] ?? updates[key]
        case .npm:
            let updates = (try? await npm.checkUpdates()) ?? [:]
            latest = updates[key]
        case .pip:
            let updates = (try? await pip.checkUpdates()) ?? [:]
            latest = updates[key]
        case .gem:
            let updates = (try? await gem.checkUpdates()) ?? [:]
            latest = updates[key]
        case .cargo:
            return
        }
        if let idx = packages.firstIndex(where: { $0.id == package.id }) {
            packages[idx].latestVersion = latest
        }
        updateCount = packages.filter(\.isOutdated).count
    }

    // MARK: - Uninstall

    func uninstall(_ package: Package) async throws {
        switch package.source {
        case .brewFormula, .brewCask:
            _ = try await brew.uninstall(package)
        case .npm:
            _ = try await npm.uninstall(package)
        case .pip:
            _ = try await pip.uninstall(package)
        case .cargo:
            _ = try await cargo.uninstall(package)
        case .gem:
            _ = try await gem.uninstall(package)
        }
        await history.append(package: package)
        packages.removeAll { $0.id == package.id }
        recentRemovals = await history.recent()
    }

    // MARK: - Upgrade

    func upgrade(_ package: Package) async throws {
        do {
            switch package.source {
            case .brewFormula:
                _ = try await ProcessRunner.run("brew", arguments: ["upgrade", package.name])
            case .brewCask:
                _ = try await ProcessRunner.run("brew", arguments: ["upgrade", "--cask", package.name])
            case .npm:
                let npmPath = (try? await npm.resolvedPath()) ?? "npm"
                _ = try await ProcessRunner.run(npmPath, arguments: ["install", "-g", package.name])
            case .pip:
                throw ProcessError.failed(status: 1, stderr: "pip upgrade is not supported in-app. Run: pip install --upgrade \(package.name)")
            case .gem:
                throw ProcessError.failed(status: 1, stderr: "gem upgrade is not supported in-app. Run: gem update \(package.name)")
            case .cargo:
                throw ProcessError.failed(status: 1, stderr: "cargo upgrade is not supported in-app. Run: cargo install \(package.name)")
            }
        } catch {
            // Always reload so the UI reflects the current on-disk state, then rethrow.
            await brew.invalidateCache()
            await loadAll()
            throw error
        }
        // Reload to pick up the new version on success.
        await brew.invalidateCache()
        await loadAll()
    }

    // MARK: - Bulk Upgrade

    var upgradeAllEligible: [Package] {
        packages.filter {
            $0.isOutdated && ($0.source == .brewFormula || $0.source == .brewCask || $0.source == .npm)
        }
    }

    func upgradeAll() async {
        let targets = upgradeAllEligible
        guard !targets.isEmpty else { return }
        isLoading     = true
        loadingStatus = "Upgrading packages…"
        for pkg in targets {
            do {
                switch pkg.source {
                case .brewFormula:
                    _ = try await ProcessRunner.run("brew", arguments: ["upgrade", pkg.name])
                case .brewCask:
                    _ = try await ProcessRunner.run("brew", arguments: ["upgrade", "--cask", pkg.name])
                case .npm:
                    let path = (try? await npm.resolvedPath()) ?? "npm"
                    _ = try await ProcessRunner.run(path, arguments: ["install", "-g", pkg.name])
                default:
                    break
                }
            } catch {
                errors.append("\(pkg.name): \(error.localizedDescription)")
            }
        }
        await brew.invalidateCache()
        await loadAll()
    }

    // MARK: - Bulk Remove Orphans

    var orphansToRemove: [Package] {
        packages.filter(\.isSafeToRemove)
    }

    func removeAllOrphans() async {
        let targets = orphansToRemove
        isLoading     = true
        loadingStatus = "Removing orphans…"
        for pkg in targets {
            do { try await uninstall(pkg) }
            catch { errors.append("\(pkg.name): \(error.localizedDescription)") }
        }
        isLoading     = false
        loadingStatus = ""
    }

    // MARK: - Brew Reverse Dependencies

    func brewUsedBy(_ name: String) async throws -> [String] {
        try await brew.usedBy(name)
    }

    // MARK: - Notes

    func setNote(_ text: String, for package: Package) async {
        await notesStore.setNote(text, for: package.id)
        notes[package.id] = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    // MARK: - Export

    func exportMarkdown() -> String {
        var lines = ["# PkgLens Export", "", "Generated: \(Date().formatted())", ""]
        for source in PackageSource.allCases {
            let pkgs = packages.filter { $0.source == source }
            guard !pkgs.isEmpty else { continue }
            lines.append("## \(source.displayName) (\(pkgs.count))")
            lines.append("")
            lines.append("| Package | Version | Description |")
            lines.append("|---------|---------|-------------|")
            for p in pkgs {
                let desc = p.description.isEmpty ? "—" : p.description
                lines.append("| `\(p.name)` | \(p.version) | \(desc) |")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    func exportJSON() throws -> Data {
        let items = packages.map { p -> [String: String] in
            var d: [String: String] = [
                "name": p.name,
                "version": p.version,
                "source": p.source.rawValue,
                "description": p.description
            ]
            if let url = p.homepage { d["homepage"] = url.absoluteString }
            if let date = p.installedDate { d["installedDate"] = date.ISO8601Format() }
            return d
        }
        return try JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: - Private

    private func load(
        label: String,
        fetch: @escaping @Sendable () async throws -> [Package]
    ) async -> [Package] {
        await MainActor.run { self.loadingStatus = "Loading \(label)…" }
        do {
            return try await fetch()
        } catch ProcessError.notFound {
            return []
        } catch {
            await MainActor.run { self.errors.append("\(label): \(error.localizedDescription)") }
            return []
        }
    }
}
