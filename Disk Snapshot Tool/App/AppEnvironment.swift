import Foundation

/// Where this run of the app keeps the library and the settings.
///
/// A run launched with `DISK_SNAPSHOT_TOOL_STORAGE=scratch` keeps nothing that
/// outlives it. The test plan launches the app that way: Xcode hosts the test
/// bundle inside this very app, so a test run is an app launch, and the user's
/// library and settings are not the tests' to read or rewrite.
enum AppEnvironment {
    static let storageVariable = "DISK_SNAPSHOT_TOOL_STORAGE"

    enum Storage: String {
        case user
        case scratch
    }

    static let storage = Storage(rawValue: ProcessInfo.processInfo.environment[storageVariable] ?? "") ?? .user

    static let libraryStore: LibraryStore = {
        switch storage {
        case .user:
            LibraryStore(fileURL: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(components: "Disk Snapshot Tool", "library.json"))
        case .scratch:
            LibraryStore(fileURL: nil)
        }
    }()

    static let defaults: UserDefaults = {
        switch storage {
        case .user:    return .standard
        case .scratch: return ScratchDefaults(suiteName: nil) ?? .standard
        }
    }()
}
