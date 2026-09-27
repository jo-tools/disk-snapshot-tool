import Testing
import Foundation
@testable import Disk_Snapshot_Tool

struct QemuImgInfoTests {
    private let withSnapshots = """
    {
      "children": [], "virtual-size": 68719476736, "filename": "disk.qcow2",
      "cluster-size": 65536, "format": "qcow2", "actual-size": 12345678,
      "format-specific": {"type": "qcow2", "data": {"compat": "1.1"}},
      "snapshots": [
        {"vm-state-size": 0, "id": "1", "name": "clean", "date-sec": 1700000000,
         "date-nsec": 500000000, "vm-clock-sec": 12, "vm-clock-nsec": 0, "icount": 0},
        {"vm-state-size": 536870912, "id": "2", "name": "running", "date-sec": 1700003600,
         "date-nsec": 0, "vm-clock-sec": 90, "vm-clock-nsec": 0}
      ],
      "dirty-flag": false
    }
    """

    private let rawImage = """
    {"virtual-size": 8388608, "filename": "raw.img", "format": "raw", "actual-size": 0, "dirty-flag": false}
    """

    @Test func decodesSnapshots() throws {
        let info = try JSONDecoder().decode(QemuImgInfo.self, from: Data(withSnapshots.utf8))
        #expect(info.format == "qcow2")
        #expect(info.virtualSize == 68_719_476_736)
        #expect(info.actualSize == 12_345_678)
        let snapshots = try #require(info.snapshots).map { $0.toSnapshot() }
        #expect(snapshots.map(\.name) == ["clean", "running"])
        #expect(snapshots.map(\.id) == ["1", "2"])
        #expect(snapshots[0].date == Date(timeIntervalSince1970: 1_700_000_000.5))
        #expect(snapshots[0].vmStateSize == 0)
        #expect(snapshots[0].formattedVMStateSize == "No RAM state")
        #expect(snapshots[1].vmStateSize == 536_870_912)
    }

    @Test func decodesImageWithoutSnapshots() throws {
        let info = try JSONDecoder().decode(QemuImgInfo.self, from: Data(rawImage.utf8))
        #expect(info.format == "raw")
        #expect(info.snapshots == nil)
        #expect(info.actualSize == 0)
    }
}

struct SnapshotNameTests {
    private let existing = [Snapshot(id: "1", name: "clean", date: .now, vmStateSize: 0)]

    @Test func acceptsANewName() {
        #expect(Snapshot.problem(withName: "before-update", existing: existing) == nil)
    }

    @Test func refusesWhatQcow2WouldMangle() {
        #expect(Snapshot.problem(withName: "", existing: existing) != nil)
        #expect(Snapshot.problem(withName: "clean", existing: existing) != nil)
        #expect(Snapshot.problem(withName: String(repeating: "x", count: 255), existing: existing) == nil)
        #expect(Snapshot.problem(withName: String(repeating: "ä", count: 128), existing: existing) != nil, "256 bytes")
    }
}

struct QemuImgErrorMappingTests {
    private func map(_ stderr: String, args: [String] = ["snapshot", "-c", "tag", "/vm/disk.qcow2"]) -> QemuImgError {
        QemuImgService.mapError(stderr: stderr, args: args, exitCode: 1)
    }

    /// A running VM holds shared locks; an exclusive lock yields the byte message.
    @Test func lockedImage() {
        #expect(map("qemu-img: Could not open '/vm/disk.qcow2': Failed to get \"write\" lock\nIs another process using the image [/vm/disk.qcow2]?") == .imageLocked)
        #expect(map("qemu-img: Could not open '/vm/disk.qcow2': Failed to lock byte 100") == .imageLocked)
    }

    @Test func missingImage() {
        #expect(map("qemu-img: Could not open '/vm/disk.qcow2': No such file or directory")
                == .imageNotFound(path: "/vm/disk.qcow2"))
    }

    @Test func missingSnapshot() {
        #expect(map("qemu-img: Could not delete snapshot 'gone': snapshot not found",
                    args: ["snapshot", "-d", "gone", "/vm/disk.qcow2"]) == .snapshotNotFound)
        #expect(map("qemu-img: Could not apply snapshot '9': Failed to load snapshot: No such file or directory",
                    args: ["snapshot", "-a", "9", "/vm/disk.qcow2"]) == .snapshotNotFound)
    }

    @Test func anythingElseKeepsStderr() {
        #expect(map("qemu-img: Operation not supported") == .commandFailed(exitCode: 1, stderr: "qemu-img: Operation not supported"))
    }
}
