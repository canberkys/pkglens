import Foundation

actor PipService {
    private struct PipPkg: Decodable { let name: String; let version: String }
    private struct PipShowInfo { let summary: String; let homepage: URL?; let location: String? }

    func loadInstalledPackages() async throws -> [Package] {
        let pip  = resolvedPip()
        // --not-required: show only top-level installs (available since pip 9.0).
        // Fall back to listing all packages if the flag is rejected by an older pip.
        let json: String
        do {
            json = try await ProcessRunner.run(pip, arguments: ["list", "--format=json", "--not-required"])
        } catch {
            json = try await ProcessRunner.run(pip, arguments: ["list", "--format=json"])
        }
        let pkgs = try JSONDecoder().decode([PipPkg].self, from: Data(json.utf8))
        let info = await loadDescriptions(for: pkgs.map(\.name), pip: pip)

        return pkgs.map { p in
            let show     = info[p.name.lowercased()]
            let location = show?.location
            let pkgPath  = location.map { "\($0)/\(p.name)" }
            let birthdate: Date? = pkgPath.flatMap {
                (try? FileManager.default.attributesOfItem(atPath: $0))?[.creationDate] as? Date
            }
            return Package(
                id: "pip-\(p.name)",
                name: p.name,
                version: p.version,
                description: show?.summary ?? "",
                source: .pip,
                installedDate: birthdate,
                installedOnRequest: true,
                dependencies: [],
                isOrphan: true,
                sizeBytes: nil,
                homepage: show?.homepage ?? URL(string: "https://pypi.org/project/\(p.name)/"),
                installPath: pkgPath
            )
        }
    }

    func upgrade(_ package: Package) async throws -> String {
        return try await ProcessRunner.run(resolvedPip(), arguments: ["install", "--upgrade", package.name])
    }

    func uninstall(_ package: Package) async throws -> String {
        return try await ProcessRunner.run(resolvedPip(), arguments: ["uninstall", "-y", package.name])
    }

    func checkUpdates() async throws -> [String: String] {
        let pip = resolvedPip()
        let output = try await ProcessRunner.run(pip, arguments: ["list", "--outdated", "--format=json"])
        guard let data = output.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [:] }
        var result: [String: String] = [:]
        for item in arr {
            if let name = item["name"] as? String, let latest = item["latest_version"] as? String {
                result[name.lowercased()] = latest
            }
        }
        return result
    }

    // Fetch pip show for all packages in one subprocess call.
    private func loadDescriptions(for names: [String], pip: String) async -> [String: PipShowInfo] {
        guard !names.isEmpty else { return [:] }
        let output = (try? await ProcessRunner.run(pip, arguments: ["show"] + names)) ?? ""
        return parsePipShow(output)
    }

    // Parses the `pip show` multi-package output (blocks separated by "---").
    private func parsePipShow(_ output: String) -> [String: PipShowInfo] {
        var result: [String: PipShowInfo] = [:]
        for block in output.components(separatedBy: "\n---") {
            var name    = ""
            var summary = ""
            var home: URL? = nil
            var location: String? = nil
            for line in block.components(separatedBy: "\n") {
                if line.hasPrefix("Name: ") {
                    name = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces).lowercased()
                } else if line.hasPrefix("Summary: ") {
                    summary = String(line.dropFirst(9)).trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("Home-page: ") {
                    let raw = String(line.dropFirst(11)).trimmingCharacters(in: .whitespaces)
                    if !raw.isEmpty { home = URL(string: raw) }
                } else if line.hasPrefix("Location: ") {
                    let raw = String(line.dropFirst(10)).trimmingCharacters(in: .whitespaces)
                    if !raw.isEmpty { location = raw }
                }
            }
            if !name.isEmpty {
                result[name] = PipShowInfo(summary: summary, homepage: home, location: location)
            }
        }
        return result
    }

    private func resolvedPip() -> String {
        let candidates = [
            "/opt/homebrew/bin/pip3",
            "/usr/local/bin/pip3",
            "/usr/bin/pip3",           // System Python (bundled with Xcode on macOS)
            "/opt/homebrew/bin/pip",
            "/usr/local/bin/pip",
            "/usr/bin/pip"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "pip3"
    }
}
