import Foundation
import Observation

/// A UTM virtual machine bundle (.utm directory) and the disk images its
/// config.plist describes.
@Observable
final class VMBundle: Identifiable {
    let id: UUID
    var name: String
    /// App-scoped security-scoped bookmark for the bundle directory.
    var bookmarkData: Data

    var url: URL
    var availability: Availability = .available
    var disks: [DiskImage] = []
    /// Shown in the unavailable state after the bundle has gone out of reach.
    private(set) var lastKnownPath: String

    init(id: UUID = UUID(), name: String, url: URL, bookmarkData: Data) {
        self.id           = id
        self.name         = name
        self.url          = url
        self.bookmarkData = bookmarkData
        self.lastKnownPath = url.path(percentEncoded: false)
    }

    func recordCurrentPath() {
        lastKnownPath = url.path(percentEncoded: false)
    }
}
