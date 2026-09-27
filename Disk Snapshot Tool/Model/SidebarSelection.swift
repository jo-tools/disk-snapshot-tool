import Foundation

/// The selected sidebar row: a disk image, or the container row above it.
///
/// A container is identified by its path because that is all it is: DiskGroup
/// is derived from a disk's URL and has no identity of its own.
enum SidebarSelection: Hashable {
    case disk(UUID)
    /// Always built through `container(_:)` so the path is normalised; a
    /// selection that spells a row's path differently from the row's tag
    /// matches nothing.
    case container(path: String)

    /// A container's identity, shared with the collapsed-rows set so a row
    /// cannot be selected under one spelling and remembered under another.
    static func key(for containerURL: URL) -> String {
        var path = containerURL.standardizedFileURL.path(percentEncoded: false)
        if path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path
    }

    static func container(_ containerURL: URL) -> SidebarSelection {
        .container(path: key(for: containerURL))
    }

    var diskID: UUID? {
        if case .disk(let id) = self { return id }
        return nil
    }

    var containerPath: String? {
        if case .container(let path) = self { return path }
        return nil
    }

    /// One string for UserDefaults. Only the first colon separates; a path may
    /// contain more.
    var storageKey: String {
        switch self {
        case .disk(let id):        return "disk:\(id.uuidString)"
        case .container(let path): return "container:\(path)"
        }
    }

    init?(storageKey: String) {
        guard let separator = storageKey.firstIndex(of: ":") else { return nil }
        let kind = String(storageKey[storageKey.startIndex..<separator])
        let value = String(storageKey[storageKey.index(after: separator)...])
        switch kind {
        case "disk":
            guard let id = UUID(uuidString: value) else { return nil }
            self = .disk(id)
        case "container":
            guard !value.isEmpty else { return nil }
            self = .container(path: value)
        default:
            return nil
        }
    }
}
