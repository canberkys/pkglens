import Foundation

actor CargoService {
    func loadInstalledPackages() async throws -> [Package] {
        let cargo = try resolvedCargo()
        let output = try await ProcessRunner.run(cargo, arguments: ["install", "--list"])
        return parse(output)
    }

    func uninstall(_ package: Package) async throws -> String {
        let cargo = try resolvedCargo()
        return try await ProcessRunner.run(cargo, arguments: ["uninstall", package.name])
    }

    // Parses `cargo install --list` output:
    //   bat v0.25.0:
    //       bat
    //   ripgrep v14.1.1:
    //       rg
    //   cargo-nextest v0.9.72:
    //       cargo-nextest    ← multi-binary crate: header defines one Package, binaries are ignored
    //       nextest
    private func parse(_ output: String) -> [Package] {
        var result: [Package] = []
        let cargoHome = FileManager.default.homeDirectoryForCurrentUser.path

        for line in output.components(separatedBy: "\n") {
            if line.isEmpty { continue }
            // Header line starts with a non-whitespace character: "<name> v<version>[...]:".
            // Binary lines are indented — skip them to avoid duplicate entries for multi-binary crates.
            guard line.first?.isWhitespace == false else { continue }

            let parts = line.components(separatedBy: " ")
            guard parts.count >= 2 else { continue }

            let name    = parts[0]
            let rawVer  = parts[1].hasPrefix("v") ? String(parts[1].dropFirst()) : parts[1]
            let version = rawVer.hasSuffix(":") ? String(rawVer.dropLast()) : rawVer

            let desc = readCargoTomlDescription(package: name, version: version)
            let home = URL(string: "https://crates.io/crates/\(name)")
            result.append(Package(
                id: "cargo-\(name)",
                name: name,
                version: version,
                description: desc,
                source: .cargo,
                installedDate: nil,
                installedOnRequest: true,
                dependencies: [],
                isOrphan: true,
                sizeBytes: nil,
                homepage: home,
                installPath: "\(cargoHome)/.cargo/bin/\(name)"
            ))
        }
        return result.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    // Reads description from the cached Cargo.toml in ~/.cargo/registry/src.
    private func readCargoTomlDescription(package: String, version: String) -> String {
        let fm   = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let src  = "\(home)/.cargo/registry/src"

        guard let mirrors = try? fm.contentsOfDirectory(atPath: src) else { return "" }
        for mirror in mirrors {
            let toml = "\(src)/\(mirror)/\(package)-\(version)/Cargo.toml"
            if let content = try? String(contentsOfFile: toml, encoding: .utf8) {
                for line in content.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("description") {
                        // e.g. description = "A fast line-oriented regex search tool"
                        if let eq = trimmed.range(of: "=") {
                            let afterEq = trimmed[eq.upperBound...]
                                .trimmingCharacters(in: .whitespaces)
                            // Strip surrounding double-quotes; ignore any trailing TOML comment.
                            if afterEq.hasPrefix("\"") {
                                let inner = afterEq.dropFirst()
                                if let closeQuote = inner.firstIndex(of: "\"") {
                                    return String(inner[..<closeQuote])
                                }
                            }
                            // Fallback: strip quotes from both ends (handles unquoted or single-quoted values)
                            return afterEq.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                        }
                    }
                }
            }
        }
        return ""
    }

    private func resolvedCargo() throws -> String {
        let fm   = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.cargo/bin/cargo",
            "/opt/homebrew/bin/cargo",
            "/usr/local/bin/cargo"
        ]
        if let found = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) {
            return found
        }
        throw ProcessError.notFound(command: "cargo")
    }
}
