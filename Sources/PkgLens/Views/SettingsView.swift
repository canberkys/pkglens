import SwiftUI

struct SettingsView: View {
    @AppStorage("apiKey") private var apiKey = ""
    @AppStorage("aiProvider") private var aiProvider = "none"

    private let appVersion: String = {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }()

    var body: some View {
        Form {
            // MARK: About
            Section("About PkgLens") {
                HStack(spacing: 16) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("PkgLens")
                            .font(.headline)
                        Text("Version \(appVersion)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Text("Package manager dashboard for macOS")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            // MARK: Keyboard Shortcuts
            Section("Keyboard Shortcuts") {
                ShortcutRow(keys: "⌘R",       action: "Refresh all packages")
                ShortcutRow(keys: "⌘,",       action: "Open Settings")
                ShortcutRow(keys: "⌘F",       action: "Search packages")
                ShortcutRow(keys: "⌘⇧E",     action: "Export package list")
            }

            // MARK: AI Descriptions
            Section("AI Descriptions (Optional)") {
                Picker("Provider", selection: $aiProvider) {
                    Text("Disabled").tag("none")
                    Text("Claude (Anthropic)").tag("claude")
                    Text("OpenAI").tag("openai")
                }
                .pickerStyle(.radioGroup)

                if aiProvider != "none" {
                    SecureField("API Key", text: $apiKey)
                        .textContentType(.password)

                    Text("Used only to explain unknown packages. Keys are stored in macOS Keychain.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: Supported Sources
            Section("Supported Package Managers") {
                LabeledContent("Homebrew", value: "formulae and casks (brew)")
                LabeledContent("npm", value: "global packages")
                LabeledContent("pip", value: "Python packages")
                LabeledContent("Cargo", value: "Rust crates")
                LabeledContent("RubyGems", value: "gem list --local")
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 460)
        .navigationTitle("Settings")
    }
}

// MARK: - Helpers

private struct ShortcutRow: View {
    let keys: String
    let action: String

    var body: some View {
        HStack {
            Text(action)
            Spacer()
            Text(keys)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.fill.secondary, in: RoundedRectangle(cornerRadius: 5))
        }
    }
}
