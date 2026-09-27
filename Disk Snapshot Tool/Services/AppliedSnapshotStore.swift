import Foundation

/// Remembers which snapshot was last applied to each disk, together with the
/// disk file's modification time at that moment.
///
/// The name is only reported back while the mtime is unchanged. Once the VM
/// has run, the live state has moved on and the snapshot is no longer "what
/// the disk is at".
struct AppliedSnapshotStore {
    private struct Record: Codable {
        let snapshotName: String
        let diskMtimeInterval: Double
    }

    private static let key = "appliedSnapshots"
    let defaults: UserDefaults

    func record(_ name: String, for disk: DiskImage) {
        guard let mtime = Self.mtime(of: disk) else { return }
        var records = load()
        records[disk.id.uuidString] = Record(snapshotName: name,
                                             diskMtimeInterval: mtime.timeIntervalSince1970)
        save(records)
    }

    /// Reacts to `deleted` being removed from `disk`: forgets it if it was the
    /// applied one, otherwise re-stamps the mtime the deletion just changed.
    func snapshotDeleted(_ deleted: String, from disk: DiskImage) {
        var records = load()
        guard let existing = records[disk.id.uuidString] else { return }
        if existing.snapshotName == deleted {
            records.removeValue(forKey: disk.id.uuidString)
        } else if let mtime = Self.mtime(of: disk) {
            records[disk.id.uuidString] = Record(snapshotName: existing.snapshotName,
                                                 diskMtimeInterval: mtime.timeIntervalSince1970)
        }
        save(records)
    }

    /// The applied snapshot's name, if exactly one snapshot on the disk still
    /// carries it and the disk has not been written since. A record that fails
    /// either test is dropped.
    func currentlyApplied(for disk: DiskImage) -> String? {
        var records = load()
        guard let record = records[disk.id.uuidString] else { return nil }
        let stillExists = disk.snapshots.count(where: { $0.name == record.snapshotName }) == 1
        let unchanged = Self.mtime(of: disk).map {
            abs($0.timeIntervalSince1970 - record.diskMtimeInterval) < 1.0
        } ?? false
        guard stillExists, unchanged else {
            records.removeValue(forKey: disk.id.uuidString)
            save(records)
            return nil
        }
        return record.snapshotName
    }

    private func load() -> [String: Record] {
        guard let data = defaults.data(forKey: Self.key),
              let records = try? JSONDecoder().decode([String: Record].self, from: data)
        else { return [:] }
        return records
    }

    private func save(_ records: [String: Record]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Self.key)
    }

    private static func mtime(of disk: DiskImage) -> Date? {
        let accessing = disk.url.startAccessingSecurityScopedResource()
        defer { if accessing { disk.url.stopAccessingSecurityScopedResource() } }
        return (try? FileManager.default.attributesOfItem(atPath: disk.url.path(percentEncoded: false)))
            .flatMap { $0[.modificationDate] as? Date }
    }
}
