// Filter in Console.app or a terminal:
//   log stream --predicate 'subsystem == "ch.jo-tools.disk-snapshot-tool"'

import OSLog

/// `nonisolated` opts out of the module's MainActor default so the loggers can
/// be used off the main actor.
nonisolated extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "ch.jo-tools.disk-snapshot-tool"

    static let qemuImg   = Logger(subsystem: subsystem, category: "qemu-img")
    static let library   = Logger(subsystem: subsystem, category: "library")
    static let sidebar   = Logger(subsystem: subsystem, category: "sidebar")
    static let disk      = Logger(subsystem: subsystem, category: "disk")
    static let security  = Logger(subsystem: subsystem, category: "security-scope")
    static let lockProbe = Logger(subsystem: subsystem, category: "lock-probe")
}
