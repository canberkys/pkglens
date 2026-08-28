import SwiftUI
import AppKit

struct PackageDetailView: View {
    let package: Package
    @EnvironmentObject private var vm: PackagesViewModel
    @State private var showUninstallConfirm = false
    @State private var isUninstalling = false
    @State private var isUpgrading = false
    @State private var uninstallError: String?
    @State private var noteText = ""
    @State private var calculatedSize: String? = nil
    @State private var isCalculatingSize = false
    @State private var usedByList: [String] = []
    @State private var lastUsedDate: Date? = nil
    @State private var changelogEntries: [ChangelogEntry] = []
    @State private var isLoadingChangelog = false
    @State private var isCheckingVersion = false
    @State private var upgradeError: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // ── Full-width top: header + banners ──────────────────────────
            VStack(alignment: .leading, spacing: 0) {
                HeaderSection(
                    package: package,
                    isCheckingVersion: isCheckingVersion,
                    isUninstalling: isUninstalling,
                    onCheckVersion: { Task { await performCheckVersion() } },
                    onUninstall: { showUninstallConfirm = true }
                )
                .padding(24)

                if let result = vm.lastUpgradeResult {
                    UpgradeResultBanner(message: result) { vm.lastUpgradeResult = nil }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                } else if package.isOutdated, let latest = package.latestVersion {
                    UpdateAvailableBanner(
                        package: package,
                        latestVersion: latest,
                        isUpgrading: isUpgrading
                    ) {
                        Task { await performUpgrade() }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                } else if package.isSafeToRemove {
                    SafeToRemoveBanner()
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                } else if !package.dependencies.isEmpty {
                    DependencyWarningBanner(count: package.dependencies.count)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            // ── Two-column body ───────────────────────────────────────────
            HStack(alignment: .top, spacing: 0) {
                // Left: meta + notes
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        MetaSection(package: package, lastUsedDate: lastUsedDate)
                        Divider()
                        NotesSection(noteText: $noteText) {
                            Task { await vm.setNote(noteText, for: package) }
                        }
                        if package.isOutdated {
                            Divider()
                            VersionHistorySection(
                                package: package,
                                entries: changelogEntries,
                                isLoading: isLoadingChangelog
                            )
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)

                Divider()

                // Right: path, needed by, dependencies
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let path = package.installPath {
                            PathSection(
                                path: path,
                                calculatedSize: calculatedSize,
                                isCalculatingSize: isCalculatingSize,
                                onReveal: {
                                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                                },
                                onCalculateSize: { Task { await calculateSize() } }
                            )
                        }
                        if !usedByList.isEmpty {
                            if package.installPath != nil { Divider() }
                            UsedBySection(packages: usedByList)
                        }
                        if !package.dependencies.isEmpty {
                            if package.installPath != nil || !usedByList.isEmpty { Divider() }
                            DependenciesSection(deps: package.dependencies)
                        }
                        if package.installPath == nil && usedByList.isEmpty && package.dependencies.isEmpty {
                            Text("No path or dependency information available.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showUninstallConfirm) {
            UninstallConfirmView(package: package) {
                showUninstallConfirm = false
                Task { await performUninstall() }
            } onCancel: {
                showUninstallConfirm = false
            }
        }
        .alert("Uninstall Failed", isPresented: Binding(
            get: { uninstallError != nil },
            set: { if !$0 { uninstallError = nil } }
        )) {
            Button("OK") { uninstallError = nil }
        } message: {
            Text(uninstallError ?? "")
        }
        .alert("Upgrade Failed", isPresented: Binding(
            get: { upgradeError != nil },
            set: { if !$0 { upgradeError = nil } }
        )) {
            Button("OK") { upgradeError = nil }
        } message: {
            Text(upgradeError ?? "")
        }
        .task(id: package.id) {
            noteText = vm.notes[package.id] ?? ""
            calculatedSize = nil
            usedByList     = []
            lastUsedDate   = nil
            if package.source == .brewFormula {
                async let used   = vm.brewUsedBy(package.name)
                async let luDate = vm.lastUsedDate(for: package)
                usedByList   = (try? await used) ?? []
                lastUsedDate = await luDate
            }
        }
        // Re-fetch changelog whenever latestVersion changes (i.e. after checkVersion).
        .task(id: package.latestVersion) {
            guard package.isOutdated else { changelogEntries = []; return }
            isLoadingChangelog = true
            // Run in a detached task so SwiftUI re-renders don't cancel the network fetch.
            changelogEntries = await Task.detached(priority: .userInitiated) {
                (try? await ChangelogFetcher.fetch(for: package)) ?? []
            }.value
            isLoadingChangelog = false
        }
    }

    private func calculateSize() async {
        guard let path = package.installPath, !isCalculatingSize else { return }
        isCalculatingSize = true
        let output = (try? await ProcessRunner.run("/usr/bin/du", arguments: ["-sh", path])) ?? ""
        let sizeStr = output.components(separatedBy: "\t").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        calculatedSize = sizeStr.isEmpty ? nil : sizeStr
        isCalculatingSize = false
    }

    private func performUninstall() async {
        isUninstalling = true
        do {
            try await vm.uninstall(package)
        } catch {
            uninstallError = error.localizedDescription
        }
        isUninstalling = false
    }

    private func performCheckVersion() async {
        guard !isCheckingVersion else { return }
        isCheckingVersion = true
        await vm.checkVersion(for: package)
        isCheckingVersion = false
    }

    private func performUpgrade() async {
        isUpgrading = true
        upgradeError = nil
        do {
            _ = try await vm.upgrade(package)
        } catch {
            upgradeError = error.localizedDescription
        }
        isUpgrading = false
    }
}

// MARK: - Header

private struct HeaderSection: View {
    let package: Package
    let isCheckingVersion: Bool
    let isUninstalling: Bool
    let onCheckVersion: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: badge + action buttons
            HStack(alignment: .center, spacing: 8) {
                Label(package.source.displayName, systemImage: package.source.icon)
                    .font(.caption)
                    .foregroundStyle(package.source.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(package.source.color.opacity(0.1), in: Capsule())

                Spacer()

                if package.source != .cargo {
                    if isCheckingVersion {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(action: onCheckVersion) {
                            Label(
                                package.isOutdated ? "Re-check Version" : "Check Version",
                                systemImage: "arrow.clockwise.circle"
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if isUninstalling {
                    ProgressView().controlSize(.small)
                } else {
                    Button(role: .destructive, action: onUninstall) {
                        Label("Uninstall", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(package.name)
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                    .fontDesign(.monospaced)
                    .textSelection(.enabled)

                Text(package.version)
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .fontDesign(.monospaced)
            }

            if !package.description.isEmpty {
                Text(package.description)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let url = package.homepage {
                Link(destination: url) {
                    Label("Homepage", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
        }
    }
}

// MARK: - Banners

private struct UpgradeResultBanner: View {
    let message: String
    let onDismiss: () -> Void

    private var firstLine: String { message.components(separatedBy: "\n").first ?? message }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(firstLine).fontWeight(.medium)
                Text("Reload to see the updated version.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Dismiss", action: onDismiss).buttonStyle(.bordered).controlSize(.small)
        }
        .padding(12)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.green.opacity(0.2)))
    }
}

private struct UpdateAvailableBanner: View {
    let package: Package
    let latestVersion: String
    let isUpgrading: Bool
    let onUpgrade: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Update available: \(latestVersion)")
                    .fontWeight(.medium)
                Text("A newer version is ready to install.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isUpgrading {
                ProgressView().controlSize(.small)
            } else {
                Button("Update", action: onUpgrade)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.blue.opacity(0.2)))
    }
}

// MARK: - Changelog entry model

struct ChangelogEntry: Identifiable {
    var id: String { version }
    let version: String
    let date: Date
    let body: String?       // first meaningful line from release notes; nil when not available
    let releaseURL: URL?    // link to GitHub release page; nil for registry-only sources
}

// MARK: - Version History (inline, left column)

private struct VersionHistorySection: View {
    let package: Package
    let entries: [ChangelogEntry]
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Version History", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let url = package.changelogURL {
                    Link(destination: url) {
                        Label("Registry ↗", systemImage: "arrow.up.right.square")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            if isLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text("Loading…").font(.caption).foregroundStyle(.secondary)
                }
            } else if entries.isEmpty {
                Text("Not available for this source.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(entries) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(item.version)
                                    .font(.caption)
                                    .fontDesign(.monospaced)
                                    .foregroundStyle(item.version == package.latestVersion ? Color.blue : .primary)
                                if item.version == package.latestVersion {
                                    Text("latest")
                                        .font(.caption2)
                                        .foregroundStyle(.blue)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(.blue.opacity(0.12), in: Capsule())
                                }
                                if item.version == package.version {
                                    Text("installed")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(.fill.secondary, in: Capsule())
                                }
                                Spacer()
                                HStack(spacing: 6) {
                                    Text(item.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    if let url = item.releaseURL {
                                        Link(destination: url) {
                                            Label("Release Notes", systemImage: "arrow.up.right.square")
                                                .labelStyle(.titleAndIcon)
                                                .font(.caption2)
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 2)
                                                .background(.blue.opacity(0.08), in: Capsule())
                                                .foregroundStyle(.blue.opacity(0.85))
                                        }
                                    }
                                }
                            }
                            if let body = item.body, !body.isEmpty {
                                Text(body)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 5)
                        if item.id != entries.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(10)
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private enum ChangelogFetcher {
    // Pre-release tag pattern — filter these out so only stable versions are shown.
    private static let preRelease = try! NSRegularExpression(
        pattern: #"-(dev|alpha|beta|rc|canary|next|nightly|pre)\b"#,
        options: .caseInsensitive
    )
    // Platform-specific npm distribution tags (e.g. "1.2.3-darwin-arm64") are not
    // useful to show — they represent the same release as the base "1.2.3" version.
    private static let platformDist = try! NSRegularExpression(
        pattern: #"-(darwin|linux|win32|freebsd|sunos|aix)-(x64|ia32|arm64|arm|s390x|ppc64|mips)\b"#,
        options: .caseInsensitive
    )

    static func fetch(for package: Package) async throws -> [ChangelogEntry] {
        switch package.source {
        case .npm:                    return try await npm(name: package.name)
        case .pip:                    return try await pip(name: package.name)
        case .gem:                    return try await gem(name: package.name)
        case .cargo:                  return try await cargo(name: package.name)
        case .brewFormula, .brewCask: return []
        }
    }

    // npm: try GitHub releases first (richer notes), fall back to `npm view time` dict.
    private static func npm(name: String) async throws -> [ChangelogEntry] {
        guard let npmPath = resolvedNpmPath() else { return [] }
        let binDir = URL(fileURLWithPath: npmPath).deletingLastPathComponent().path
        let env: [String: String] = [
            "PATH": "\(binDir):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path
        ]
        if let ghEntries = try? await npmGitHubReleases(name: name, npmPath: npmPath, env: env),
           !ghEntries.isEmpty {
            return ghEntries
        }
        return (try? await npmTimeFallback(name: name, npmPath: npmPath, env: env)) ?? []
    }

    // Fetches GitHub releases via npm registry → GitHub API chain.
    private static func npmGitHubReleases(
        name: String, npmPath: String, env: [String: String]
    ) async throws -> [ChangelogEntry] {
        // 1. Get repository URL from npm registry
        guard let repoOutput = try? await ProcessRunner.run(
            npmPath, arguments: ["view", name, "repository", "--json"],
            environment: env
        ), !repoOutput.isEmpty else { return [] }

        // 2. Extract github.com/owner/repo from any URL format
        let ghPattern = try! NSRegularExpression(
            pattern: #"github\.com[/:]([^/\"'\s\.]+)/([^/\"'\s\.]+)"#
        )
        guard let m = ghPattern.firstMatch(in: repoOutput, range: NSRange(repoOutput.startIndex..., in: repoOutput)),
              let ownerRange = Range(m.range(at: 1), in: repoOutput),
              let repoRange  = Range(m.range(at: 2), in: repoOutput)
        else { return [] }
        let owner = String(repoOutput[ownerRange])
        var repo  = String(repoOutput[repoRange])
        if repo.hasSuffix(".git") { repo = String(repo.dropLast(4)) }

        // 3. Fetch GitHub releases (unauthenticated — 60 req/hr per IP)
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases?per_page=50") else { return [] }
        var req = URLRequest(url: url)
        req.setValue("PkgLens/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 10
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let releases = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }

        // 4. Parse releases
        let iso = ISO8601DateFormatter()
        return releases.compactMap { rel -> ChangelogEntry? in
            guard rel["draft"]      as? Bool != true,
                  rel["prerelease"] as? Bool != true,
                  let tag          = rel["tag_name"]    as? String,
                  let publishedStr = rel["published_at"] as? String,
                  let date         = iso.date(from: publishedStr)
            else { return nil }

            // Strip common tag prefixes: "v1.2.3", "rust-v1.2.3", "cli-v1.2.3", etc.
            let ver: String
            if let range = tag.range(of: #"^[a-zA-Z]+-v|^v"#, options: .regularExpression) {
                ver = String(tag[range.upperBound...])
            } else {
                ver = tag
            }
            guard preRelease.firstMatch(in: ver, range: NSRange(ver.startIndex..., in: ver)) == nil else { return nil }

            // Extract first meaningful line from release body
            let body = (rel["body"] as? String).flatMap { raw -> String? in
                let candidate = raw.components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .first { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("<!--") && !$0.hasPrefix("---") }
                guard var line = candidate else { return nil }
                // Strip leading list bullets
                if line.hasPrefix("- ") || line.hasPrefix("* ") { line = String(line.dropFirst(2)) }
                return line.count > 120 ? String(line.prefix(120)) + "…" : line
            }
            let releaseURL = (rel["html_url"] as? String).flatMap { URL(string: $0) }
            return ChangelogEntry(version: ver, date: date, body: body, releaseURL: releaseURL)
        }
        .prefix(10)
        .map { $0 }
    }

    // Fallback: `npm view <name> time --json` — version→publish-date dict (~200 KB).
    private static func npmTimeFallback(
        name: String, npmPath: String, env: [String: String]
    ) async throws -> [ChangelogEntry] {
        let output = (try? await ProcessRunner.run(
            npmPath, arguments: ["view", name, "time", "--json"],
            environment: env
        )) ?? ""
        guard let data = output.data(using: .utf8),
              let time = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [] }
        let iso  = ISO8601DateFormatter()
        let skip = Set(["created", "modified"])
        return time
            .compactMap { ver, str -> ChangelogEntry? in
                guard !skip.contains(ver),
                      preRelease.firstMatch(in: ver, range: NSRange(ver.startIndex..., in: ver)) == nil,
                      platformDist.firstMatch(in: ver, range: NSRange(ver.startIndex..., in: ver)) == nil,
                      let d = iso.date(from: str) else { return nil }
                return ChangelogEntry(version: ver, date: d, body: nil, releaseURL: nil)
            }
            .sorted { $0.date > $1.date }
            .prefix(12)
            .map { $0 }
    }

    // pip: PyPI JSON API is small (package metadata only, no full package data).
    private static func pip(name: String) async throws -> [ChangelogEntry] {
        guard let url = URL(string: "https://pypi.org/pypi/\(name)/json") else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let releases = json["releases"] as? [String: [[String: Any]]]
        else { return [] }
        let iso = ISO8601DateFormatter()
        return releases
            .compactMap { ver, files -> ChangelogEntry? in
                guard preRelease.firstMatch(in: ver, range: NSRange(ver.startIndex..., in: ver)) == nil,
                      let str = files.first?["upload_time_iso_8601"] as? String,
                      let d = iso.date(from: str) else { return nil }
                return ChangelogEntry(version: ver, date: d, body: nil, releaseURL: nil)
            }
            .sorted { $0.date > $1.date }
            .prefix(12)
            .map { $0 }
    }

    // gem: RubyGems API returns compact version list (lightweight).
    private static func gem(name: String) async throws -> [ChangelogEntry] {
        guard let url = URL(string: "https://rubygems.org/api/v1/versions/\(name).json") else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        let iso = ISO8601DateFormatter()
        return arr
            .compactMap { item -> ChangelogEntry? in
                guard let ver = item["number"] as? String,
                      preRelease.firstMatch(in: ver, range: NSRange(ver.startIndex..., in: ver)) == nil,
                      let str = item["created_at"] as? String,
                      let d = iso.date(from: str) else { return nil }
                return ChangelogEntry(version: ver, date: d, body: nil, releaseURL: nil)
            }
            .prefix(12)
            .map { $0 }
    }

    // cargo: crates.io versions endpoint (compact).
    private static func cargo(name: String) async throws -> [ChangelogEntry] {
        guard let url = URL(string: "https://crates.io/api/v1/crates/\(name)/versions") else { return [] }
        var req = URLRequest(url: url)
        req.setValue("PkgLens/1.0 (macOS; contact: github.com/canberkys/pkglens)", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let versions = json["versions"] as? [[String: Any]]
        else { return [] }
        let iso = ISO8601DateFormatter()
        return versions
            .compactMap { item -> ChangelogEntry? in
                guard let ver = item["num"] as? String,
                      preRelease.firstMatch(in: ver, range: NSRange(ver.startIndex..., in: ver)) == nil,
                      let str = item["created_at"] as? String,
                      let d = iso.date(from: str) else { return nil }
                return ChangelogEntry(version: ver, date: d, body: nil, releaseURL: nil)
            }
            .prefix(12)
            .map { $0 }
    }

    // Scans nvm then static paths — no actor needed (synchronous filesystem check).
    private static func resolvedNpmPath() -> String? {
        let fm   = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let nvmDir = "\(home)/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmDir) {
            for v in versions.sorted(by: { $0.localizedStandardCompare($1) == .orderedDescending }) {
                let p = "\(nvmDir)/\(v)/bin/npm"
                if fm.isExecutableFile(atPath: p) { return p }
            }
        }
        for p in ["/opt/homebrew/bin/npm", "/usr/local/bin/npm", "/usr/bin/npm"] {
            if fm.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }
}

private struct SafeToRemoveBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Safe to remove")
                    .fontWeight(.medium)
                Text("No other package depends on this, and you installed it directly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.green.opacity(0.2)))
    }
}

private struct DependencyWarningBanner: View {
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Has \(count) \(count == 1 ? "dependency" : "dependencies")")
                    .fontWeight(.medium)
                Text("Other packages may depend on this. Brew will warn you before removing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.orange.opacity(0.2)))
    }
}

// MARK: - Path & Size

private struct PathSection: View {
    let path: String
    let calculatedSize: String?
    let isCalculatingSize: Bool
    let onReveal: () -> Void
    let onCalculateSize: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Install Path", systemImage: "folder")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 8) {
                Text(path)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                Spacer()
                Button("Reveal", action: onReveal)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }

            HStack(spacing: 8) {
                if let size = calculatedSize {
                    Label(size, systemImage: "internaldrive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isCalculatingSize {
                    ProgressView().controlSize(.mini)
                    Text("Calculating…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Calculate Size", action: onCalculateSize)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
            }
        }
    }
}

// MARK: - Used By

private struct UsedBySection: View {
    let packages: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Needed By (\(packages.count))", systemImage: "arrow.triangle.branch")
                .font(.headline)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 100, maximum: 220), spacing: 6)],
                spacing: 6
            ) {
                ForEach(packages, id: \.self) { dep in
                    Text(dep)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 5))
                }
            }
        }
    }
}

// MARK: - Meta

private struct MetaSection: View {
    let package: Package
    let lastUsedDate: Date?

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            MetaRow(label: "Source", value: package.source.displayName)
            MetaRow(label: "Version", value: package.version)

            if let date = package.installedDate {
                MetaRow(label: "Installed", value: date.formatted(date: .long, time: .omitted))
            }

            if let date = lastUsedDate {
                MetaRow(label: "Last Used", value: date.formatted(date: .long, time: .omitted))
            }

            if let size = package.displaySize {
                MetaRow(label: "Size", value: size)
            }

            MetaRow(
                label: "Origin",
                value: package.installedOnRequest ? "Installed directly" : "Installed as dependency"
            )

            MetaRow(
                label: "Orphan",
                value: package.isOrphan ? "Yes (nothing depends on it)" : "No"
            )
        }
    }
}

private struct MetaRow: View {
    let label: String
    let value: String

    var body: some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
                .fixedSize()
            Text(value)
                .fontDesign(.monospaced)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Dependencies

private struct DependenciesSection: View {
    let deps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dependencies (\(deps.count))")
                .font(.headline)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 100, maximum: 220), spacing: 6)],
                spacing: 6
            ) {
                ForEach(deps, id: \.self) { dep in
                    Text(dep)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 5))
                }
            }
        }
    }
}

// MARK: - Notes

private struct NotesSection: View {
    @Binding var noteText: String
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Note", systemImage: "bubble.left")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Why did you install this? (press Return to save)", text: $noteText)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
                .onSubmit { onSave() }
        }
    }
}

