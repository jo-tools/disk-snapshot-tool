import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct DiskSnapshotToolApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var library: Library
    @State private var sidebar: SidebarModel

    init() {
        let library = Library(store: AppEnvironment.libraryStore)
        _library = State(initialValue: library)
        _sidebar = State(initialValue: SidebarModel(library: library, defaults: AppEnvironment.defaults))
        DiskOperations.use(AppliedSnapshotStore(defaults: AppEnvironment.defaults))
    }

    var body: some Scene {
        // A single Window rather than a WindowGroup: closing it while a license
        // window stays open must leave a way back, which the Window menu offers.
        Window("Disk Snapshot Tool", id: "main") {
            MainView()
                .environment(library)
                .environment(sidebar)
        }
        .commands { AppCommands() }
        // A test run hosts its bundle in this app; it has no use for the window,
        // and a window would record its frame and state in the user's defaults.
        .defaultLaunchBehavior(AppEnvironment.storage == .scratch ? .suppressed : .automatic)
        .restorationBehavior(AppEnvironment.storage == .scratch ? .disabled : .automatic)

        // One window per document. Opening the same document twice brings the
        // existing window forward rather than stacking another one.
        WindowGroup(id: LegalDocument.windowID, for: LegalDocument.self) { $document in
            LegalDocumentView(document: document ?? .thirdPartyNotices)
        }
        .defaultSize(width: 720, height: 680)
        .commandsRemoved()
    }
}
