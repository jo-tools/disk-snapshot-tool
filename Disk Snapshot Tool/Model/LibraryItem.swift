import Foundation

/// A top-level library entry: a VM bundle with its disks, or a bare disk image.
enum LibraryItem: Identifiable {
    case vm(VMBundle)
    case disk(DiskImage)

    var id: UUID {
        switch self {
        case .vm(let vm):     return vm.id
        case .disk(let disk): return disk.id
        }
    }

    var displayName: String {
        switch self {
        case .vm(let vm):     return vm.name
        case .disk(let disk): return disk.label
        }
    }

    var disks: [DiskImage] {
        switch self {
        case .vm(let vm):     return vm.disks
        case .disk(let disk): return [disk]
        }
    }
}
