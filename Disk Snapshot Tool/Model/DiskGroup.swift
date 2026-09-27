import Foundation

/// The container a disk image is shown under: its UTM bundle, or the folder it
/// lives in. Derived from the disk's URL and the library; nothing is persisted.
struct DiskGroup: Hashable {
    enum Kind: Hashable {
        case utmVM
        case folder
    }

    let name: String
    let kind: Kind
    /// The .utm bundle or enclosing folder — what "Reveal in Finder" opens.
    let containerURL: URL

    init(name: String, kind: Kind, containerURL: URL) {
        self.name = name
        self.kind = kind
        self.containerURL = containerURL
    }

    init(vm: VMBundle) {
        self.init(name: vm.name, kind: .utmVM, containerURL: vm.url)
    }
}
