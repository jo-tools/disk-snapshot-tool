import SwiftUI
import AppKit

/// The "Reveal in Finder" pair every menu offers: the container first, then
/// the file when the menu is about one file.
struct RevealButtons: View {
    let group: DiskGroup
    /// nil for a row that stands for several files.
    var disk: DiskImage?
    /// False inside a menu already titled "Reveal in Finder".
    var withInFinderSuffix = true
    var containerShortcut: KeyboardShortcut?

    /// Whole phrases rather than a noun and a suffix pieced together, which
    /// would not survive translation.
    static func containerTitle(for kind: DiskGroup.Kind, inFinder: Bool) -> LocalizedStringKey {
        switch (kind, inFinder) {
        case (.utmVM, true):   return "Reveal VM Bundle in Finder"
        case (.utmVM, false):  return "Reveal VM Bundle"
        case (.folder, true):  return "Reveal Enclosing Folder in Finder"
        case (.folder, false): return "Reveal Enclosing Folder"
        }
    }

    var body: some View {
        Button(Self.containerTitle(for: group.kind, inFinder: withInFinderSuffix), systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([group.containerURL])
        }
        .keyboardShortcut(containerShortcut)
        if let disk {
            Button(withInFinderSuffix ? "Reveal Disk File in Finder" : "Reveal Disk File",
                   systemImage: "internaldrive") {
                NSWorkspace.shared.activateFileViewerSelecting([disk.url])
            }
        }
    }
}
