import SwiftUI
import AppKit

struct MainView: View {
    @EnvironmentObject private var vm: PackagesViewModel
    @State private var selectedPackage: Package?
    @State private var showExportPicker = false
    @State private var showBulkRemoveConfirm = false

    var body: some View {
        NavigationSplitView {
            SidebarView(showBulkRemoveConfirm: $showBulkRemoveConfirm)
                .environmentObject(vm)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 320)
        } content: {
            PackageListView(selectedPackage: $selectedPackage)
                .environmentObject(vm)
        } detail: {
            if let pkg = selectedPackage {
                PackageDetailView(package: pkg)
                    .environmentObject(vm)
                    .id(pkg.id)
            } else {
                WelcomeDetailView()
                    .environmentObject(vm)
            }
        }
        .searchable(text: $vm.searchText, placement: .toolbar, prompt: "Search packages…")
        .toolbar { ToolbarItems(onExport: { showExportPicker = true }) }
        .task { await vm.loadAll() }
        .onChange(of: vm.packages) {
            // Package is a struct — equality breaks when latestVersion mutates after
            // checkVersion(). Match by stable ID and propagate the updated value so
            // the detail view re-renders with the new latestVersion in place.
            if let sel = selectedPackage {
                if let updated = vm.packages.first(where: { $0.id == sel.id }) {
                    selectedPackage = updated
                } else {
                    selectedPackage = nil  // removed (uninstall / full reload)
                }
            }
        }
        .sheet(isPresented: $showBulkRemoveConfirm) {
            BulkRemoveConfirmView(packages: vm.orphansToRemove) {
                showBulkRemoveConfirm = false
                Task { await vm.removeAllOrphans() }
            } onCancel: {
                showBulkRemoveConfirm = false
            }
        }
        .sheet(isPresented: $showExportPicker) {
            ExportSheet()
                .environmentObject(vm)
        }
        .alert("Load Errors", isPresented: Binding(
            get: { !vm.errors.isEmpty },
            set: { if !$0 { vm.errors = [] } }
        )) {
            Button("OK") { vm.errors = [] }
        } message: {
            Text(vm.errors.joined(separator: "\n"))
        }
    }
}

// MARK: - Sidebar

private struct SidebarView: View {
    @EnvironmentObject private var vm: PackagesViewModel
    @Binding var showBulkRemoveConfirm: Bool
    @State private var showUpdateAllConfirm = false

    var body: some View {
        List(selection: $vm.selectedFilter) {
            Section("Sources") {
                SidebarRow(label: "All Packages",
                           icon: "square.grid.2x2.fill",
                           color: .primary,
                           count: vm.packages.count)
                    .tag(SourceFilter.all)

                ForEach(PackageSource.allCases, id: \.self) { source in
                    SidebarRow(label: source.displayName,
                               icon: source.icon,
                               color: source.color,
                               count: vm.count(for: source))
                        .tag(SourceFilter.source(source))
                }
            }

            Section("Quick Filters") {
                Toggle(isOn: $vm.showOrphansOnly) {
                    Label {
                        Text("Orphans")
                    } icon: {
                        Image(systemName: "leaf.fill").foregroundStyle(.green)
                    }
                }
                .toggleStyle(.checkbox)
                .badge(vm.orphanCount)

                if vm.showOrphansOnly && !vm.orphansToRemove.isEmpty {
                    Button {
                        showBulkRemoveConfirm = true
                    } label: {
                        Label("Remove All Orphans", systemImage: "trash")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }

                Toggle(isOn: $vm.showStaleOnly) {
                    Label {
                        Text("Stale (90+ days)")
                    } icon: {
                        Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.orange)
                    }
                }
                .toggleStyle(.checkbox)
                .badge(vm.staleCount)
            }

            Section("Updates") {
                SidebarRow(label: "Available Updates",
                           icon: "arrow.up.circle.fill",
                           color: .blue,
                           count: vm.updateCount)
                    .tag(SourceFilter.updates)

                if vm.isCheckingUpdates {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Scanning…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, 4)
                } else {
                    Button {
                        Task { await vm.checkForUpdates() }
                    } label: {
                        Label("Scan for Updates", systemImage: "arrow.clockwise")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                    .disabled(vm.isLoading)
                }

                if !vm.upgradeAllEligible.isEmpty {
                    Button {
                        showUpdateAllConfirm = true
                    } label: {
                        Label("Update All (\(vm.upgradeAllEligible.count))", systemImage: "arrow.up.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
            }
            .sheet(isPresented: $showUpdateAllConfirm) {
                UpdateAllConfirmView(packages: vm.upgradeAllEligible) {
                    showUpdateAllConfirm = false
                    Task { await vm.upgradeAll() }
                } onCancel: {
                    showUpdateAllConfirm = false
                }
            }

            if !vm.recentRemovals.isEmpty {
                Section("Recent Removals") {
                    ForEach(vm.recentRemovals) { entry in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.name)
                                .font(.system(.caption, design: .monospaced))
                                .fontWeight(.medium)
                            Text(entry.removedAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("PkgLens")
        .safeAreaInset(edge: .bottom) {
            if vm.isLoading {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(vm.loadingStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }
}

private struct SidebarRow: View {
    let label: String
    let icon: String
    let color: Color
    let count: Int

    var body: some View {
        Label {
            Text(label)
        } icon: {
            Image(systemName: icon).foregroundStyle(color)
        }
        .badge(count)
    }
}

// MARK: - Toolbar

private struct ToolbarItems: ToolbarContent {
    @EnvironmentObject private var vm: PackagesViewModel
    let onExport: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(action: onExport) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .disabled(vm.packages.isEmpty)
            .help("Export package list")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await vm.loadAll() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(vm.isLoading)
            .keyboardShortcut("r", modifiers: .command)
            .help("Refresh all packages (⌘R)")
        }

        ToolbarItem(placement: .primaryAction) {
            Picker("Sort", selection: $vm.sortOrder) {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .help("Sort order")
        }
    }
}

// MARK: - Update All Confirm

private struct UpdateAllConfirmView: View {
    let packages: [Package]
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().fill(.blue.opacity(0.1)).frame(width: 72, height: 72)
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30)).foregroundStyle(.blue)
            }
            VStack(spacing: 6) {
                Text("Update \(packages.count) \(packages.count == 1 ? "package" : "packages")?")
                    .font(.headline).multilineTextAlignment(.center)
                Text("Homebrew and npm packages will be upgraded in-place.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(packages, id: \.id) { pkg in
                        HStack {
                            Text("• \(pkg.name)")
                                .font(.system(.caption, design: .monospaced))
                            Spacer()
                            if let latest = pkg.latestVersion {
                                Text("\(pkg.version) → \(latest)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 6))
            }
            .frame(maxHeight: 160)

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction).controlSize(.large)
                Button(action: onConfirm) {
                    Label("Update All", systemImage: "arrow.up.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction).controlSize(.large)
            }
        }
        .padding(28)
        .frame(width: 420)
    }
}

// MARK: - Bulk Remove Confirm

private struct BulkRemoveConfirmView: View {
    let packages: [Package]
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle().fill(.red.opacity(0.1)).frame(width: 72, height: 72)
                Image(systemName: "trash.fill")
                    .font(.system(size: 30)).foregroundStyle(.red)
            }
            VStack(spacing: 6) {
                Text("Remove \(packages.count) orphan packages?")
                    .font(.headline).multilineTextAlignment(.center)
                Text("These packages have no dependents and were installed directly.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(packages, id: \.id) { pkg in
                        Text("• \(pkg.name) (\(pkg.source.displayName))")
                            .font(.system(.caption, design: .monospaced))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 6))
            }
            .frame(maxHeight: 160)

            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction).controlSize(.large)
                Button(role: .destructive, action: onConfirm) {
                    Label("Remove All", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent).tint(.red)
                .keyboardShortcut(.defaultAction).controlSize(.large)
            }
        }
        .padding(28)
        .frame(width: 400)
    }
}

// MARK: - Export sheet

private struct ExportSheet: View {
    @EnvironmentObject private var vm: PackagesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var format: ExportFormat = .markdown
    @State private var writeError: String?

    enum ExportFormat: String, CaseIterable {
        case markdown = "Markdown"
        case json     = "JSON"
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 36))
                .foregroundStyle(.blue)

            Text("Export Package List")
                .font(.headline)

            Text("\(vm.packages.count) packages will be exported")
                .foregroundStyle(.secondary)

            Picker("Format", selection: $format) {
                ForEach(ExportFormat.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)

                Button("Save…") { saveFile() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(32)
        .frame(width: 360)
        .alert("Export Failed", isPresented: Binding(
            get: { writeError != nil },
            set: { if !$0 { writeError = nil } }
        )) {
            Button("OK") { writeError = nil }
        } message: {
            Text(writeError ?? "")
        }
    }

    private func saveFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = format == .markdown ? "packages.md" : "packages.json"
        panel.allowedContentTypes = format == .markdown ? [.text] : [.json]
        panel.begin { response in
            // User cancelled — keep the sheet open so they can retry or cancel.
            guard response == .OK, let url = panel.url else { return }
            do {
                if format == .markdown {
                    try vm.exportMarkdown().write(to: url, atomically: true, encoding: .utf8)
                } else {
                    try vm.exportJSON().write(to: url)
                }
                // Only dismiss on a successful write.
                dismiss()
            } catch {
                writeError = error.localizedDescription
            }
        }
    }
}

// MARK: - Welcome detail (no selection)

private struct WelcomeDetailView: View {
    @EnvironmentObject private var vm: PackagesViewModel

    var body: some View {
        VStack(spacing: 28) {
            if vm.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(vm.loadingStatus)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            } else {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.quaternary)

                VStack(spacing: 6) {
                    Text("\(vm.packages.count) packages installed")
                        .font(.title3).fontWeight(.medium)
                    if vm.staleCount > 0 {
                        Label("\(vm.staleCount) packages unused 90+ days",
                              systemImage: "clock.badge.exclamationmark")
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }
                    Text("\(vm.orphansToRemove.count) can be safely removed")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    ForEach(PackageSource.allCases, id: \.self) { source in
                        let n = vm.count(for: source)
                        if n > 0 {
                            VStack(spacing: 4) {
                                Image(systemName: source.icon)
                                    .foregroundStyle(source.color)
                                    .font(.title2)
                                Text("\(n)")
                                    .font(.title3).fontWeight(.semibold)
                                Text(source.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(width: 72)
                            }
                        }
                    }
                }
                .padding()
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))

                Text("Select a package to see details and manage it.")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
