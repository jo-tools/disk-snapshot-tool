import Foundation
import Observation
import OSLog

/// The user's VM bundles and disk images, in sidebar order.
///
/// Items are never removed on their own. One whose file cannot be reached is
/// kept as unavailable until the user removes it, which is what an item on an
/// unplugged external drive needs.
@Observable
final class Library {
    private(set) var items: [LibraryItem]
    /// Set when an import was refused; the sidebar shows it as an alert.
    var importError: String?

    private let store: LibraryStore

    init(items: [LibraryItem] = [], store: LibraryStore) {
        self.items = items
        self.store = store
    }

    // MARK: Lookup

    var disks: [DiskImage] { items.flatMap(\.disks) }

    func disk(id: UUID) -> DiskImage? {
        disks.first { $0.id == id }
    }

    /// The item a disk belongs to: its VM bundle, or the disk itself.
    func item(containing diskID: UUID) -> LibraryItem? {
        items.first { $0.disks.contains { $0.id == diskID } }
    }

    /// The container a disk is shown under: its VM bundle if it came from one,
    /// otherwise the .utm bundle or plain folder its path is in.
    func group(for disk: DiskImage) -> DiskGroup {
        if case .vm(let vm)? = item(containing: disk.id) {
            return DiskGroup(vm: vm)
        }
        let folder = disk.url.deletingLastPathComponent()
        let parent = folder.deletingLastPathComponent()
        if parent.pathExtension.lowercased() == "utm" {
            return DiskGroup(name: parent.deletingPathExtension().lastPathComponent,
                             kind: .utmVM, containerURL: parent)
        }
        return DiskGroup(name: folder.lastPathComponent, kind: .folder, containerURL: folder)
    }

    /// Compared with symlinks resolved, as security-scoped bookmarks resolve them.
    private static func identity(of url: URL) -> String {
        SidebarSelection.key(for: url.resolvingSymlinksInPath())
    }

    /// Whether the file is listed already, on its own or inside a listed VM.
    private func lists(_ url: URL) -> Bool {
        let path = Self.identity(of: url)
        return items.contains { item in
            switch item {
            case .vm(let vm):
                let bundle = Self.identity(of: vm.url)
                return path == bundle || path.hasPrefix(bundle + "/")
            case .disk(let disk):
                return path == Self.identity(of: disk.url)
            }
        }
    }

    /// Loose disks already listed from inside the bundle at `url`, which would
    /// otherwise end up with two rows for one container.
    private func looseDisks(inside url: URL) -> [DiskImage] {
        let bundle = Self.identity(of: url) + "/"
        return items.compactMap { item in
            guard case .disk(let disk) = item, Self.identity(of: disk.url).hasPrefix(bundle) else { return nil }
            return disk
        }
    }

    // MARK: Loading and refreshing

    /// Reads library.json and each reachable bundle's drive list. Nothing is
    /// probed yet, but every row exists, so a saved selection can be restored.
    func load() {
        items = store.load().map { record in
            switch record {
            case .vmBundle(let r):
                let vm: VMBundle
                if let reopened = SecurityScope.reopen(r.bookmarkData, name: r.cachedName) {
                    vm = VMBundle(id: r.id, name: r.cachedName, url: reopened.url, bookmarkData: reopened.bookmarkData)
                    vm.availability = reopened.availability
                    if vm.availability.isAvailable { readDrives(of: vm) }
                } else {
                    vm = VMBundle(id: r.id, name: r.cachedName, url: URL(filePath: r.cachedPath), bookmarkData: r.bookmarkData)
                    vm.availability = .unavailable(reason: String(localized: "Its saved location could not be resolved."))
                }
                return .vm(vm)
            case .diskImage(let r):
                let disk: DiskImage
                if let reopened = SecurityScope.reopen(r.bookmarkData, name: r.cachedLabel) {
                    disk = DiskImage(id: r.id, label: r.cachedLabel, url: reopened.url, bookmarkData: reopened.bookmarkData)
                    disk.availability = reopened.availability
                } else {
                    disk = DiskImage(id: r.id, label: r.cachedLabel, url: URL(filePath: r.cachedPath), bookmarkData: r.bookmarkData)
                    disk.availability = .unavailable(reason: String(localized: "Its saved location could not be resolved."))
                }
                return .disk(disk)
            }
        }
        Logger.library.info("Loaded \(self.items.count, privacy: .public) item(s)")
    }

    func refreshAll() async {
        for item in items {
            switch item {
            case .vm(let vm):     await refreshVM(vm)
            case .disk(let disk): await DiskOperations.refresh(disk)
            }
        }
        save()
    }

    /// For Retry and ⌘R: a disk whose VM went out of reach comes back with its VM.
    func refresh(_ disk: DiskImage) async {
        if case .vm(let vm)? = item(containing: disk.id), !vm.availability.isAvailable {
            await refreshVM(vm)
            save()
        } else {
            await DiskOperations.refresh(disk)
        }
    }

    /// Brings back what went out of reach — a reconnected drive, a moved or
    /// renamed file — without a relaunch. Runs whenever the app is activated.
    func refreshUnavailable() async {
        var reopenedAny = false
        for item in items {
            switch item {
            case .vm(let vm) where !vm.availability.isAvailable || vm.disks.contains(where: { !$0.availability.isAvailable }):
                await refreshVM(vm)
                reopenedAny = true
            case .disk(let disk) where !disk.availability.isAvailable:
                await DiskOperations.refresh(disk)
                reopenedAny = true
            default:
                break
            }
        }
        if reopenedAny { save() }
    }

    private func refreshVM(_ vm: VMBundle) async {
        if !vm.availability.isAvailable || !SecurityScope.isReachable(vm.url),
           let reopened = SecurityScope.reopen(vm.bookmarkData, name: vm.name) {
            vm.url = reopened.url
            vm.bookmarkData = reopened.bookmarkData
        }
        guard SecurityScope.isReachable(vm.url) else {
            Logger.library.warning("VM '\(vm.name, privacy: .public)' not reachable")
            vm.availability = .unavailable(reason: String(localized: "The VM bundle is not currently accessible."))
            for disk in vm.disks {
                disk.availability = .unavailable(reason: String(localized: "The VM containing this disk image is not accessible."))
                disk.isInUse = false
            }
            return
        }
        vm.availability = .available
        vm.recordCurrentPath()
        readDrives(of: vm)
        for disk in vm.disks { await DiskOperations.refresh(disk) }
    }

    /// Re-reads the drive list and the VM's name, keeping the existing object
    /// for each drive that is still there so its loaded state and identity
    /// survive. Its location is taken over, since the bundle may have moved.
    private func readDrives(of vm: VMBundle) {
        guard let config = try? UTMBundleReader.readConfig(at: vm.url) else { return }
        vm.name = config.information.name
        let existing = Dictionary(uniqueKeysWithValues: vm.disks.map { ($0.id, $0) })
        vm.disks = UTMBundleReader.disks(for: vm, config: config).map { fresh in
            guard let disk = existing[fresh.id] else { return fresh }
            disk.url = fresh.url
            disk.bookmarkData = fresh.bookmarkData
            return disk
        }
    }

    // MARK: Adding and removing

    /// Adds a .utm bundle. Returns nil if it is already listed or cannot be read.
    func importVM(at url: URL) async -> VMBundle? {
        guard !lists(url) else {
            Logger.library.info("Already in library: \(url.lastPathComponent, privacy: .public)")
            return nil
        }
        guard looseDisks(inside: url).isEmpty else {
            importError = String(localized: "\"\(url.lastPathComponent)\" contains disk images that are already listed on their own. Remove them from the list first.")
            return nil
        }
        do {
            let bookmark = try SecurityScope.bookmark(for: url)
            let resolvedURL = SecurityScope.resolve(bookmark)?.url ?? url
            let vm = try UTMBundleReader.makeBundle(at: resolvedURL, bookmark: bookmark)
            // Probe before the rows appear, so badges, sizes and the board are
            // filled in from the start rather than as each disk is clicked.
            for disk in vm.disks { await DiskOperations.refresh(disk) }
            // Checked again: the same bundle may have been added while this one was probed.
            guard !lists(resolvedURL) else { return nil }
            items.append(.vm(vm))
            save()
            Logger.library.info("Added VM '\(vm.name, privacy: .public)' with \(vm.disks.count, privacy: .public) disk(s)")
            return vm
        } catch {
            Logger.library.error("Adding VM failed: \(error, privacy: .public)")
            importError = String(localized: "\"\(url.lastPathComponent)\" could not be added: \(error.localizedDescription)")
            return nil
        }
    }

    /// Adds a disk image on its own. Returns nil if it is already listed or
    /// qemu-img cannot read it.
    func importDisk(at url: URL) async -> DiskImage? {
        guard !lists(url) else {
            Logger.library.info("Already in library: \(url.lastPathComponent, privacy: .public)")
            return nil
        }
        do {
            let bookmark = try SecurityScope.bookmark(for: url)
            let resolvedURL = SecurityScope.resolve(bookmark)?.url ?? url
            let disk = DiskImage(label: url.lastPathComponent, url: resolvedURL, bookmarkData: bookmark)

            // A readability check, not a format check: qemu-img reports anything
            // it does not recognise as "raw", and non-qcow2 images are meant to
            // be listed.
            await DiskOperations.refresh(disk)
            guard disk.readError == nil, disk.format != nil else {
                Logger.library.warning("Rejected '\(disk.label, privacy: .public)': qemu-img could not read it")
                importError = String(localized: "\"\(disk.label)\" could not be read by qemu-img, so it was not added.")
                return nil
            }
            guard !lists(resolvedURL) else { return nil }
            items.append(.disk(disk))
            save()
            Logger.library.info("Added disk '\(disk.label, privacy: .public)' (\(disk.format ?? "?", privacy: .public))")
            return disk
        } catch {
            Logger.library.error("Adding disk failed: \(error, privacy: .public)")
            importError = String(localized: "\"\(url.lastPathComponent)\" could not be added: \(error.localizedDescription)")
            return nil
        }
    }

    func remove(ids: [UUID]) {
        items.removeAll { ids.contains($0.id) }
        save()
    }

    func reorder(_ newItems: [LibraryItem]) {
        items = newItems
        save()
    }

    private func save() {
        store.save(items.map(LibraryRecord.init))
    }
}
