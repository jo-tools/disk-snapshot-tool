import SwiftUI
import AppKit

struct SnapshotBoardView: View {
    @Environment(Library.self) private var library
    let disk: DiskImage

    @State private var selectedSnapshotID: String?
    @State private var pending: PendingAction?
    /// Tracked so that arriving by Tab can be made visible: a focused List with
    /// nothing selected looks exactly like an unfocused one.
    @FocusState private var listFocused: Bool

    private enum PendingAction: Equatable {
        case create
        case apply(Snapshot)
        case delete(Snapshot)
    }

    private struct Confirmation {
        let title: String
        let message: String
        let button: String
        let perform: () -> Void
    }

    private var group: DiskGroup { library.group(for: disk) }

    private var selectedSnapshot: Snapshot? {
        disk.snapshots.first { $0.id == selectedSnapshotID }
    }

    var body: some View {
        content
            .navigationTitle(group.name)
            .toolbar { toolbar }
            .focusedSceneValue(\.snapshotBoard, actions)
            .sheet(isPresented: Binding(get: { pending == .create },
                                        set: { if !$0 { pending = nil } })) {
                CreateSnapshotSheet(existing: disk.snapshots) { name in
                    Task { await DiskOperations.createSnapshot(named: name, on: disk) }
                }
            }
            .alert(confirmation?.title ?? "",
                   isPresented: Binding(get: { confirmation != nil },
                                        set: { if !$0 { pending = nil } }),
                   presenting: confirmation) { confirmation in
                Button(confirmation.button, role: .destructive, action: confirmation.perform)
                Button("Cancel", role: .cancel) {}
            } message: { confirmation in
                Text(confirmation.message)
            }
            // Re-read when the disk appears or comes back, then follow its file.
            .task(id: disk.availability.isAvailable) {
                await DiskOperations.refresh(disk)
                guard disk.availability.isAvailable else { return }
                for await _ in DiskWatcher.changes(at: disk.url) {
                    await DiskOperations.refresh(disk)
                }
            }
    }

    /// The one rule for menus, toolbar and keys. Nothing is offered while a
    /// sheet or confirmation is up: its key equivalents would reach the menu
    /// and replace what is pending.
    private var actions: SnapshotBoardActions {
        let canMutate = disk.canMutate && pending == nil
        return SnapshotBoardActions(
            disk: disk,
            group: group,
            canCreate: canMutate,
            canApplyOrDelete: canMutate && selectedSnapshot != nil,
            create: { pending = .create },
            apply: { if let snapshot = selectedSnapshot { pending = .apply(snapshot) } },
            delete: { if let snapshot = selectedSnapshot { pending = .delete(snapshot) } },
            refresh: { Task { await library.refresh(disk) } }
        )
    }

    private var confirmation: Confirmation? {
        switch pending {
        case .apply(let snapshot):
            return Confirmation(
                title: String(localized: "Apply Snapshot?"),
                message: String(localized: "Applying \"\(snapshot.name)\" will overwrite the current live state of the disk. This cannot be undone unless you create another snapshot first."),
                button: String(localized: "Apply \"\(snapshot.name)\"")
            ) {
                Task { await DiskOperations.applySnapshot(snapshot, on: disk) }
            }
        case .delete(let snapshot):
            return Confirmation(
                title: String(localized: "Delete Snapshot?"),
                message: String(localized: "Snapshot \"\(snapshot.name)\" will be permanently removed from the disk image."),
                button: String(localized: "Delete \"\(snapshot.name)\"")
            ) {
                if selectedSnapshotID == snapshot.id { selectedSnapshotID = nil }
                Task { await DiskOperations.deleteSnapshot(snapshot, on: disk) }
            }
        case .create, nil:
            return nil
        }
    }

    // MARK: Layout

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            DiskInfoBar(disk: disk, group: group)
            // The same statuses the sidebar shows as badges, in the same order.
            ForEach(DiskStatus.all(for: disk)) { status in
                Divider()
                DiskStatusBanner(status: status)
            }
            Divider()
            if case .unavailable = disk.availability {
                unavailableView
            } else {
                snapshotsHeader
                Divider()
                snapshotArea
            }
            if let error = disk.lastError {
                Divider()
                errorBanner(error)
            }
        }
    }

    // Outside the List, to avoid the Section header artefact.
    private var snapshotsHeader: some View {
        HStack {
            Text("Snapshots")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
    }

    /// The list, or what stands in for it, never both: an empty List would still
    /// take focus from Tab and leave nothing to see. Loading counts only before
    /// the first read, so a background refresh never swaps the empty state out.
    @ViewBuilder
    private var snapshotArea: some View {
        if !disk.snapshots.isEmpty || (disk.isLoading && disk.format == nil) {
            snapshotList
        } else if disk.hasKnownUnsupportedFormat {
            unsupportedFormatView.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if disk.supportsSnapshots {
            emptyStateView.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Otherwise the format is not known yet and nothing is claimed about it;
        // a failed probe leaves readError, whose banner is below.
    }

    private var snapshotList: some View {
        List(selection: $selectedSnapshotID) {
            ForEach(disk.snapshots.reversed()) { snapshot in
                SnapshotRow(
                    snapshot: snapshot,
                    isLastApplied: disk.lastAppliedSnapshotName == snapshot.name,
                    canMutate: disk.canMutate,
                    group: group,
                    disk: disk,
                    onApply: { pending = .apply(snapshot) },
                    onDelete: { pending = .delete(snapshot) }
                )
            }
        }
        .listStyle(.inset)
        .focused($listFocused)
        // Land on the newest snapshot when the list takes focus from the
        // keyboard, so Tab out of the sidebar has a visible result. Only from
        // the keyboard: a click focuses the list before it applies the row it
        // landed on, and selecting here would flash the wrong row for a frame.
        // NSApp.currentEvent is the Tab key press or the mouse-down, and stays
        // set until the next event is dequeued.
        .onChange(of: listFocused) { _, isFocused in
            guard isFocused, NSApp.currentEvent?.type == .keyDown,
                  selectedSnapshotID == nil,
                  let newest = disk.snapshots.last
            else { return }
            selectedSnapshotID = newest.id
        }
        .onDeleteCommand {
            if actions.canApplyOrDelete { actions.delete() }
        }
    }

    // MARK: Empty and unavailable states

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Snapshots Yet", systemImage: "camera")
        } description: {
            Text("Create one from the toolbar above, from the Snapshot menu, or by pressing ⌘N.")
        } actions: {
            Button("New Snapshot…") { pending = .create }
                .buttonStyle(.bordered)
                .disabled(!actions.canCreate)
        }
    }

    private var unsupportedFormatView: some View {
        ContentUnavailableView {
            Label("Snapshots Not Supported", systemImage: "camera")
        } description: {
            Text("Internal snapshots are a feature of the qcow2 format; \(disk.formatDisplayName) images cannot store them. This disk can be inspected here, but not snapshotted.")
        }
    }

    /// The reason is in the banner above; this adds where the file was last
    /// seen and what to do about it.
    private var unavailableView: some View {
        ContentUnavailableView {
            Label("Disk Not Available", systemImage: "internaldrive.fill")
        } description: {
            Text(disk.lastKnownPath)
                .font(.caption)
                .foregroundStyle(.tertiary)
        } actions: {
            Button("Retry") {
                Task { await library.refresh(disk) }
            }
            .buttonStyle(.bordered)
            Button(RevealButtons.containerTitle(for: group.kind, inFinder: false)) {
                NSWorkspace.shared.activateFileViewerSelecting([group.containerURL])
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer()
            Button("Dismiss") { disk.dismissErrors() }
                .font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("New Snapshot", systemImage: "plus.viewfinder") { pending = .create }
                .disabled(!actions.canCreate)
                // Say why the button is greyed out rather than repeat a shortcut
                // the user cannot use; the first status is the most structural.
                .help(DiskStatus.all(for: disk).first?.message ?? String(localized: "Create a new snapshot (⌘N)"))
        }

        ToolbarSpacer(.fixed)

        ToolbarItemGroup(placement: .automatic) {
            Button("Apply", systemImage: "arrow.uturn.backward.circle", action: actions.apply)
                .disabled(!actions.canApplyOrDelete)
                .help("Revert the disk to this snapshot (⌘↩)")

            Button("Delete", systemImage: "trash", role: .destructive, action: actions.delete)
                .disabled(!actions.canApplyOrDelete)
                .help("Permanently delete this snapshot (⌘⌫)")
        }

        ToolbarSpacer(.fixed)

        ToolbarItem(placement: .automatic) {
            Menu("Reveal in Finder", systemImage: "folder") {
                RevealButtons(group: group, disk: disk, withInFinderSuffix: false)
            }
            .help("Reveal in Finder")
        }
    }
}
