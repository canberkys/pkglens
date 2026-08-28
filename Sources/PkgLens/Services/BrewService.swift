import Foundation

actor BrewService {
    private let prefix: String = {
        FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local"
    }()
    // MARK: - JSON shapes

    private struct BrewInfoResponse: Decodable {
        let formulae: [FormulaInfo]
        let casks: [CaskInfo]
    }

    private struct FormulaInfo: Decodable {
        let name: String
        let desc: String?
        let homepage: String?
        let installed: [InstalledVersion]
        let dependencies: [String]

        struct InstalledVersion: Decodable {
            let version: String
            let installedOnRequest: Bool
            let time: Double?

            enum CodingKeys: String, CodingKey {
                case version, time
                case installedOnRequest = "installed_on_request"
            }
        }

        enum CodingKeys: String, CodingKey {
            case name, desc, homepage, installed, dependencies
        }
    }

    private struct CaskInfo: Decodable {
        let token: String
        let name: [String]
        let desc: String?
        let homepage: String?
        let version: String?
        let installed: String?
        let installedTime: Double?

        enum CodingKeys: String, CodingKey {
            case token, name, desc, homepage, version, installed
            case installedTime = "installed_time"
        }
    }

    // MARK: - Cache

    private var cachedInfo: BrewInfoResponse?
    private var cachedLeaves: Set<String>?

    // MARK: - Public API

    func loadAll() async throws -> [Package] {
        let info   = try await fetchInfo()
        let leaves = try await fetchLeaves()

        let formulae: [Package] = info.formulae.compactMap { f in
            guard let inst = f.installed.first else { return nil }
            return Package(
                id: "brew-formula-\(f.name)",
                name: f.name,
                version: inst.version,
                description: f.desc ?? "",
                source: .brewFormula,
                installedDate: inst.time.map { Date(timeIntervalSince1970: $0) },
                installedOnRequest: inst.installedOnRequest,
                dependencies: f.dependencies,
                isOrphan: leaves.contains(f.name),
                sizeBytes: nil,
                homepage: f.homepage.flatMap { URL(string: $0) },
                installPath: "\(prefix)/Cellar/\(f.name)/\(inst.version)"
            )
        }

        let casks: [Package] = info.casks.compactMap { c in
            guard c.installed != nil else { return nil }
            // Use the installed version string if available; fall back to the manifest version.
            let version = c.installed ?? c.version ?? "unknown"
            return Package(
                id: "brew-cask-\(c.token)",
                name: c.token,
                version: version,
                description: c.desc ?? (c.name.first ?? ""),
                source: .brewCask,
                installedDate: c.installedTime.map { Date(timeIntervalSince1970: $0) },
                installedOnRequest: true,
                dependencies: [],
                isOrphan: true,
                sizeBytes: nil,
                homepage: c.homepage.flatMap { URL(string: $0) },
                installPath: version != "unknown" ? "\(prefix)/Caskroom/\(c.token)/\(version)" : nil
            )
        }

        return formulae + casks
    }

    func uninstall(_ package: Package) async throws -> String {
        invalidateCache()
        switch package.source {
        case .brewFormula:
            return try await ProcessRunner.run("brew", arguments: ["uninstall", package.name])
        case .brewCask:
            return try await ProcessRunner.run("brew", arguments: ["uninstall", "--cask", package.name])
        default:
            throw ProcessError.failed(status: 1, stderr: "Not a Homebrew package")
        }
    }

    func invalidateCache() {
        cachedInfo   = nil
        cachedLeaves = nil
    }

    func usedBy(_ name: String) async throws -> [String] {
        let output = try await ProcessRunner.run("brew", arguments: ["uses", "--installed", name])
        return output.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func checkUpdates() async throws -> [String: String] {
        struct OutdatedResponse: Decodable {
            let formulae: [OutdatedFormula]
            let casks: [OutdatedCask]
            struct OutdatedFormula: Decodable {
                let name: String
                let latestVersion: String
                enum CodingKeys: String, CodingKey {
                    case name
                    // `current_version` is the *installed* version; `latest_version` is what's available.
                    case latestVersion = "latest_version"
                }
            }
            struct OutdatedCask: Decodable {
                let name: String
                let latestVersion: String
                enum CodingKeys: String, CodingKey {
                    case name
                    case latestVersion = "latest_version"
                }
            }
        }
        let json = try await ProcessRunner.run("brew", arguments: ["outdated", "--json=v2"])
        let decoded = try JSONDecoder().decode(OutdatedResponse.self, from: Data(json.utf8))
        var result: [String: String] = [:]
        for f in decoded.formulae { result[f.name] = f.latestVersion }
        for c in decoded.casks    { result[c.name] = c.latestVersion }
        return result
    }

    // MARK: - Private helpers

    private func fetchInfo() async throws -> BrewInfoResponse {
        if let cached = cachedInfo { return cached }
        let json = try await ProcessRunner.run("brew", arguments: ["info", "--json=v2", "--installed"])
        let info = try JSONDecoder().decode(BrewInfoResponse.self, from: Data(json.utf8))
        cachedInfo = info
        return info
    }

    private func fetchLeaves() async throws -> Set<String> {
        if let cached = cachedLeaves { return cached }
        let output = try await ProcessRunner.run("brew", arguments: ["leaves"])
        let leaves = Set(output.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) })
        cachedLeaves = leaves
        return leaves
    }
}
