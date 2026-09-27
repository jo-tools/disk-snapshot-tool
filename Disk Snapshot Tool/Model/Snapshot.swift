import Foundation

/// One internal snapshot of a qcow2 image, as reported by `qemu-img info`.
///
/// qcow2 identifies a snapshot by its numeric ID; the tag is only a label and
/// need not be unique. Anything that must hit exactly one snapshot uses `id`.
nonisolated struct Snapshot: Identifiable, Equatable {
    let id: String
    let name: String
    let date: Date
    /// 0 when the snapshot holds disk state only.
    let vmStateSize: Int64
}

extension Snapshot {
    /// qcow2 cuts a tag at 255 bytes without saying so.
    static let maxNameBytes = 255

    /// Why `name` cannot become a new snapshot's tag on a disk that already has
    /// `existing`, or nil if it can. A duplicate tag would leave `snapshot -d`
    /// unable to tell the two apart.
    static func problem(withName name: String, existing: [Snapshot]) -> String? {
        if name.isEmpty { return String(localized: "Enter a name.") }
        if name.utf8.count > maxNameBytes { return String(localized: "The name is too long.") }
        if existing.contains(where: { $0.name == name }) { return String(localized: "A snapshot with this name already exists.") }
        return nil
    }

    var formattedDate: String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    var formattedVMStateSize: String {
        vmStateSize == 0
            ? String(localized: "No RAM state")
            : ByteCountFormatter.string(fromByteCount: vmStateSize, countStyle: .binary)
    }
}
