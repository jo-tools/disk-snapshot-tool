import Testing
import Foundation
@testable import Disk_Snapshot_Tool

struct LibraryStoreTests {
    private func sampleRecords() -> [LibraryRecord] {
        [
            .vmBundle(record: .init(id: UUID(), bookmarkData: Data([1, 2, 3]),
                                    cachedName: "VM", cachedPath: "/vm/VM.utm")),
            .diskImage(record: .init(id: UUID(), bookmarkData: Data([4, 5]),
                                     cachedLabel: "d.qcow2", cachedPath: "/d/d.qcow2")),
        ]
    }

    @Test func roundTrips() throws {
        let data = try JSONEncoder().encode(sampleRecords())
        let decoded = try LibraryStore.decodeRecords(from: data)
        #expect(decoded.skipped == 0)
        #expect(decoded.records.count == 2)
        guard case .vmBundle(let vm) = decoded.records[0],
              case .diskImage(let disk) = decoded.records[1] else {
            Issue.record("record kinds did not survive"); return
        }
        #expect(vm.cachedName == "VM")
        #expect(disk.cachedLabel == "d.qcow2")
    }

    @Test func oneBadRecordDoesNotDropTheRest() throws {
        let data = try JSONEncoder().encode(sampleRecords())
        var array = try JSONSerialization.jsonObject(with: data) as! [Any]
        array.insert(["somethingElse": ["record": ["id": "nope"]]], at: 1)
        let mixed = try JSONSerialization.data(withJSONObject: array)

        let decoded = try LibraryStore.decodeRecords(from: mixed)
        #expect(decoded.skipped == 1)
        #expect(decoded.records.count == 2)
    }

    /// A file that exists but cannot be read must survive the save that
    /// follows every launch.
    @Test func unreadableFileIsNeverOverwritten() throws {
        let file = FileManager.default.temporaryDirectory.appending(component: "library-\(UUID().uuidString).json")
        let original = try JSONEncoder().encode(sampleRecords())
        try original.write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path(percentEncoded: false))
        defer { try? FileManager.default.removeItem(at: file) }

        let store = LibraryStore(fileURL: file)
        #expect(store.load().isEmpty)
        store.save([])

        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path(percentEncoded: false))
        #expect(try Data(contentsOf: file) == original)
    }

    @Test func nonArrayFileThrows() {
        #expect(throws: (any Error).self) {
            try LibraryStore.decodeRecords(from: Data("{\"not\": \"an array\"}".utf8))
        }
    }
}
