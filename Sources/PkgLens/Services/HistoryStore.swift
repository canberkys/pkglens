import Foundation

actor HistoryStore {
    struct Entry: Codable, Identifiable, Sendable {
        let id: UUID
        let name: String
        let version: String
        let source: String
        let removedAt: Date

        init(package: Package) {
            self.id        = UUID()
            self.name      = package.name
            self.version   = package.version
            self.source    = package.source.rawValue
            self.removedAt = Date()
        }
    }

    private let fileURL: URL
    private(set) var entries: [Entry] = []

    init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pkglens")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? decoder.decode([Entry].self, from: data) {
            entries = loaded
        }
    }

    func append(package: Package) {
        entries.insert(Entry(package: package), at: 0)
        if entries.count > 50 { entries = Array(entries.prefix(50)) }
        persist()
    }

    func recent(limit: Int = 5) -> [Entry] {
        Array(entries.prefix(limit))
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(entries) {
            // .atomic writes to a temp file then renames — prevents corruption on crash.
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
