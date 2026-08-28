import Foundation
import SwiftUI

struct PackageCollection: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var packageIds: [String]   // Package.id values ("npm-typescript", "brew-formula-bat", …)
    var icon: String           // SF Symbol name
    var colorName: String      // see CollectionIconOption.color(for:)

    init(name: String, icon: String = "star.fill", colorName: String = "orange") {
        self.id        = UUID()
        self.name      = name
        self.packageIds = []
        self.icon      = icon
        self.colorName = colorName
    }
}

// Canonical icon+color pairs shown in the collection editor.
struct CollectionIconOption: Identifiable {
    let id      = UUID()
    let symbol: String
    let color:  String   // color name key

    static let all: [CollectionIconOption] = [
        .init(symbol: "star.fill",                      color: "orange"),
        .init(symbol: "heart.fill",                     color: "pink"),
        .init(symbol: "bookmark.fill",                  color: "blue"),
        .init(symbol: "tag.fill",                       color: "purple"),
        .init(symbol: "flame.fill",                     color: "red"),
        .init(symbol: "bolt.fill",                      color: "yellow"),
        .init(symbol: "briefcase.fill",                 color: "blue"),
        .init(symbol: "wrench.and.screwdriver.fill",    color: "gray"),
        .init(symbol: "terminal.fill",                  color: "green"),
        .init(symbol: "server.rack",                    color: "teal"),
        .init(symbol: "cube.fill",                      color: "indigo"),
        .init(symbol: "archivebox.fill",                color: "brown"),
        .init(symbol: "folder.fill",                    color: "yellow"),
        .init(symbol: "tray.fill",                      color: "gray"),
        .init(symbol: "gearshape.fill",                 color: "gray"),
        .init(symbol: "shield.fill",                    color: "indigo"),
        .init(symbol: "checkmark.seal.fill",            color: "green"),
        .init(symbol: "clock.fill",                     color: "secondary"),
        .init(symbol: "globe",                          color: "blue"),
        .init(symbol: "person.fill",                    color: "teal"),
    ]
}

extension Color {
    static func pkgLensCollection(_ name: String) -> Color {
        switch name {
        case "orange":    return .orange
        case "pink":      return .pink
        case "blue":      return .blue
        case "purple":    return .purple
        case "red":       return .red
        case "yellow":    return .yellow
        case "green":     return .green
        case "teal":      return .teal
        case "indigo":    return .indigo
        case "brown":     return .brown
        case "gray":      return .gray
        default:          return .orange
        }
    }
}

actor CollectionStore {
    private let fileURL: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir  = home.appendingPathComponent(".pkglens")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("collections.json")
    }

    func load() -> [PackageCollection] {
        guard let data = try? Data(contentsOf: fileURL),
              let cols = try? JSONDecoder().decode([PackageCollection].self, from: data)
        else { return [] }
        return cols
    }

    func save(_ collections: [PackageCollection]) {
        guard let data = try? JSONEncoder().encode(collections) else { return }
        try? data.write(to: fileURL)
    }
}
