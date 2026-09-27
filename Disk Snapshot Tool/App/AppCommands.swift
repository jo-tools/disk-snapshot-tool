import SwiftUI

struct SnapshotBoardActions {
    let disk: DiskImage
    let group: DiskGroup
    let canCreate: Bool
    let canApplyOrDelete: Bool
    let create: () -> Void
    let apply: () -> Void
    let delete: () -> Void
    let refresh: () -> Void
}

struct SidebarActions {
    let openImporter: () -> Void
    /// nil when no row is selected.
    let removeSelected: (() -> Void)?
}

extension FocusedValues {
    @Entry var snapshotBoard: SnapshotBoardActions?
    @Entry var sidebar: SidebarActions?
}

/// The menu bar. Every item acts through a focused-scene value the views
/// publish, so the same code decides what is possible in menus, toolbar and
/// context menus.
struct AppCommands: Commands {
    @FocusedValue(\.snapshotBoard) private var board
    @FocusedValue(\.sidebar) private var sidebar
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Disk Image or VM…", systemImage: "folder.badge.plus") {
                sidebar?.openImporter()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(sidebar == nil)

            Divider()

            Button("Remove from List", systemImage: "minus.circle") {
                sidebar?.removeSelected?()
            }
            .disabled(sidebar?.removeSelected == nil)
        }

        CommandGroup(after: .sidebar) {
            Button("Refresh", systemImage: "arrow.clockwise") {
                board?.refresh()
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(board == nil)
        }

        // Same order as the board's toolbar: New | Apply Delete | Reveal.
        CommandMenu("Snapshot") {
            Button("New Snapshot…", systemImage: "plus.viewfinder") {
                board?.create()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(board?.canCreate != true)

            Divider()

            Button("Apply / Revert", systemImage: "arrow.uturn.backward.circle") {
                board?.apply()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(board?.canApplyOrDelete != true)

            Button("Delete Snapshot", systemImage: "trash") {
                board?.delete()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(board?.canApplyOrDelete != true)

            Divider()

            Menu("Reveal in Finder", systemImage: "folder") {
                if let board {
                    RevealButtons(group: board.group, disk: board.disk, withInFinderSuffix: false,
                                  containerShortcut: KeyboardShortcut("r", modifiers: [.command, .shift]))
                }
            }
            .disabled(board == nil)
        }

        // Replaces the stock "Disk Snapshot Tool Help", which opens a help book
        // that does not exist. The license items show the copies the build put
        // in Contents/Resources, in the app's own window — offline, and exactly
        // what this copy of the app ships.
        CommandGroup(replacing: .help) {
            Button("Disk Snapshot Tool on GitHub", systemImage: "chevron.left.forwardslash.chevron.right") {
                About.open(About.repositoryURL)
            }
            Button("Report an Issue…", systemImage: "exclamationmark.bubble") {
                About.open(About.issuesURL)
            }

            Divider()

            documentButton(.license, systemImage: "doc.text")
            documentButton(.thirdPartyNotices, systemImage: "doc.text.magnifyingglass")

            Menu("Third-Party Licenses", systemImage: "books.vertical") {
                ForEach(LegalDocument.fullTexts) { document in
                    documentButton(document, systemImage: nil)
                }
            }

            Divider()

            Button("Support this Project…", systemImage: "heart") {
                About.open(About.donationURL)
            }
        }
    }

    /// Opens a licensing document in the app's window, and disables itself if
    /// the build did not copy that file in, rather than opening an empty window.
    private func documentButton(_ document: LegalDocument, systemImage: String?) -> some View {
        Button {
            openWindow(id: LegalDocument.windowID, value: document)
        } label: {
            if let systemImage {
                Label(document.title, systemImage: systemImage)
            } else {
                Text(document.title)
            }
        }
        .disabled(!document.isAvailable)
    }
}
