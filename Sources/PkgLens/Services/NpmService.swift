import Foundation

actor NpmService {
    private let hidden: Set<String> = ["npm", "corepack"]

    // Read installed packages directly from the filesystem instead of running
    // `npm list`, which requires npm to resolve the correct node runtime via PATH.
    // Deriving the global node_modules root from the npm binary location is robust
    // across nvm, nodenv, and homebrew node installations.
    func loadInstalledPackages() async throws -> [Package] {
        let npmPath = try resolvedNpmPath()
        let npmBin  = URL(fileURLWithPath: npmPath)
        // Structure: <node_root>/bin/npm → <node_root>/lib/node_modules
        let globalModules = npmBin
            .deletingLastPathComponent()           // .../bin
            .deletingLastPathComponent()           // .../node_root
            .appendingPathComponent("lib/node_modules")

        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: globalModules.path) else {
            return []
        }

        var result: [Package] = []
        for entry in entries {
            if entry.hasPrefix("@") {
                // Scoped directory (e.g. @anthropic-ai) — each child is a package
                let scopeDir = globalModules.appendingPathComponent(entry)
                if let children = try? fm.contentsOfDirectory(atPath: scopeDir.path) {
                    for child in children {
                        let fullName = "\(entry)/\(child)"
                        guard !hidden.contains(fullName) else { continue }
                        let pkgDir = scopeDir.appendingPathComponent(child)
                        if let pkg = readPackage(at: pkgDir, name: fullName) { result.append(pkg) }
                    }
                }
            } else {
                guard !hidden.contains(entry) else { continue }
                let pkgDir = globalModules.appendingPathComponent(entry)
                if let pkg = readPackage(at: pkgDir, name: entry) { result.append(pkg) }
            }
        }

        return result.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    func checkUpdates() async throws -> [String: String] {
        let npm = try resolvedNpmPath()
        let binDir = URL(fileURLWithPath: npm).deletingLastPathComponent().path
        let extraEnv = ["PATH": "\(binDir):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]
        // npm outdated exits with code 1 when outdated packages exist; allowNonZeroExit captures stdout anyway.
        let output = try await ProcessRunner.run(
            npm, arguments: ["outdated", "-g", "--json"],
            extraEnv: extraEnv, allowNonZeroExit: true
        )
        guard let data = output.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]]
        else { return [:] }
        return dict.compactMapValues { $0["latest"] as? String }
    }

    func upgrade(_ package: Package) async throws -> String {
        let npm = try resolvedNpmPath()
        let binDir = URL(fileURLWithPath: npm).deletingLastPathComponent().path
        let extraEnv = ["PATH": "\(binDir):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]
        return try await ProcessRunner.run(npm, arguments: ["install", "-g", package.name], extraEnv: extraEnv)
    }

    func uninstall(_ package: Package) async throws -> String {
        let npm = try resolvedNpmPath()
        // Put npm's own bin dir first so node resolution uses the same runtime.
        let binDir = URL(fileURLWithPath: npm).deletingLastPathComponent().path
        let extraEnv = ["PATH": "\(binDir):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]
        return try await ProcessRunner.run(npm, arguments: ["uninstall", "-g", package.name], extraEnv: extraEnv)
    }

    // Reads a package's metadata from its local package.json (no network call).
    private func readPackage(at dir: URL, name: String) -> Package? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent("package.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        let version = (json["version"] as? String) ?? "unknown"
        let desc    = (json["description"] as? String) ?? ""
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let home: URL? = (json["homepage"] as? String).flatMap { URL(string: $0) }
            ?? URL(string: "https://www.npmjs.com/package/\(encoded)")

        return Package(
            id: "npm-\(name)",
            name: name,
            version: version,
            description: desc,
            source: .npm,
            installedDate: nil,
            installedOnRequest: true,
            dependencies: [],
            isOrphan: true,
            sizeBytes: nil,
            homepage: home,
            installPath: dir.path
        )
    }

    func resolvedPath() throws -> String { try resolvedNpmPath() }

    // Searches PATH entries, nvm directory, and static locations for the npm binary.
    private func resolvedNpmPath() throws -> String {
        let fm   = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path

        // 1. Parent process PATH (works when app is launched from a configured terminal)
        for dir in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init) {
            let candidate = "\(dir)/npm"
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }

        // 2. nvm: scan ~/.nvm/versions/node/<version>/bin/npm (newest first).
        // Use localizedStandardCompare so "v10.x" sorts after "v9.x" (semantic order).
        let nvmNodeDir = "\(home)/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmNodeDir) {
            let sorted = versions.sorted {
                $0.localizedStandardCompare($1) == .orderedDescending
            }
            for version in sorted {
                let candidate = "\(nvmNodeDir)/\(version)/bin/npm"
                if fm.isExecutableFile(atPath: candidate) { return candidate }
            }
        }

        // 3. Static fallbacks
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"] {
            let candidate = "\(dir)/npm"
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }

        throw ProcessError.notFound(command: "npm")
    }
}
