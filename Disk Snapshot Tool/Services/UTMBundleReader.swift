import Foundation

/// The parts of a UTM bundle's config.plist this app reads (ConfigurationVersion 4),
/// for both backends. QEMU drives carry `ImageType` and `Interface`; Apple
/// Virtualization drives carry neither and mark removable media `ReadOnly`.
struct UTMConfig: Decodable {
    let information: Information
    let drive: [Drive]

    struct Information: Decodable {
        let name: String

        enum CodingKeys: String, CodingKey {
            case name = "Name"
        }
    }

    struct Drive: Decodable {
        let identifier: String
        let imageType: String?
        let imageName: String?
        let interface: String?
        let readOnly: Bool?

        enum CodingKeys: String, CodingKey {
            case identifier = "Identifier"
            case imageType  = "ImageType"
            case imageName  = "ImageName"
            case interface  = "Interface"
            case readOnly   = "ReadOnly"
        }

        /// A hard disk, as opposed to a CD-ROM or removable media.
        var isDisk: Bool { imageType.map { $0 == "Disk" } ?? (readOnly != true) }
    }

    enum CodingKeys: String, CodingKey {
        case information = "Information"
        case drive       = "Drive"
    }
}

/// Turns a .utm directory into a `VMBundle` and its `DiskImage`s.
enum UTMBundleReader {
    static func makeBundle(at url: URL, bookmark: Data) throws -> VMBundle {
        let config = try readConfig(at: url)
        let vm = VMBundle(name: config.information.name, url: url, bookmarkData: bookmark)
        vm.disks = disks(for: vm, config: config)
        return vm
    }

    static func readConfig(at bundleURL: URL) throws -> UTMConfig {
        let accessing = bundleURL.startAccessingSecurityScopedResource()
        defer { if accessing { bundleURL.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: bundleURL.appending(component: "config.plist"))
        return try PropertyListDecoder().decode(UTMConfig.self, from: data)
    }

    /// One `DiskImage` per hard-disk drive. A drive whose file cannot be
    /// bookmarked is skipped.
    static func disks(for vm: VMBundle, config: UTMConfig) -> [DiskImage] {
        let accessing = vm.url.startAccessingSecurityScopedResource()
        defer { if accessing { vm.url.stopAccessingSecurityScopedResource() } }

        let dataDir = vm.url.appending(component: "Data")
        return config.drive.compactMap { drive in
            guard drive.isDisk, let imageName = drive.imageName else { return nil }
            let diskURL = dataDir.appending(component: imageName)
            guard let bookmark = try? SecurityScope.bookmark(for: diskURL),
                  let resolved = SecurityScope.resolve(bookmark) else { return nil }
            return DiskImage(
                id: scopedDiskID(vmID: vm.id, driveIdentifier: drive.identifier),
                imageType: drive.imageType ?? "Disk",
                interface: drive.interface ?? "",
                label: URL(fileURLWithPath: imageName).lastPathComponent,
                url: resolved.url,
                bookmarkData: bookmark
            )
        }
    }

    /// FNV-1a of "vmID:driveIdentifier", folded into a UUID. Scoped to the
    /// bundle so that cloned VMs, which keep their drive identifiers, never
    /// share disk ids.
    static func scopedDiskID(vmID: UUID, driveIdentifier: String) -> UUID {
        var h: UInt64 = 14695981039346656037
        for byte in (vmID.uuidString + ":" + driveIdentifier).utf8 {
            h ^= UInt64(byte)
            h = h &* 1099511628211
        }
        var h2 = h ^ 0x9e3779b97f4a7c15
        h2 = h2 &* 6364136223846793005
        h2 = h2 &+ 1442695040888963407
        return UUID(uuid: (
            UInt8(h >> 56 & 0xff), UInt8(h >> 48 & 0xff),
            UInt8(h >> 40 & 0xff), UInt8(h >> 32 & 0xff),
            UInt8(h >> 24 & 0xff), UInt8(h >> 16 & 0xff),
            UInt8(h >>  8 & 0xff), UInt8(h       & 0xff),
            UInt8(h2 >> 56 & 0xff), UInt8(h2 >> 48 & 0xff),
            UInt8(h2 >> 40 & 0xff), UInt8(h2 >> 32 & 0xff),
            UInt8(h2 >> 24 & 0xff), UInt8(h2 >> 16 & 0xff),
            UInt8(h2 >>  8 & 0xff), UInt8(h2       & 0xff)
        ))
    }
}
