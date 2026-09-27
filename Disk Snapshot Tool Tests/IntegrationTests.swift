import Testing
import Foundation
import Darwin
@testable import Disk_Snapshot_Tool

/// Runs inside the sandboxed host app, so app-scoped bookmarks and the bundled
/// qemu-img both behave as they do in real use.
@Suite(.serialized)
final class IntegrationTests {
    private let dir: URL
    private let helper: URL

    init() throws {
        DiskOperations.use(AppliedSnapshotStore(defaults: ScratchDefaults(suiteName: nil)!))
        dir = FileManager.default.temporaryDirectory.appending(component: "IntegrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        helper = Bundle.main.bundleURL.appending(components: "Contents", "Helpers", "qemu-img")
    }

    deinit {
        try? FileManager.default.removeItem(at: dir)
    }

    private func qemuImg(_ args: String...) throws {
        let p = Process()
        p.executableURL = helper
        p.arguments = args
        p.standardOutput = nil
        try p.run()
        p.waitUntilExit()
        try #require(p.terminationStatus == 0, "qemu-img \(args.joined(separator: " "))")
    }

    private func makeBundle(named name: String) throws -> URL {
        let bundle = dir.appending(component: "\(name).utm", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bundle.appending(component: "Data"), withIntermediateDirectories: true)
        try qemuImg("create", "-f", "qcow2", bundle.appending(components: "Data", "disk.qcow2").path(percentEncoded: false), "16M")
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
          <key>Information</key><dict><key>Name</key><string>\(name)</string></dict>
          <key>Drive</key><array>
            <dict><key>Identifier</key><string>drive0</string><key>ImageName</key><string>disk.qcow2</string>
                  <key>ImageType</key><string>Disk</string><key>Interface</key><string>VirtIO</string></dict>
            <dict><key>Identifier</key><string>cd0</string><key>ImageType</key><string>CD</string></dict>
          </array>
        </dict></plist>
        """
        try Data(plist.utf8).write(to: bundle.appending(component: "config.plist"))
        return bundle
    }

    @Test func bundleIsReadAndItsDisksProbed() async throws {
        let bundleURL = try makeBundle(named: "Fixture VM")
        let vm = try UTMBundleReader.makeBundle(at: bundleURL, bookmark: try SecurityScope.bookmark(for: bundleURL))
        #expect(vm.name == "Fixture VM")
        #expect(vm.disks.map(\.label) == ["disk.qcow2"])
        #expect(vm.disks[0].imageType == "Disk" && vm.disks[0].interface == "VirtIO")

        await DiskOperations.refresh(vm.disks[0])
        #expect(vm.disks[0].availability == .available)
        #expect(vm.disks[0].format == "qcow2")
        #expect(vm.disks[0].virtualSize == 16 * 1024 * 1024)
        #expect(vm.disks[0].snapshots.isEmpty)
        #expect(vm.disks[0].lastError == nil)
    }

    @Test func libraryRoundTripsThroughBookmarks() async throws {
        let bundleURL = try makeBundle(named: "Round Trip")
        let rawURL = dir.appending(component: "plain.img")
        try qemuImg("create", "-f", "raw", rawURL.path(percentEncoded: false), "4M")

        let store = LibraryStore(fileURL: dir.appending(component: "library.json"))
        let library = Library(store: store)
        let vm = try #require(await library.importVM(at: bundleURL))
        let raw = try #require(await library.importDisk(at: rawURL))
        #expect(raw.format == "raw" && !raw.supportsSnapshots)
        #expect(await library.importDisk(at: rawURL) == nil, "already listed")
        #expect(library.importError == nil)

        let reloaded = Library(store: store)
        reloaded.load()
        #expect(reloaded.items.map(\.id) == [vm.id, raw.id])
        for disk in reloaded.disks {
            #expect(disk.availability == .available, "\(disk.label)")
        }
        guard case .vm(let vm2) = reloaded.items[0] else { Issue.record("first item is not the VM"); return }
        #expect(vm2.name == "Round Trip")
        await reloaded.refreshAll()
        #expect(vm2.disks.map(\.label) == ["disk.qcow2"])
        #expect(vm2.disks[0].id == vm.disks[0].id, "disk ids are stable across launches")
        #expect(vm2.disks[0].format == "qcow2")
    }

    @Test func rejectsWhatQemuImgCannotRead() async throws {
        let bogus = dir.appending(component: "notes.qcow2")
        try Data("just text".utf8).write(to: bogus)
        let library = Library(store: LibraryStore(fileURL: dir.appending(component: "library.json")))
        // qemu-img reports unknown files as raw, so a text file is accepted, as designed.
        let disk = try #require(await library.importDisk(at: bogus))
        #expect(disk.format == "raw")

        let missing = dir.appending(component: "missing.qcow2")
        #expect(await library.importDisk(at: missing) == nil)
        #expect(library.importError?.contains("missing.qcow2") == true)
    }

    @Test func snapshotLifecycle() async throws {
        let url = dir.appending(component: "life.qcow2")
        try qemuImg("create", "-f", "qcow2", url.path(percentEncoded: false), "16M")
        let disk = DiskImage(label: "life.qcow2", url: url, bookmarkData: try SecurityScope.bookmark(for: url))

        await DiskOperations.refresh(disk)
        #expect(disk.canMutate)

        await DiskOperations.createSnapshot(named: "first", on: disk)
        await DiskOperations.createSnapshot(named: "second", on: disk)
        #expect(disk.snapshots.map(\.name) == ["first", "second"])
        #expect(disk.lastAppliedSnapshotName == "second")
        #expect(disk.lastError == nil)

        await DiskOperations.applySnapshot(disk.snapshots[0], on: disk)
        #expect(disk.lastAppliedSnapshotName == "first")

        await DiskOperations.deleteSnapshot(disk.snapshots[1], on: disk)
        #expect(disk.snapshots.map(\.name) == ["first"])
        #expect(disk.lastAppliedSnapshotName == "first", "deleting another snapshot keeps the applied one")

        await DiskOperations.deleteSnapshot(disk.snapshots[0], on: disk)
        #expect(disk.snapshots.isEmpty)
        #expect(disk.lastAppliedSnapshotName == nil)
    }

    @Test func failedMutationKeepsItsError() async throws {
        let url = dir.appending(component: "failing.qcow2")
        try qemuImg("create", "-f", "qcow2", url.path(percentEncoded: false), "16M")
        let disk = DiskImage(label: "failing.qcow2", url: url, bookmarkData: try SecurityScope.bookmark(for: url))
        await DiskOperations.refresh(disk)

        // qemu-img fails, then the re-read afterwards succeeds.
        await DiskOperations.deleteSnapshot(Snapshot(id: "9", name: "ghost", date: .now, vmStateSize: 0), on: disk)
        #expect(disk.operationError == QemuImgError.snapshotNotFound.localizedDescription)
        #expect(disk.format == "qcow2")

        await DiskOperations.refresh(disk)
        #expect(disk.operationError != nil, "only Dismiss or the next operation clears it")
    }

    /// qcow2 accepts a tag twice; only the ID tells the two apart.
    @Test func duplicateTagsAreHandledByID() async throws {
        let url = dir.appending(component: "dup.qcow2")
        try qemuImg("create", "-f", "qcow2", url.path(percentEncoded: false), "16M")
        try qemuImg("snapshot", "-c", "dup", url.path(percentEncoded: false))
        try qemuImg("snapshot", "-c", "dup", url.path(percentEncoded: false))
        let disk = DiskImage(label: "dup.qcow2", url: url, bookmarkData: try SecurityScope.bookmark(for: url))
        await DiskOperations.refresh(disk)
        #expect(disk.snapshots.map(\.id) == ["1", "2"])

        await DiskOperations.createSnapshot(named: "dup", on: disk)
        #expect(disk.snapshots.count == 2, "a third 'dup' is refused")

        await DiskOperations.applySnapshot(disk.snapshots[1], on: disk)
        #expect(disk.operationError == nil)

        await DiskOperations.deleteSnapshot(disk.snapshots[1], on: disk)
        #expect(disk.snapshots.map(\.id) == ["1", "2"], "qemu-img would have deleted ID 1")
        #expect(disk.operationError != nil)

        await DiskOperations.deleteSnapshot(disk.snapshots[0], on: disk)
        #expect(disk.snapshots.map(\.id) == ["2"])
    }

    /// More than a pipe buffer of JSON: qemu-img must not block on a full pipe.
    @Test(.timeLimit(.minutes(1))) func largeInfoOutputIsRead() async throws {
        let url = dir.appending(component: "many.qcow2")
        try qemuImg("create", "-f", "qcow2", url.path(percentEncoded: false), "16M")
        let longName = String(repeating: "n", count: 240)
        for index in 0..<180 {
            try qemuImg("snapshot", "-c", "\(index)-\(longName)", url.path(percentEncoded: false))
        }
        let disk = DiskImage(label: "many.qcow2", url: url, bookmarkData: try SecurityScope.bookmark(for: url))
        await DiskOperations.refresh(disk)
        #expect(disk.snapshots.count == 180)
    }

    @Test func heldWriteLockBlocksMutations() async throws {
        let url = dir.appending(component: "locked.qcow2")
        try qemuImg("create", "-f", "qcow2", url.path(percentEncoded: false), "16M")
        let disk = DiskImage(label: "locked.qcow2", url: url, bookmarkData: try SecurityScope.bookmark(for: url))
        await DiskOperations.refresh(disk)
        #expect(!disk.isInUse)

        // Hold QEMU's write-share byte the way a running VM does.
        let fd = open(url.path(percentEncoded: false), O_RDWR)
        try #require(fd >= 0)
        defer { close(fd) }
        var lock = flock(l_start: 201, l_len: 1, l_pid: 0, l_type: Int16(F_WRLCK), l_whence: Int16(SEEK_SET))
        let locked = withUnsafeMutablePointer(to: &lock) { fcntl(fd, 90 /* F_OFD_SETLK */, UnsafeMutableRawPointer($0)) }
        try #require(locked == 0)

        #expect(await DiskLockProbe.isInUse(url: url))
        await DiskOperations.createSnapshot(named: "nope", on: disk)
        #expect(disk.isInUse && !disk.canMutate)
        #expect(disk.snapshots.isEmpty)
        #expect(DiskStatus.all(for: disk) == [.inUse(snapshotsReadable: true)], "the banner explains the refusal")

        // Snapshots stay readable while the lock is held.
        await DiskOperations.refresh(disk)
        #expect(disk.format == "qcow2" && disk.lastError == nil)
    }
}
