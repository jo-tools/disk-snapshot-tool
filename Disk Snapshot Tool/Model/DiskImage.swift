import Foundation
import Observation

/// One disk image, from inside a UTM bundle or added on its own. Any format
/// qemu-img can read is listed; only qcow2 can hold snapshots.
@Observable
final class DiskImage: Identifiable {
    let id: UUID
    /// UTM's drive type ("Disk", "CD"); empty for a file added on its own.
    let imageType: String
    /// UTM's drive interface ("VirtIO", "NVMe", …); empty for a file added on its own.
    let interface: String
    /// The filename.
    let label: String
    var bookmarkData: Data

    var url: URL
    var availability: Availability = .available
    /// From the last successful `qemu-img info`.
    var snapshots: [Snapshot] = []
    var virtualSize: Int64 = 0
    var actualSize: Int64 = 0
    /// qemu-img's format name; nil until the image has been probed.
    var format: String?
    /// True while the app itself has the image open.
    var isLoading = false
    /// Another process holds QEMU's write lock, typically a running VM.
    /// Advisory: see DiskLockProbe.
    var isInUse = false
    /// Why the last `qemu-img info` failed; cleared by the next one that works.
    var readError: String?
    /// Why the last create, apply or delete failed. Outlives later reads, so
    /// it stays until dismissed or replaced by the next operation.
    var operationError: String?
    /// Set only while the disk file is unchanged since the snapshot was applied.
    var lastAppliedSnapshotName: String?
    /// Shown in the unavailable state after the file has gone out of reach.
    private(set) var lastKnownPath: String

    init(id: UUID = UUID(), imageType: String = "", interface: String = "",
         label: String, url: URL, bookmarkData: Data) {
        self.id           = id
        self.imageType    = imageType
        self.interface    = interface
        self.label        = label
        self.url          = url
        self.bookmarkData = bookmarkData
        self.lastKnownPath = url.path(percentEncoded: false)
    }

    func recordCurrentPath() {
        lastKnownPath = url.path(percentEncoded: false)
    }
}

extension DiskImage {
    var lastError: String? { operationError ?? readError }

    func dismissErrors() {
        operationError = nil
        readError = nil
    }

    /// Whether create, apply and delete may be offered right now. `isInUse` is
    /// advisory; DiskOperations re-probes before every mutation.
    var canMutate: Bool {
        availability.isAvailable && !isInUse && !isLoading && supportsSnapshots
    }

    /// qcow2 is the only local format whose QEMU block driver implements
    /// snapshots; on anything else `qemu-img snapshot -c` fails with
    /// "Operation not supported". False while the format is unknown, so nothing
    /// is offered before the first probe has answered.
    var supportsSnapshots: Bool { format == "qcow2" }

    /// Known *and* known to be unsupported, so the explanation never flashes
    /// during the first probe.
    var hasKnownUnsupportedFormat: Bool { format != nil && !supportsSnapshots }

    var formatDisplayName: String {
        guard let format else { return String(localized: "unknown", comment: "Disk image format that has not been determined") }
        switch format {
        case "vmdk", "vdi", "vhdx", "vpc", "qed", "luks": return format.uppercased()
        case "parallels": return "Parallels"
        default: return format
        }
    }

    // Virtual size is binary because UTM's size field is: a disk created there
    // as 10 GB is 10 GiB, and only .binary reads it back as "10 GB". Size on
    // disk is decimal so it agrees with Finder's Get Info. Both spell zero as
    // "0 bytes" rather than "Zero KB".

    private static let virtualSizeFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        f.allowsNonnumericFormatting = false
        return f
    }()

    private static let actualSizeFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f
    }()

    var formattedVirtualSize: String {
        Self.virtualSizeFormatter.string(fromByteCount: virtualSize)
    }

    var formattedActualSize: String {
        Self.actualSizeFormatter.string(fromByteCount: actualSize)
    }
}
