import SwiftUI
import AppKit

struct PackageListView: View {
    @EnvironmentObject private var vm: PackagesViewModel
    @Binding var selectedPackage: Package?
    @State private var packageToUninstall: Package? = nil
    @State private var uninstallError: String? = nil

    var body: some View {
        List(vm.filtered, selection: $selectedPackage) { pkg in
            PackageRow(
                package: pkg,
                hasNote: vm.notes[pkg.id] != nil,
                isStarred: vm.isPackageInAnyCollection(pkg.id)
            )
            .tag(pkg)
            .contextMenu { rowContextMenu(for: pkg) }
        }
        .confirmationDialog(
            packageToUninstall.map { "Uninstall \"\($0.name)\"?" } ?? "Uninstall?",
            isPresented: Binding(
                get: { packageToUninstall != nil },
                set: { if !$0 { packageToUninstall = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pkg = packageToUninstall {
                Button("Uninstall", role: .destructive) {
                    packageToUninstall = nil
                    Task {
                        do { try await vm.uninstall(pkg) }
                        catch { uninstallError = error.localizedDescription }
                    }
                }
                Button("Cancel", role: .cancel) { packageToUninstall = nil }
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
        .listStyle(.inset)
        .navigationSplitViewColumnWidth(min: 240, ideal: 320, max: 600)
        .safeAreaInset(edge: .top, spacing: 0) { listHeader }
        .overlay {
            if vm.isLoading && vm.packages.isEmpty {
                ProgressView(vm.loadingStatus.isEmpty ? "Loading…" : vm.loadingStatus)
            } else if vm.filtered.isEmpty && !vm.searchText.isEmpty {
                ContentUnavailableView.search(text: vm.searchText)
            } else if vm.packages.isEmpty && !vm.isLoading {
                ContentUnavailableView(
                    "No Packages Found",
                    systemImage: "tray",
                    description: Text("No package managers detected on this system.")
                )
            } else if vm.filtered.isEmpty && !vm.packages.isEmpty {
                if case .updates = vm.selectedFilter {
                    updatesEmptyState
                } else if case .recent = vm.selectedFilter {
                    recentEmptyState
                } else {
                    filtersEmptyState
                }
            }
        }
        .navigationTitle("Packages")
        .navigationSubtitle("\(vm.filtered.count) of \(vm.packages.count)")
    }

    private var listHeader: some View {
        HStack {
            Spacer()
            Picker("Sort", selection: $vm.sortOrder) {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .labelsHidden()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    // Shown when active filters produce zero results.
    private var filtersEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text("No Packages Match")
                    .font(.headline)
                Text(activeFilterDescription)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Clear Filters") { clearAllFilters() }
                .buttonStyle(.bordered)
                .controlSize(.regular)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private var updatesEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)

            VStack(spacing: 4) {
                Text("Everything is up to date")
                    .font(.headline)
                Text("Run \"Scan for Updates\" in the sidebar to check for newer versions.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private var recentEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(.purple)

            VStack(spacing: 4) {
                Text("No Recent Installs")
                    .font(.headline)
                Text("Packages installed in the last 7 days will appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private var activeFilterDescription: String {
        var parts: [String] = []
        if case .source(let s) = vm.selectedFilter { parts.append("Source: \(s.displayName)") }
        if case .updates       = vm.selectedFilter { parts.append("Updates only") }
        if vm.showOrphansOnly { parts.append("Orphans only") }
        if vm.showStaleOnly   { parts.append("Stale (90+ days)") }
        return parts.isEmpty ? "No packages match the current filters."
                             : "Active filters: " + parts.joined(separator: " · ")
    }

    private func clearAllFilters() {
        vm.selectedFilter  = .all
        vm.showOrphansOnly = false
        vm.showStaleOnly   = false
        vm.searchText      = ""
    }

    @ViewBuilder
    private func rowContextMenu(for pkg: Package) -> some View {
        Button("Copy Name") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(pkg.name, forType: .string)
        }
        Button("Copy Version") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(pkg.version, forType: .string)
        }
        if let path = pkg.installPath {
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
            }
        }

        if !vm.collections.isEmpty {
            Divider()
            ForEach(vm.collections) { col in
                Button {
                    Task { await vm.togglePackage(pkg.id, in: col.id) }
                } label: {
                    if vm.isPackage(pkg.id, inCollection: col.id) {
                        Label("Remove from \"\(col.name)\"", systemImage: "checkmark")
                    } else {
                        Label("Add to \"\(col.name)\"", systemImage: "star")
                    }
                }
            }
        }

        Divider()
        Button(role: .destructive) {
            packageToUninstall = pkg
        } label: {
            Label("Uninstall…", systemImage: "trash")
        }
    }
}

// MARK: - Row

struct PackageRow: View {
    let package: Package
    var hasNote: Bool    = false
    var isStarred: Bool  = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: package.source.icon)
                .frame(width: 18)
                .foregroundStyle(package.source.color.opacity(0.85))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(package.name)
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                        .lineLimit(1)

                    // isOrphan is only meaningful for Homebrew (derived from `brew leaves`).
                    // npm/pip/cargo/gem packages are always marked orphan due to lack of
                    // dependency tracking — showing the badge there would be misleading.
                    if package.isOrphan && (package.source == .brewFormula || package.source == .brewCask) {
                        Image(systemName: "leaf.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .help("Orphan — nothing depends on this")
                    }

                    if package.isStale {
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .help("Not updated in 90+ days")
                    }

                    if package.isOutdated {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                            .help("Update available: \(package.latestVersion ?? "")")
                    }
                }

                if !package.description.isEmpty {
                    Text(package.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let days = package.daysSinceInstall {
                    Text("Installed \(days) days ago")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                if isStarred {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange.opacity(0.8))
                }
                if hasNote {
                    Image(systemName: "bubble.left.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.6))
                }
                Text(package.version)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}
