import Foundation

/// `qemu-img info --output=json`, the parts this app reads.
///
/// `nonisolated` so QemuImgService can decode it off the main actor; the
/// module's default isolation would otherwise make the synthesised init
/// MainActor-only.
nonisolated struct QemuImgInfo: Decodable {
    let virtualSize: Int64
    let actualSize: Int64
    /// "qcow2", "raw", "vmdk", … Note that "raw" is a fallback rather than an
    /// identification: qemu-img reports any file it does not recognise as raw.
    let format: String
    /// Absent when the image has no snapshots.
    let snapshots: [QemuSnapshotRecord]?

    enum CodingKeys: String, CodingKey {
        case virtualSize = "virtual-size"
        case actualSize  = "actual-size"
        case format
        case snapshots
    }
}

nonisolated struct QemuSnapshotRecord: Decodable {
    let id: String
    let name: String
    let dateSec: Int64
    let dateNsec: Int32
    let vmStateSize: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case dateSec     = "date-sec"
        case dateNsec    = "date-nsec"
        case vmStateSize = "vm-state-size"
    }

    func toSnapshot() -> Snapshot {
        let wallTime = TimeInterval(dateSec) + TimeInterval(dateNsec) / 1_000_000_000
        return Snapshot(id: id,
                        name: name,
                        date: Date(timeIntervalSince1970: wallTime),
                        vmStateSize: vmStateSize)
    }
}
