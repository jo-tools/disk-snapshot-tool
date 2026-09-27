import SwiftUI

struct MainView: View {
    @Environment(Library.self) private var library
    @Environment(SidebarModel.self) private var sidebar
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 400)
        } detail: {
            Group {
                if let disk = sidebar.selectedDisk {
                    // Keyed by disk so the board's own state starts over per disk.
                    SnapshotBoardView(disk: disk)
                        .id(disk.id)
                } else {
                    placeholder
                }
            }
            // Suppress the split view's cross-fade when the disk changes.
            .animation(nil, value: sidebar.selectedDisk?.id)
        }
        .frame(minWidth: 760, minHeight: 480)
        .task {
            library.load()
            sidebar.restore()
            await library.refreshAll()
        }
        .task {
            await DiskLockMonitor.run { library.disks }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await library.refreshUnavailable()
                if let disk = sidebar.selectedDisk { await DiskOperations.refresh(disk) }
            }
        }
    }

    /// Three different nothings: an empty library is the only one where adding
    /// a file is the answer; with a container selected its disks are one row down.
    @ViewBuilder
    private var placeholder: some View {
        if library.items.isEmpty {
            ContentUnavailableView(
                "No Disk Images",
                systemImage: "internaldrive",
                description: Text("Drop a disk image or a UTM VM onto the sidebar, or choose File > Open Disk Image or VM….")
            )
        } else if let container = sidebar.selectedContainer {
            ContentUnavailableView(
                "Select a Disk Image",
                systemImage: "internaldrive",
                description: Text("Select one of the disk images in \"\(container.name)\" to see its snapshots.")
            )
        } else {
            ContentUnavailableView(
                "Select a Disk Image",
                systemImage: "internaldrive",
                description: Text("Select a disk image in the sidebar to see its snapshots, or drop another one onto the sidebar.")
            )
        }
    }
}
