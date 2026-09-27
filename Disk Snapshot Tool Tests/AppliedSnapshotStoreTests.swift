import Testing
import Foundation
@testable import Disk_Snapshot_Tool

final class AppliedSnapshotStoreTests {
    private let defaults: UserDefaults
    private let store: AppliedSnapshotStore
    private let file: URL
    private let disk: DiskImage

    init() throws {
        defaults = ScratchDefaults(suiteName: nil)!
        store = AppliedSnapshotStore(defaults: defaults)
        file = FileManager.default.temporaryDirectory.appending(component: "\(UUID().uuidString).qcow2")
        try Data("fixture".utf8).write(to: file)
        disk = DiskImage(label: file.lastPathComponent, url: file, bookmarkData: Data())
        disk.snapshots = [Snapshot(id: "1", name: "s1", date: .now, vmStateSize: 0),
                          Snapshot(id: "2", name: "s2", date: .now, vmStateSize: 0)]
    }

    deinit {
        try? FileManager.default.removeItem(at: file)
    }

    @Test func reportsWhileFileIsUnchanged() {
        store.record("s1", for: disk)
        #expect(store.currentlyApplied(for: disk) == "s1")
    }

    @Test func forgetsOnceFileChanges() throws {
        store.record("s1", for: disk)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)],
                                              ofItemAtPath: file.path(percentEncoded: false))
        #expect(store.currentlyApplied(for: disk) == nil)
        #expect(store.currentlyApplied(for: disk) == nil, "record is dropped, not just hidden")
    }

    @Test func forgetsWhenSnapshotIsGone() {
        store.record("s1", for: disk)
        disk.snapshots.removeAll { $0.name == "s1" }
        #expect(store.currentlyApplied(for: disk) == nil)
    }

    @Test func deletingAnotherSnapshotKeepsTheAppliedOne() throws {
        store.record("s1", for: disk)
        try Data("changed by deletion".utf8).write(to: file)
        store.snapshotDeleted("s2", from: disk)
        disk.snapshots.removeAll { $0.name == "s2" }
        #expect(store.currentlyApplied(for: disk) == "s1")
    }

    @Test func anAmbiguousNameIsNotClaimed() {
        store.record("s1", for: disk)
        disk.snapshots.append(Snapshot(id: "3", name: "s1", date: .now, vmStateSize: 0))
        #expect(store.currentlyApplied(for: disk) == nil)
    }

    @Test func deletingTheAppliedSnapshotForgetsIt() {
        store.record("s1", for: disk)
        store.snapshotDeleted("s1", from: disk)
        #expect(store.currentlyApplied(for: disk) == nil)
    }
}
