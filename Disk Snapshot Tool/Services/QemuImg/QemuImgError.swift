import Foundation

nonisolated enum QemuImgError: LocalizedError, Equatable {
    case binaryNotFound
    case imageLocked
    case imageNotFound(path: String)
    case snapshotNotFound
    case invalidOutput(String)
    case commandFailed(exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return String(localized: "The qemu-img helper was not found in the app bundle.")
        case .imageLocked:
            return String(localized: "The disk image is in use by another process, such as a running virtual machine.\nClose it, then try again.")
        case .imageNotFound(let path):
            return String(localized: "Disk image not found: \(path)")
        case .snapshotNotFound:
            return String(localized: "The snapshot no longer exists on this disk image.")
        case .invalidOutput(let detail):
            return String(localized: "Unexpected output from qemu-img: \(detail)")
        case .commandFailed(let code, let stderr):
            let msg = stderr.isEmpty ? String(localized: "(no details)") : stderr
            return String(localized: "qemu-img failed (exit \(code)):\n\(msg.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
}
