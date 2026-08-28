import SwiftUI
import AppKit

struct MainView: View {
    @EnvironmentObject private var vm: PackagesViewModel
    @State private var selectedPackage: Package?
    @State private var showExportPicker = false
    @State private var showBulkRemoveConfirm = false
    @State private var isSearchActive = false

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
        .searchable(text: $vm.searchText, isPresented: $isSearchActive, placement: .toolbar, prompt: "Search packages…")
        // ⌘F — toggles search: activates when inactive, deactivates+clears when active.
        .background {
            Button("") {
                if isSearchActive {
                    vm.searchText  = ""
                    isSearchActive = false
                } else {
                    isSearchActive = true
                }
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
            .frame(width: 0, height: 0)
        }
        .toolbar { ToolbarItems(onExport: { showExportPicker = true }) }
        .task { await vm.loadAll() }
        .onChange(of: vm.selectedFilter) { _, _ in
            vm.searchText  = ""
            isSearchActive = false
        }
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
    @State private var showUpdateAllConfirm  = false
    @State private var showCollectionEditor  = false
    @State private var collectionToEdit: PackageCollection? = nil

    var body: some View {
        List(selection: $vm.selectedFilter) {
            Section {
                SidebarDashboardStrip()
                    .selectionDisabled()
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 4, trailing: 8))
            }

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

            Section {
                ForEach(vm.collections) { col in
                    SidebarRow(
                        label: col.name,
                        icon: col.icon,
                        color: .pkgLensCollection(col.colorName),
                        count: vm.collectionCount(for: col.id)
                    )
                    .tag(SourceFilter.collection(col.id))
                    .contextMenu {
                        Button("Edit…") {
                            collectionToEdit = col
                            showCollectionEditor = true
                        }
                        Button("Delete", role: .destructive) {
                            Task { await vm.deleteCollection(id: col.id) }
                        }
                    }
                }

                Button {
                    collectionToEdit = nil
                    showCollectionEditor = true
                } label: {
                    Label("New Collection…", systemImage: "plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            } header: {
                Text("My Collections")
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
        .sheet(isPresented: $showCollectionEditor) {
            CollectionEditorSheet(editingCollection: collectionToEdit)
                .environmentObject(vm)
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

// MARK: - Dashboard Strip

private struct SidebarDashboardStrip: View {
    @EnvironmentObject private var vm: PackagesViewModel

    var body: some View {
        HStack(spacing: 0) {
            statCell(value: vm.packages.count, label: "Total", color: .secondary) {
                vm.selectedFilter  = .all
                vm.showOrphansOnly = false
                vm.showStaleOnly   = false
            }
            sep()
            statCell(value: vm.updateCount, label: "Updates", color: .blue) {
                vm.selectedFilter = .updates
            }
            sep()
            statCell(value: vm.recentCount, label: "New", color: .purple) {
                vm.selectedFilter = .recent
            }
            sep()
            statCell(value: vm.orphanCount, label: "Orphans", color: .green) {
                vm.selectedFilter  = .all
                vm.showOrphansOnly = true
                vm.showStaleOnly   = false
            }
        }
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func sep() -> some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 0.5, height: 26)
    }

    private func statCell(
        value: Int, label: String, color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text("\(value)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(value > 0 ? color : Color.secondary)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
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
        case brewfile = "Brewfile"
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
        switch format {
        case .markdown: panel.nameFieldStringValue = "packages.md";  panel.allowedContentTypes = [.text]
        case .json:     panel.nameFieldStringValue = "packages.json"; panel.allowedContentTypes = [.json]
        case .brewfile: panel.nameFieldStringValue = "Brewfile";      panel.allowedContentTypes = [.text]
        }
        panel.begin { response in
            // User cancelled — keep the sheet open so they can retry or cancel.
            guard response == .OK, let url = panel.url else { return }
            do {
                switch format {
                case .markdown: try vm.exportMarkdown().write(to: url, atomically: true, encoding: .utf8)
                case .json:     try vm.exportJSON().write(to: url)
                case .brewfile: try vm.exportBrewfile().write(to: url, atomically: true, encoding: .utf8)
                }
                dismiss()
            } catch {
                writeError = error.localizedDescription
            }
        }
    }
}

// MARK: - Collection Editor Sheet

private struct CollectionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var vm: PackagesViewModel

    let editingCollection: PackageCollection?

    @State private var name            = ""
    @State private var selectedSymbol  = "star.fill"
    @State private var selectedColor   = "orange"

    var body: some View {
        VStack(spacing: 20) {
            // Live icon preview
            ZStack {
                Circle()
                    .fill(Color.pkgLensCollection(selectedColor).opacity(0.15))
                    .frame(width: 60, height: 60)
                Image(systemName: selectedSymbol)
                    .font(.system(size: 24))
                    .foregroundStyle(Color.pkgLensCollection(selectedColor))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Collection name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { commitAction() }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Icon")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 40, maximum: 48), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(CollectionIconOption.all) { opt in
                        Button {
                            selectedSymbol = opt.symbol
                            selectedColor  = opt.color
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(selectedSymbol == opt.symbol
                                          ? AnyShapeStyle(Color.pkgLensCollection(opt.color).opacity(0.18))
                                          : AnyShapeStyle(.fill.tertiary))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(
                                                selectedSymbol == opt.symbol
                                                    ? Color.pkgLensCollection(opt.color)
                                                    : Color.clear,
                                                lineWidth: 1.5
                                            )
                                    )
                                Image(systemName: opt.symbol)
                                    .font(.system(size: 17))
                                    .foregroundStyle(Color.pkgLensCollection(opt.color))
                            }
                            .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .help(opt.symbol)
                    }
                }
            }

            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.large)

                Button(editingCollection == nil ? "Create" : "Save") { commitAction() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 440)
        .onAppear {
            if let col = editingCollection {
                name           = col.name
                selectedSymbol = col.icon
                selectedColor  = col.colorName
            }
        }
    }

    private func commitAction() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Task {
            if let col = editingCollection {
                await vm.renameCollection(id: col.id, to: trimmed)
                await vm.updateCollectionAppearance(id: col.id, icon: selectedSymbol, colorName: selectedColor)
            } else {
                await vm.addCollection(name: trimmed, icon: selectedSymbol, colorName: selectedColor)
            }
            dismiss()
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
                    if vm.updateCount > 0 {
                        Label("\(vm.updateCount) updates available",
                              systemImage: "arrow.up.circle.fill")
                            .foregroundStyle(.blue)
                            .font(.callout)
                    }
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
