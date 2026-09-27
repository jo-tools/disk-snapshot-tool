import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Refuses an unsuitable drag *before* it is dropped, so the "+" badge never
/// appears for a file the app would only reject afterwards. This is why
/// `.dropDestination(for: URL.self)` is not used: it accepts every file URL and
/// offers no way to say no while the drag is in flight.
struct DiskDropDelegate: DropDelegate {
    let accept: ([URL]) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        Self.isAcceptable(info)
    }

    /// This, not validateDrop, governs the drag badge. Without it SwiftUI
    /// proposes .copy for anything the target matched at all.
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: Self.isAcceptable(info) ? .copy : .forbidden)
    }

    /// Judged synchronously, so the item providers cannot be asked to load
    /// their URLs. The drag pasteboard holds the real file URLs and can be read
    /// right now; a drag without any carries nothing the app could add.
    ///
    /// Never judge by an item provider synthesised from a URL: a real Finder
    /// drag puts only `public.file-url` on the pasteboard, so a rule that needs
    /// a concrete type rejects every drop.
    private static func isAcceptable(_ info: DropInfo) -> Bool {
        guard let urls = NSPasteboard(name: .drag).readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty
        else { return false }
        return urls.allSatisfy(DiskImageFile.isAddable)
    }

    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }

        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                guard let item = try? await provider.loadItem(
                    forTypeIdentifier: UTType.fileURL.identifier) else { continue }
                if let url = item as? URL {
                    urls.append(url)
                } else if let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
            if !urls.isEmpty { accept(urls) }
        }
        return true
    }
}
