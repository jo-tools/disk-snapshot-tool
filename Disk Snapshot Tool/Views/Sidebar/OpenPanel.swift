import AppKit

/// The Open panel, vetting names the way a drop does. SwiftUI's fileImporter
/// filters by type only: .img shares its type with .dmg, and a .utm bundle is
/// a plain folder on a Mac without UTM, so choosing one would need every
/// folder to be choosable.
enum OpenPanel {
    static func run(completion: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.prompt = String(localized: "Add", comment: "Open panel confirm button")
        panel.message = String(localized: "Choose disk images or UTM virtual machines.")
        let delegate = Delegate()
        panel.delegate = delegate
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            withExtendedLifetime(delegate) {
                if response == .OK { completion(panel.urls) }
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    private final class Delegate: NSObject, NSOpenSavePanelDelegate {
        /// Folders stay enabled so they can be opened and browsed.
        func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
            DiskImageFile.isAddable(url) || (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }

        func panel(_ sender: Any, validate url: URL) throws {
            guard !DiskImageFile.isAddable(url) else { return }
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnsupportedSchemeError, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "\"\(url.lastPathComponent)\" is neither a disk image nor a UTM virtual machine.")
            ])
        }
    }
}
