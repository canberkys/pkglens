import SwiftUI

struct UninstallConfirmView: View {
    let package: Package
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(.red.opacity(0.1))
                    .frame(width: 72, height: 72)
                Image(systemName: "trash.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.red)
            }

            VStack(spacing: 8) {
                Text("Uninstall \u{201C}\(package.name)\u{201D}?")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Group {
                    switch package.source {
                    case .brewFormula:
                        Text("Runs `brew uninstall \(package.name)`.")
                    case .brewCask:
                        Text("Runs `brew uninstall --cask \(package.name)`.")
                    case .npm:
                        Text("Runs `npm uninstall -g \(package.name)`.")
                    case .pip:
                        Text("Runs `pip3 uninstall -y \(package.name)`.")
                    case .cargo:
                        Text("Runs `cargo uninstall \(package.name)`.")
                    case .gem:
                        Text("Runs `gem uninstall \(package.name)`.")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

                if !package.dependencies.isEmpty {
                    Label("\(package.dependencies.count) listed dependencies — brew will warn if needed",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .padding(.top, 4)
                }

                if !package.installedOnRequest {
                    Label("Originally installed as a dependency of another package",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)

                Button(role: .destructive, action: onConfirm) {
                    Label("Uninstall", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }
        }
        .padding(32)
        .frame(width: 380)
    }
}
