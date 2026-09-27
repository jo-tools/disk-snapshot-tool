import Foundation

/// Which filenames the app is willing to consider a disk image.
///
/// The authority on what a file *is* remains `qemu-img info`, but a drag has to
/// be accepted or refused synchronously, long before any probe could run, so at
/// that moment the filename is all there is. The Open panel and the drop apply
/// the same rule.
///
/// Deliberately tight: several plausible extensions map to misleading system
/// types ("raw" is a Panasonic camera image, "vhd" a VHDL source), extensionless
/// files cannot be told from any other untyped file, and "qcow" (version 1)
/// has no driver in the bundled qemu-img, which would report it as raw.
enum DiskImageFile {
    static let extensions: Set<String> = [
        "qcow2", "img", "vmdk", "vdi", "vhdx", "qed", "iso"
    ]

    static let addableExtensions: Set<String> = extensions.union(["utm"])

    static func isAddable(_ url: URL) -> Bool {
        addableExtensions.contains(url.pathExtension.lowercased())
    }
}
