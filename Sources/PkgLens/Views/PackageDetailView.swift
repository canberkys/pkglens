import SwiftUI
import AppKit

struct PackageDetailView: View {
    let package: Package
    @EnvironmentObject private var vm: PackagesViewModel
    @State private var showUninstallConfirm = false
    @State private var isUninstalling = false
    @State private var isUpgrading = false
    @State private var uninstallError: String?
    @State private var noteText = ""
    @State private var calculatedSize: String? = nil
    @State private var isCalculatingSize = false
    @State private var usedByList: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            // ── Full-width top: header + banners ──────────────────────────
            VStack(alignment: .leading, spacing: 0) {
                HeaderSection(package: package)
                    .padding(24)

                if package.isOutdated, let latest = package.latestVersion {
                    let canUpgrade = package.source == .brewFormula
                                  || package.source == .brewCask
                                  || package.source == .npm
                    UpdateAvailableBanner(
                        latestVersion: latest,
                        isUpgrading: isUpgrading,
                        canUpgrade: canUpgrade
                    ) {
                        Task { await performUpgrade() }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
                } else if package.isSafeToRemove {
                    SafeToRemoveBanner()
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                } else if !package.dependencies.isEmpty {
                    DependencyWarningBanner(count: package.dependencies.count)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                }
            }

            Divider()

            // ── Two-column body ───────────────────────────────────────────
            HStack(alignment: .top, spacing: 0) {
                // Left: meta + notes
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        MetaSection(package: package)
                        Divider()
                        NotesSection(noteText: $noteText) {
                            Task { await vm.setNote(noteText, for: package) }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)

                Divider()

                // Right: path, needed by, dependencies
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let path = package.installPath {
                            PathSection(
                                path: path,
                                calculatedSize: calculatedSize,
                                isCalculatingSize: isCalculatingSize,
                                onReveal: {
                                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                                },
                                onCalculateSize: { Task { await calculateSize() } }
                            )
                        }
                        if !usedByList.isEmpty {
                            if package.installPath != nil { Divider() }
                            UsedBySection(packages: usedByList)
                        }
                        if !package.dependencies.isEmpty {
                            if package.installPath != nil || !usedByList.isEmpty { Divider() }
                            DependenciesSection(deps: package.dependencies)
                        }
                        if package.installPath == nil && usedByList.isEmpty && package.dependencies.isEmpty {
                            Text("No path or dependency information available.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            ActionBar(
                package: package,
                isUninstalling: isUninstalling,
                onUninstall: { showUninstallConfirm = true }
            )
        }
        .sheet(isPresented: $showUninstallConfirm) {
            UninstallConfirmView(package: package) {
                showUninstallConfirm = false
                Task { await performUninstall() }
            } onCancel: {
                showUninstallConfirm = false
            }
        }
        .alert("Uninstall Failed", isPresented: Binding(
            get: { uninstallError != nil },
            set: { if !$0 { uninstallError = nil } }
        )) {
            Button("OK") { uninstallError = nil }
        } message: {
            Text(uninstallError ?? "")
        }
        .task(id: package.id) {
            noteText = vm.notes[package.id] ?? ""
            calculatedSize = nil
            usedByList = []
            if package.source == .brewFormula {
                usedByList = (try? await vm.brewUsedBy(package.name)) ?? []
            }
        }
    }

    private func calculateSize() async {
        guard let path = package.installPath, !isCalculatingSize else { return }
        isCalculatingSize = true
        let output = (try? await ProcessRunner.run("/usr/bin/du", arguments: ["-sh", path])) ?? ""
        let sizeStr = output.components(separatedBy: "\t").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        calculatedSize = sizeStr.isEmpty ? nil : sizeStr
        isCalculatingSize = false
    }

    private func performUninstall() async {
        isUninstalling = true
        do {
            try await vm.uninstall(package)
        } catch {
            uninstallError = error.localizedDescription
        }
        isUninstalling = false
    }

    private func performUpgrade() async {
        isUpgrading = true
        do {
            try await vm.upgrade(package)
        } catch {
            uninstallError = error.localizedDescription
        }
        isUpgrading = false
    }
}

// MARK: - Header

private struct HeaderSection: View {
    let package: Package

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Source badge
            Label(package.source.displayName, systemImage: package.source.icon)
                .font(.caption)
                .foregroundStyle(package.source.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(package.source.color.opacity(0.1), in: Capsule())

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(package.name)
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                    .fontDesign(.monospaced)
                    .textSelection(.enabled)

                Text(package.version)
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .fontDesign(.monospaced)
            }

            if !package.description.isEmpty {
                Text(package.description)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let url = package.homepage {
                Link(destination: url) {
                    Label("Homepage", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
        }
    }
}

// MARK: - Banners

private struct UpdateAvailableBanner: View {
    let latestVersion: String
    let isUpgrading: Bool
    var canUpgrade: Bool = true
    let onUpgrade: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.circle.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text("Update available: \(latestVersion)")
                    .fontWeight(.medium)
                if canUpgrade {
                    Text("A newer version is ready to install.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Update via your package manager — in-app update not supported for this source.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if canUpgrade {
                if isUpgrading {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Update", action: onUpgrade)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
        .padding(12)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.blue.opacity(0.2)))
    }
}

private struct SafeToRemoveBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Safe to remove")
                    .fontWeight(.medium)
                Text("No other package depends on this, and you installed it directly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.green.opacity(0.2)))
    }
}

private struct DependencyWarningBanner: View {
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Has \(count) \(count == 1 ? "dependency" : "dependencies")")
                    .fontWeight(.medium)
                Text("Other packages may depend on this. Brew will warn you before removing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.orange.opacity(0.2)))
    }
}

// MARK: - Path & Size

private struct PathSection: View {
    let path: String
    let calculatedSize: String?
    let isCalculatingSize: Bool
    let onReveal: () -> Void
    let onCalculateSize: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Install Path", systemImage: "folder")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 8) {
                Text(path)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                Spacer()
                Button("Reveal", action: onReveal)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }

            HStack(spacing: 8) {
                if let size = calculatedSize {
                    Label(size, systemImage: "internaldrive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isCalculatingSize {
                    ProgressView().controlSize(.mini)
                    Text("Calculating…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Calculate Size", action: onCalculateSize)
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                }
            }
        }
    }
}

// MARK: - Used By

private struct UsedBySection: View {
    let packages: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Needed By (\(packages.count))", systemImage: "arrow.triangle.branch")
                .font(.headline)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 100, maximum: 220), spacing: 6)],
                spacing: 6
            ) {
                ForEach(packages, id: \.self) { dep in
                    Text(dep)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 5))
                }
            }
        }
    }
}

// MARK: - Meta

private struct MetaSection: View {
    let package: Package

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
            MetaRow(label: "Source", value: package.source.displayName)
            MetaRow(label: "Version", value: package.version)

            if let date = package.installedDate {
                MetaRow(label: "Installed", value: date.formatted(date: .long, time: .omitted))
            }

            if let size = package.displaySize {
                MetaRow(label: "Size", value: size)
            }

            MetaRow(
                label: "Origin",
                value: package.installedOnRequest ? "Installed directly" : "Installed as dependency"
            )

            MetaRow(
                label: "Orphan",
                value: package.isOrphan ? "Yes (nothing depends on it)" : "No"
            )
        }
    }
}

private struct MetaRow: View {
    let label: String
    let value: String

    var body: some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
                .fixedSize()
            Text(value)
                .fontDesign(.monospaced)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Dependencies

private struct DependenciesSection: View {
    let deps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dependencies (\(deps.count))")
                .font(.headline)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 100, maximum: 220), spacing: 6)],
                spacing: 6
            ) {
                ForEach(deps, id: \.self) { dep in
                    Text(dep)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 5))
                }
            }
        }
    }
}

// MARK: - Notes

private struct NotesSection: View {
    @Binding var noteText: String
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Note", systemImage: "bubble.left")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Why did you install this? (press Return to save)", text: $noteText)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
                .onSubmit { onSave() }
        }
    }
}

// MARK: - Action bar

private struct ActionBar: View {
    let package: Package
    let isUninstalling: Bool
    let onUninstall: () -> Void

    var body: some View {
        HStack {
            if !package.installedOnRequest {
                Label("Installed as dependency", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isUninstalling {
                ProgressView("Uninstalling…").controlSize(.small)
            } else {
                Button(role: .destructive, action: onUninstall) {
                    Label("Uninstall", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.bar)
    }
}
