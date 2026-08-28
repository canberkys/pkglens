import SwiftUI

enum PackageSource: String, CaseIterable, Codable, Sendable {
    case brewFormula = "brew-formula"
    case brewCask    = "brew-cask"
    case npm         = "npm"
    case pip         = "pip"
    case cargo       = "cargo"
    case gem         = "gem"

    var displayName: String {
        switch self {
        case .brewFormula: "Homebrew Formula"
        case .brewCask:    "Homebrew Cask"
        case .npm:         "npm Global"
        case .pip:         "pip (Python)"
        case .cargo:       "Cargo (Rust)"
        case .gem:         "RubyGems"
        }
    }

    var icon: String {
        switch self {
        case .brewFormula: "flask.fill"
        case .brewCask:    "shippingbox.fill"
        case .npm:         "curlybraces"
        case .pip:         "p.circle.fill"
        case .cargo:       "gearshape.2.fill"
        case .gem:         "diamond.fill"
        }
    }

    var color: Color {
        switch self {
        case .brewFormula: .orange
        case .brewCask:    .blue
        case .npm:         .red
        case .pip:         Color(red: 0.22, green: 0.47, blue: 0.67)
        case .cargo:       Color(hue: 0.05, saturation: 0.85, brightness: 0.75)
        case .gem:         Color(red: 0.70, green: 0.15, blue: 0.22)
        }
    }
}
