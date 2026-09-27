import Foundation
import OSLog

/// Keeps `DiskImage.isInUse` current by re-probing every reachable disk on a
/// timer. A VM taking QEMU's lock does not change the file, so the kqueue
/// watcher never sees it; polling is the only way to notice a VM starting.
enum DiskLockMonitor {
    static let interval = Duration.seconds(3)

    /// Runs until the task is cancelled.
    static func run(disks: () -> [DiskImage]) async {
        Logger.disk.info("Lock polling started")
        while !Task.isCancelled {
            await poll(disks())
            try? await Task.sleep(for: interval)
        }
        Logger.disk.info("Lock polling stopped")
    }

    /// Skips a disk while the app itself has it open: qemu-img holds the same
    /// lock a VM does, and would be reported as another process.
    private static func poll(_ disks: [DiskImage]) async {
        for disk in disks where disk.availability.isAvailable && !disk.isLoading {
            let inUse = await DiskLockProbe.isInUse(url: disk.url)
            guard disk.isInUse != inUse, !disk.isLoading else { continue }
            disk.isInUse = inUse
            Logger.disk.info("Disk '\(disk.label, privacy: .public)' \(inUse ? "is now in use" : "has been released", privacy: .public)")
            // A VM that just shut down may have left new snapshot state behind.
            if !inUse { await DiskOperations.refresh(disk) }
        }
    }
}
