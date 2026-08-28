import Foundation

actor GemService {
    private var cachedGemDir: String?

    func loadInstalledPackages() async throws -> [Package] {
        let gem    = try resolvedGem()
        let gemdir = try await resolvedGemDir(gem: gem)
        let output = try await ProcessRunner.run(gem, arguments: ["list", "--local"])
        return parse(output, gemdir: gemdir)
    }

    func uninstall(_ package: Package) async throws -> String {
        let gem = try resolvedGem()
        return try await ProcessRunner.run(gem, arguments: ["uninstall", package.name, "-x", "--force"])
    }

    func checkUpdates() async throws -> [String: String] {
        let gem = try resolvedGem()
        let output = try await ProcessRunner.run(gem, arguments: ["outdated"])
        // Format: "name (installed_version < latest_version)"
        var result: [String: String] = [:]
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let open = trimmed.firstIndex(of: "(") else { continue }
            let name = String(trimmed[..<open]).trimmingCharacters(in: .whitespaces)
            let inner = String(trimmed[open...].dropFirst().dropLast())
            if let ltRange = inner.range(of: " < ") {
                // Take only the version token — strip any trailing platform annotations
                // e.g. "8.0.1, ruby" → "8.0.1"
                let rawLatest = String(inner[ltRange.upperBound...])
                    .components(separatedBy: ",")
                    .first?
                    .trimmingCharacters(in: .whitespaces) ?? ""
                if !rawLatest.isEmpty {
                    result[name.lowercased()] = rawLatest
                }
            }
        }
        return result
    }

    // `gem list --local` format:
    //   actioncable (7.1.3.2)
    //   bigdecimal (3.1.7, 3.1.4)   ← multiple versions, take first
    private func parse(_ output: String, gemdir: String) -> [Package] {
        var result: [Package] = []
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let parenOpen = trimmed.firstIndex(of: "(") else { continue }
            let name    = trimmed[..<parenOpen].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }

            let rest = trimmed[parenOpen...]
            var version = String(
                rest.dropFirst()                      // drop "("
                    .components(separatedBy: ",")
                    .first?
                    .trimmingCharacters(in: .whitespaces) ?? "unknown"
            )
            // Strip trailing ")" left over for single-version gems: "1.0.0)"
            if version.hasSuffix(")") { version = String(version.dropLast()).trimmingCharacters(in: .whitespaces) }
            // Strip "default: " prefix for system gems: "default: 1.0.0" → "1.0.0"
            if version.hasPrefix("default: ") { version = String(version.dropFirst(9)) }

            result.append(Package(
                id: "gem-\(name)",
                name: name,
                version: version,
                description: "",
                source: .gem,
                installedDate: nil,
                installedOnRequest: true,
                dependencies: [],
                isOrphan: true,
                sizeBytes: nil,
                homepage: URL(string: "https://rubygems.org/gems/\(name)"),
                installPath: "\(gemdir)/gems/\(name)-\(version)"
            ))
        }
        return result.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private func resolvedGemDir(gem: String) async throws -> String {
        if let cached = cachedGemDir { return cached }
        let output = try await ProcessRunner.run(gem, arguments: ["environment", "gemdir"])
        let dir    = output.trimmingCharacters(in: .whitespacesAndNewlines)
        cachedGemDir = dir
        return dir
    }

    private func resolvedGem() throws -> String {
        let candidates = [
            "/opt/homebrew/bin/gem",
            "/usr/local/bin/gem",
            "/usr/bin/gem"
        ]
        guard let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw ProcessError.notFound(command: "gem")
        }
        return found
    }
}
