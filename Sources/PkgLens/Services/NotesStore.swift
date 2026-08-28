import Foundation

actor NotesStore {
    private let fileURL: URL
    private var notes: [String: String] = [:]

    init() {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pkglens")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("notes.json")

        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode([String: String].self, from: data) {
            notes = loaded
        }
    }

    func note(for id: String) -> String {
        notes[id] ?? ""
    }

    func setNote(_ text: String, for id: String) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes.removeValue(forKey: id)
        } else {
            notes[id] = text
        }
        persist()
    }

    func allNotes() -> [String: String] { notes }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(notes) {
            // .atomic writes to a temp file then renames — prevents corruption on crash.
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
