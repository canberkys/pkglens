import SwiftUI

@main
struct PkgLensApp: App {
    @StateObject private var viewModel = PackagesViewModel()

    var body: some Scene {
        // "main" id lets openWindow(id:) target this group from the menu bar.
        WindowGroup(id: "main") {
            MainView()
                .environmentObject(viewModel)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Refresh Packages") {
                    Task { await viewModel.loadAll() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button("PkgLens on GitHub") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/canberkys/pkglens")!)
                }
                Button("Report an Issue") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/canberkys/pkglens/issues/new")!)
                }
                Divider()
                Button("What is an orphan package?") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/canberkys/pkglens#usage")!)
                }
            }
        }

        MenuBarExtra {
            MenuBarContent()
                .environmentObject(viewModel)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "shippingbox.fill")
                if !viewModel.isLoading {
                    Text("\(viewModel.packages.count)")
                        .monospacedDigit()
                }
            }
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}

private struct MenuBarContent: View {
    @EnvironmentObject private var vm: PackagesViewModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if vm.isLoading {
            Text("Scanning packages…")
            Divider()
        } else {
            // Tapping these sets the filter and opens the app
            Button("\(vm.packages.count) packages installed") {
                open(filter: .all)
            }
            Button("\(vm.orphansToRemove.count) can be safely removed") {
                vm.showOrphansOnly = true
                vm.showStaleOnly   = false
                open(filter: .all)
            }
            if vm.staleCount > 0 {
                Button("\(vm.staleCount) unused 90+ days") {
                    vm.showStaleOnly   = true
                    vm.showOrphansOnly = false
                    open(filter: .all)
                }
            }
            if vm.updateCount > 0 {
                Button("\(vm.updateCount) updates available") {
                    open(filter: .all)
                }
            }
            Divider()
            ForEach(PackageSource.allCases, id: \.self) { source in
                let n = vm.count(for: source)
                if n > 0 {
                    Button("\(source.displayName): \(n)") {
                        open(filter: .source(source))
                    }
                }
            }
            Divider()
        }
        Button("Open PkgLens") { open(filter: nil) }
        Button("Refresh") {
            Task { await vm.loadAll() }
        }
        .disabled(vm.isLoading)
        Divider()
        Button("Quit PkgLens") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func open(filter: SourceFilter?) {
        if let f = filter { vm.selectedFilter = f }
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
