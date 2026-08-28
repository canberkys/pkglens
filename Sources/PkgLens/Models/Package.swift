import Foundation

struct Package: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let version: String
    let description: String
    let source: PackageSource
    let installedDate: Date?
    let installedOnRequest: Bool
    let dependencies: [String]
    let isOrphan: Bool
    let sizeBytes: Int?
    let homepage: URL?
    var latestVersion: String? = nil
    var installPath: String? = nil

    var displaySize: String? {
        guard let bytes = sizeBytes else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    // Safe to remove = only meaningful for Homebrew where brew leaves gives reliable dependency data.
    // npm/pip/cargo global packages have no inter-package dependency tracking — all appear orphaned,
    // so the banner would fire on every actively-used global tool, which is misleading.
    var isSafeToRemove: Bool { source == .brewFormula && isOrphan && installedOnRequest }

    // Stale = orphan + installed more than 90 days ago without being touched since
    var isStale: Bool {
        guard isOrphan, let date = installedDate else { return false }
        return Date().timeIntervalSince(date) > 90 * 86400
    }

    var daysSinceInstall: Int? {
        guard let date = installedDate else { return nil }
        return Calendar.current.dateComponents([.day], from: date, to: Date()).day
    }

    var isOutdated: Bool {
        guard let latest = latestVersion, !latest.isEmpty else { return false }
        return latest != version
    }
}
