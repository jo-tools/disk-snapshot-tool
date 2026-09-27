import Foundation
import OSLog

/// Everything the app does to a disk image through qemu-img, updating the
/// `DiskImage` as it goes.
enum DiskOperations {
    private static var appliedStore: AppliedSnapshotStore?

    /// Handed over once at launch by whoever assembles the app. Where these
    /// records live is a decision of the run, not of this type.
    static func use(_ store: AppliedSnapshotStore) {
        appliedStore = store
    }

    private static var applied: AppliedSnapshotStore {
        guard let appliedStore else {
            preconditionFailure("DiskOperations.use(_:) must run before any disk operation")
        }
        return appliedStore
    }

    /// Re-checks reachability and the lock, then reloads format, sizes and snapshots.
    static func refresh(_ disk: DiskImage) async {
        guard !disk.isLoading else { return }
        if !disk.availability.isAvailable || !SecurityScope.isReachable(disk.url) {
            reopen(disk)
        }
        guard SecurityScope.isReachable(disk.url) else {
            Logger.disk.warning("Disk not reachable: \(disk.label, privacy: .public)")
            disk.availability = .unavailable(reason: String(localized: "The file is not currently accessible."))
            disk.isInUse = false
            return
        }
        disk.isLoading = true
        defer { disk.isLoading = false }
        disk.availability = .available
        disk.recordCurrentPath()
        disk.isInUse = await DiskLockProbe.isInUse(url: disk.url)

        do {
            let info = try await QemuImgService.info(diskURL: disk.url)
            disk.snapshots   = (info.snapshots ?? []).map { $0.toSnapshot() }
            disk.virtualSize = info.virtualSize
            disk.actualSize  = info.actualSize
            disk.format      = info.format
            disk.lastAppliedSnapshotName = applied.currentlyApplied(for: disk)
            disk.readError   = nil
            Logger.disk.info("Disk '\(disk.label, privacy: .public)': \(info.format, privacy: .public), \(disk.snapshots.count, privacy: .public) snapshot(s)")
        } catch {
            Logger.disk.error("Disk '\(disk.label, privacy: .public)' refresh failed: \(error, privacy: .public)")
            disk.readError = error.localizedDescription
        }
    }

    /// A file that went out of reach may be back under another path, or back
    /// with the security scope that a fallback URL from launch never had.
    private static func reopen(_ disk: DiskImage) {
        guard let reopened = SecurityScope.reopen(disk.bookmarkData, name: disk.label) else { return }
        disk.url = reopened.url
        disk.bookmarkData = reopened.bookmarkData
    }

    static func createSnapshot(named name: String, on disk: DiskImage) async {
        if let problem = Snapshot.problem(withName: name, existing: disk.snapshots) {
            disk.operationError = problem
            return
        }
        await perform("Create snapshot '\(name)'", on: disk) {
            try await QemuImgService.createSnapshot(name: name, diskURL: disk.url)
            applied.record(name, for: disk)
        }
    }

    static func applySnapshot(_ snapshot: Snapshot, on disk: DiskImage) async {
        await perform("Apply snapshot '\(snapshot.name)'", on: disk) {
            try await QemuImgService.applySnapshot(snapshot, diskURL: disk.url)
            applied.record(snapshot.name, for: disk)
        }
    }

    /// `snapshot -d` takes the first snapshot with the tag, so only that one
    /// can be deleted safely while another shares its tag.
    static func deleteSnapshot(_ snapshot: Snapshot, on disk: DiskImage) async {
        if let first = disk.snapshots.first(where: { $0.name == snapshot.name }), first.id != snapshot.id {
            disk.operationError = String(localized: "An older snapshot is also named \"\(snapshot.name)\", and qemu-img would delete that one instead.\nDelete the older one first.")
            return
        }
        await perform("Delete snapshot '\(snapshot.name)'", on: disk) {
            try await QemuImgService.deleteSnapshot(snapshot, diskURL: disk.url)
            applied.snapshotDeleted(snapshot.name, from: disk)
        }
    }

    /// Refuses an unreachable or busy disk, holds `isLoading` from the lock
    /// check to the end so no refresh or poll interleaves, and re-reads the
    /// disk afterwards. The lock is probed again right before the write because
    /// the badge is only as fresh as the last poll; qemu-img's own lock covers
    /// the race that is left. A refusal needs no message of its own: the
    /// in-use banner appears with it.
    private static func perform(_ what: String, on disk: DiskImage,
                                _ body: () async throws -> Void) async {
        disk.operationError = nil
        guard disk.availability.isAvailable, !disk.isLoading else { return }
        disk.isLoading = true
        disk.isInUse = await DiskLockProbe.isInUse(url: disk.url)
        if disk.isInUse {
            Logger.disk.warning("Refusing snapshot operation: '\(disk.label, privacy: .public)' is in use")
        } else {
            Logger.disk.info("\(what, privacy: .public) on '\(disk.label, privacy: .public)'")
            do {
                try await body()
                Logger.disk.info("\(what, privacy: .public) done")
            } catch {
                Logger.disk.error("\(what, privacy: .public) failed: \(error, privacy: .public)")
                disk.operationError = error.localizedDescription
            }
        }
        disk.isLoading = false
        await refresh(disk)
    }
}
