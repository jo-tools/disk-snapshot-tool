import Foundation
import Observation
import OSLog

/// One top-level sidebar row and the disk rows under it: a VM bundle from the
/// library, or the folder that a set of separately added disk images share.
struct SidebarContainer: Identifiable {
    let group: DiskGroup
    let disks: [DiskImage]
    /// The library items this row stands for — the bundle, or every disk in the folder.
    let itemIDs: [UUID]
    let availability: Availability
    /// Whether the row is a library item itself rather than a grouping of several.
    let isBundle: Bool

    var name: String { group.name }
    var path: String { SidebarSelection.key(for: group.containerURL) }
    var id: String { (isBundle ? "vm:" : "group:") + path }
}

struct SidebarRow: Identifiable {
    enum Kind {
        case container
        case disk(DiskImage)
    }

    let kind: Kind
    let container: SidebarContainer
    let containerIndex: Int
    /// The row a drop "after this container" is drawn under.
    let isLastInContainer: Bool

    var id: String {
        switch kind {
        case .container:       return container.id
        case .disk(let disk):  return "disk:\(disk.id.uuidString)"
        }
    }
}

/// The sidebar's view state: which row is selected and which containers are
/// collapsed, both kept across launches in UserDefaults. The rows themselves
/// are derived from the library.
@Observable
final class SidebarModel {
    struct RemovalTarget: Identifiable {
        let id = UUID()
        let name: String
        let itemIDs: [UUID]
    }

    private enum Keys {
        static let selection = "sidebarSelection"
        static let collapsed = "collapsedContainers"
    }

    let library: Library
    private let defaults: UserDefaults

    /// Container rows are selectable too, so the keyboard can reach them to
    /// expand, collapse or open a context menu.
    var selection: SidebarSelection? {
        didSet {
            guard selection != oldValue else { return }
            defaults.set(selection?.storageKey, forKey: Keys.selection)
        }
    }

    /// Container paths the user has collapsed. Anything not listed is open,
    /// so a newly added row arrives expanded.
    private(set) var collapsed: Set<String> {
        didSet { defaults.set(Array(collapsed), forKey: Keys.collapsed) }
    }

    init(library: Library, defaults: UserDefaults) {
        self.library = library
        self.defaults = defaults
        self.collapsed = Set(defaults.stringArray(forKey: Keys.collapsed) ?? [])
    }

    // MARK: Rows

    var containers: [SidebarContainer] {
        var rows: [SidebarContainer] = []
        var seenFolders: Set<String> = []
        for item in library.items {
            switch item {
            case .vm(let vm):
                rows.append(SidebarContainer(group: DiskGroup(vm: vm), disks: vm.disks,
                                             itemIDs: [vm.id], availability: vm.availability, isBundle: true))
            case .disk(let disk):
                let group = library.group(for: disk)
                let key = SidebarSelection.key(for: group.containerURL)
                guard seenFolders.insert(key).inserted else { continue }
                let siblings = library.items.compactMap { item -> DiskImage? in
                    guard case .disk(let d) = item,
                          SidebarSelection.key(for: library.group(for: d).containerURL) == key else { return nil }
                    return d
                }
                // A folder's images are shown alphabetically; a VM's keep config.plist order.
                // A folder is reachable by construction, so only its disks can raise a badge.
                rows.append(SidebarContainer(
                    group: group,
                    disks: siblings.sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending },
                    itemIDs: siblings.map(\.id), availability: .available, isBundle: false))
            }
        }
        return rows
    }

    func container(atPath path: String) -> SidebarContainer? {
        containers.first { $0.path == path }
    }

    var rows: [SidebarRow] {
        containers.enumerated().flatMap { index, container -> [SidebarRow] in
            let disks = isExpanded(container.group.containerURL) ? container.disks : []
            var rows = [SidebarRow(kind: .container, container: container, containerIndex: index,
                                   isLastInContainer: disks.isEmpty)]
            for (offset, disk) in disks.enumerated() {
                rows.append(SidebarRow(kind: .disk(disk), container: container, containerIndex: index,
                                       isLastInContainer: offset == disks.count - 1))
            }
            return rows
        }
    }

    var selectedDisk: DiskImage? {
        selection?.diskID.flatMap(library.disk(id:))
    }

    var selectedContainer: SidebarContainer? {
        selection?.containerPath.flatMap(container(atPath:))
    }

    // MARK: Expansion

    func isExpanded(_ containerURL: URL) -> Bool {
        !collapsed.contains(SidebarSelection.key(for: containerURL))
    }

    func setExpanded(_ expanded: Bool, for containerURL: URL) {
        let key = SidebarSelection.key(for: containerURL)
        if expanded { collapsed.remove(key) } else { collapsed.insert(key) }
    }

    /// Forgets containers that no longer have a row, so "collapsed" only ever
    /// describes a row that exists and a re-added file cannot inherit the
    /// collapsed state of the row it used to be in.
    private func pruneCollapsed() {
        let live = collapsed.filter { container(atPath: $0) != nil }
        guard live.count < collapsed.count else { return }
        Logger.sidebar.info("Forgot \(self.collapsed.count - live.count, privacy: .public) collapsed container(s) with no rows left")
        collapsed = live
    }

    // MARK: Selection

    /// Restores the last selection, opening the container that holds it, and
    /// forgets collapsed rows that are gone since.
    func restore() {
        pruneCollapsed()
        guard let stored = defaults.string(forKey: Keys.selection),
              let restored = SidebarSelection(storageKey: stored) else {
            Logger.sidebar.info("No saved selection")
            return
        }
        switch restored {
        case .disk(let id):
            guard let disk = library.disk(id: id) else {
                Logger.sidebar.info("Saved disk is no longer in the library")
                return
            }
            setExpanded(true, for: library.group(for: disk).containerURL)
        case .container(let path):
            guard container(atPath: path) != nil else {
                Logger.sidebar.info("Saved container is no longer in the library")
                return
            }
        }
        selection = restored
        Logger.sidebar.info("Restored selection: \(stored, privacy: .public)")
    }

    private func dropInvalidSelection() {
        switch selection {
        case .disk(let id) where library.disk(id: id) == nil:           selection = nil
        case .container(let path) where container(atPath: path) == nil: selection = nil
        default: break
        }
    }

    // MARK: Keyboard

    /// ← on a container closes it; on a disk it steps up to the container.
    /// Returns false when there is nothing to do, so the key keeps its other meanings.
    func collapseOrGoToParent() -> Bool {
        switch selection {
        case .container(let path):
            guard let row = container(atPath: path), isExpanded(row.group.containerURL) else { return false }
            setExpanded(false, for: row.group.containerURL)
            return true
        case .disk(let id):
            guard let parent = containers.first(where: { $0.disks.contains { $0.id == id } }) else { return false }
            selection = .container(parent.group.containerURL)
            return true
        case nil:
            return false
        }
    }

    /// → opens the selected container, or steps into one that is already open.
    func expandOrGoToFirstChild() -> Bool {
        guard case .container(let path)? = selection, let row = container(atPath: path) else { return false }
        if !isExpanded(row.group.containerURL) {
            setExpanded(true, for: row.group.containerURL)
            return true
        }
        guard let first = row.disks.first else { return false }
        selection = .disk(first.id)
        return true
    }

    // MARK: Adding, removing, reordering

    /// Adds a file the user opened or dropped and opens the row it lands in.
    func add(_ url: URL) async {
        guard DiskImageFile.isAddable(url) else {
            Logger.sidebar.warning("Ignored '\(url.lastPathComponent, privacy: .public)': not a VM bundle or disk image name")
            return
        }
        if url.pathExtension.lowercased() == "utm" {
            if let vm = await library.importVM(at: url) {
                setExpanded(true, for: vm.url)
            }
        } else if let disk = await library.importDisk(at: url) {
            setExpanded(true, for: library.group(for: disk).containerURL)
        }
    }

    func removalTarget(for container: SidebarContainer) -> RemovalTarget {
        RemovalTarget(name: container.name, itemIDs: container.itemIDs)
    }

    /// A disk row removes the library item it belongs to — for a VM's disk that
    /// is the whole bundle, since a VM's disks are not separable.
    func removalTarget(forDisk disk: DiskImage) -> RemovalTarget? {
        guard let item = library.item(containing: disk.id) else { return nil }
        return RemovalTarget(name: item.displayName, itemIDs: [item.id])
    }

    var selectedRemovalTarget: RemovalTarget? {
        if let container = selectedContainer { return removalTarget(for: container) }
        if let disk = selectedDisk { return removalTarget(forDisk: disk) }
        return nil
    }

    func remove(_ target: RemovalTarget) {
        library.remove(ids: target.itemIDs)
        pruneCollapsed()
        dropInvalidSelection()
    }

    // MARK: Dragging containers

    static let dragPayloadPrefix = "disk-snapshot-tool-container:"

    func dragPayload(for container: SidebarContainer) -> String {
        Self.dragPayloadPrefix + container.id
    }

    private func containerIndex(fromDragPayload payload: String) -> Int? {
        guard payload.hasPrefix(Self.dragPayloadPrefix) else { return nil }
        let id = payload.dropFirst(Self.dragPayloadPrefix.count)
        return containers.firstIndex { $0.id == id }
    }

    /// The position in `containers` a drop over `row` would move the dragged
    /// container to, or nil where the drop would change nothing.
    func dropPosition(over row: SidebarRow, inLowerHalf: Bool, dragging payload: String) -> Int? {
        guard let source = containerIndex(fromDragPayload: payload) else { return nil }
        let position: Int
        switch row.kind {
        case .container: position = inLowerHalf ? row.containerIndex + 1 : row.containerIndex
        case .disk:      position = row.containerIndex + 1
        }
        guard position != source, position != source + 1 else { return nil }
        return position
    }

    func moveContainer(dragging payload: String, to position: Int) {
        guard let source = containerIndex(fromDragPayload: payload),
              position != source, position != source + 1 else { return }
        var reordered = containers
        let moving = reordered.remove(at: source)
        reordered.insert(moving, at: position > source ? position - 1 : position)
        let byID = Dictionary(uniqueKeysWithValues: library.items.map { ($0.id, $0) })
        library.reorder(reordered.flatMap(\.itemIDs).compactMap { byID[$0] })
    }
}
