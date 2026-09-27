import Darwin
import Foundation
import OSLog

/// Detects whether another QEMU process holds a disk image open, without
/// launching qemu-img.
///
/// QEMU takes advisory byte-range locks on every image it opens. From
/// block/file-posix.c: permissions are held at `RAW_LOCK_PERM_BASE` (100) + n,
/// and "nobody else may take permission n" at `RAW_LOCK_SHARED_BASE` (200) + n.
/// A running VM opens its disk read-write and denies write sharing, so byte
/// 201 (`SHARED_BASE + BLK_PERM_WRITE`) is locked exactly while it has the
/// image open. Testing that byte with F_OFD_GETLK costs an open/fcntl/close.
///
/// The result is advisory: network volumes may not honour fcntl locks, OFD
/// locks are anonymous (l_pid is -1), and a VM can start between the probe
/// and the action. DiskOperations re-probes right before every mutation, and
/// qemu-img's own locking is the final backstop.
nonisolated enum DiskLockProbe {
    private static let writeShareByte: off_t = 201

    /// `F_OFD_GETLK` from <sys/fcntl.h>; the Darwin overlay does not expose the
    /// F_OFD_* commands.
    private static let fcntlOFDGetLock: Int32 = 92

    /// Off the main actor because `open()` can stall on a network mount.
    static func isInUse(url: URL) async -> Bool {
        await Task.detached(priority: .utility) { probe(url: url) }.value
    }

    private static func probe(url: URL) -> Bool {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        // O_RDONLY is enough to ask about conflicting locks and never disturbs a VM.
        let fd = open(url.path(percentEncoded: false), O_RDONLY)
        guard fd >= 0 else {
            Logger.lockProbe.debug("Cannot open \(url.lastPathComponent, privacy: .public) for lock probe (errno \(errno, privacy: .public))")
            return false
        }
        defer { close(fd) }

        // OFD locks are what QEMU uses on macOS; classic POSIX record locks share
        // the same lock space, so either command sees the other's locks.
        if let held = conflictingWriteLock(fd: fd, command: fcntlOFDGetLock) { return held }
        if let held = conflictingWriteLock(fd: fd, command: F_GETLK)         { return held }

        // Report idle rather than block the user; qemu-img refuses if this is wrong.
        Logger.lockProbe.warning("Lock probe inconclusive for \(url.lastPathComponent, privacy: .public)")
        return false
    }

    /// Whether taking an exclusive lock on the write-share byte would conflict.
    /// nil if the query itself failed.
    private static func conflictingWriteLock(fd: Int32, command: Int32) -> Bool? {
        var lock = flock(
            l_start:  writeShareByte,
            l_len:    1,
            l_pid:    0,
            l_type:   Int16(F_WRLCK),
            l_whence: Int16(SEEK_SET)
        )
        let result = withUnsafeMutablePointer(to: &lock) {
            fcntl(fd, command, UnsafeMutableRawPointer($0))
        }
        guard result == 0 else { return nil }
        return lock.l_type != Int16(F_UNLCK)
    }
}
