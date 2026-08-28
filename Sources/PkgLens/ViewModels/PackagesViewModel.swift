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
    case collection(UUID)
    case recent   // installed in the last 7 days
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
    @Published var lastUpgradeResult: String? = nil   // persists across detail view re-renders
    @Published var notes: [String: String] = [:]
    @Published var recentRemovals: [HistoryStore.Entry] = []
    @Published var collections: [PackageCollection] = []

    private let brew            = BrewService()
    private let npm             = NpmService()
    private let pip             = PipService()
    private let cargo           = CargoService()
    private let gem             = GemService()
    private let history         = HistoryStore()
    private let notesStore      = NotesStore()
    private let collectionStore = CollectionStore()

    var filtered: [Package] {
        var result = packages.filter { pkg in
            let matchesSearch = searchText.isEmpty
                || pkg.name.localizedCaseInsensitiveContains(searchText)
                || pkg.description.localizedCaseInsensitiveContains(searchText)
            let matchesSource: Bool = {
                switch selectedFilter {
                case .all:                return true
                case .source(let s):      return pkg.source == s
                case .updates:            return pkg.isOutdated
                case .collection(let id): return collections.first { $0.id == id }?.packageIds.contains(pkg.id) ?? false
                case .recent:
                    guard let date = pkg.installedDate else { return false }
                    return Date().timeIntervalSince(date) <= 7 * 86400
                }
            }()
            // Orphan/stale toggles don't narrow the Updates, Collection, or Recent views.
            let matchesOrphan: Bool
            let matchesStale: Bool
            switch selectedFilter {
            case .updates, .collection, .recent:
                matchesOrphan = true
                matchesStale  = true
            default:
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

    var orphanCount: Int  { packages.filter(\.isOrphan).count }
    var staleCount: Int   { packages.filter(\.isStale).count }
    var recentCount: Int  { packages.filter { ($0.installedDate.map { Date().timeIntervalSince($0) <= 7 * 86400 }) ?? false }.count }
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

        // Restore persisted notes, history, and collections
        let allNotes = await notesStore.allNotes()
        notes        = allNotes
        recentRemovals = await history.recent()
        collections    = await collectionStore.load()
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

    func upgrade(_ package: Package) async throws -> String {
        let output: String
        do {
            switch package.source {
            case .brewFormula:
                output = try await ProcessRunner.run("brew", arguments: ["upgrade", package.name])
            case .brewCask:
                output = try await ProcessRunner.run("brew", arguments: ["upgrade", "--cask", package.name])
            case .npm:
                output = try await npm.upgrade(package)
            case .pip:
                output = try await pip.upgrade(package)
            case .gem:
                output = try await gem.upgrade(package)
            case .cargo:
                output = try await cargo.upgrade(package)
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
        lastUpgradeResult = output   // store AFTER loadAll so the detail view is alive
        return output
    }

    // MARK: - Collections

    func addCollection(name: String, icon: String = "star.fill", colorName: String = "orange") async {
        let col = PackageCollection(name: name, icon: icon, colorName: colorName)
        collections.append(col)
        await collectionStore.save(collections)
    }

    func updateCollectionAppearance(id: UUID, icon: String, colorName: String) async {
        guard let idx = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[idx].icon      = icon
        collections[idx].colorName = colorName
        await collectionStore.save(collections)
    }

    func deleteCollection(id: UUID) async {
        collections.removeAll { $0.id == id }
        if case .collection(let sel) = selectedFilter, sel == id { selectedFilter = .all }
        await collectionStore.save(collections)
    }

    func renameCollection(id: UUID, to name: String) async {
        guard let idx = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[idx].name = name
        await collectionStore.save(collections)
    }

    func togglePackage(_ packageId: String, in collectionId: UUID) async {
        guard let idx = collections.firstIndex(where: { $0.id == collectionId }) else { return }
        if collections[idx].packageIds.contains(packageId) {
            collections[idx].packageIds.removeAll { $0 == packageId }
        } else {
            collections[idx].packageIds.append(packageId)
        }
        await collectionStore.save(collections)
    }

    func isPackage(_ packageId: String, inCollection collectionId: UUID) -> Bool {
        collections.first { $0.id == collectionId }?.packageIds.contains(packageId) ?? false
    }

    func isPackageInAnyCollection(_ packageId: String) -> Bool {
        collections.contains { $0.packageIds.contains(packageId) }
    }

    func collectionCount(for id: UUID) -> Int {
        guard let col = collections.first(where: { $0.id == id }) else { return 0 }
        return packages.filter { col.packageIds.contains($0.id) }.count
    }

    // MARK: - Last Used (Brew only, via Spotlight)

    func lastUsedDate(for package: Package) async -> Date? {
        guard package.source == .brewFormula else { return nil }
        return await brew.lastUsedDate(for: package)
    }

    // MARK: - Bulk Upgrade

    var upgradeAllEligible: [Package] {
        packages.filter(\.isOutdated)
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
                case .npm:   _ = try await npm.upgrade(pkg)
                case .pip:   _ = try await pip.upgrade(pkg)
                case .gem:   _ = try await gem.upgrade(pkg)
                case .cargo: _ = try await cargo.upgrade(pkg)
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

    func exportBrewfile() -> String {
        var lines = ["# Generated by PkgLens on \(Date().formatted(date: .abbreviated, time: .omitted))", ""]
        let formulae = packages.filter { $0.source == .brewFormula }
        let casks    = packages.filter { $0.source == .brewCask }
        if !formulae.isEmpty {
            lines.append("# Formulae")
            for p in formulae { lines.append("brew \"\(p.name)\"") }
            lines.append("")
        }
        if !casks.isEmpty {
            lines.append("# Casks")
            for p in casks { lines.append("cask \"\(p.name)\"") }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

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
