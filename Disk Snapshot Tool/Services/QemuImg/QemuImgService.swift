import Foundation
import OSLog

/// The one place this app launches qemu-img, which the build installs at
/// Contents/Helpers/qemu-img. Security-scoped access is held around each run
/// so the sandboxed child can read and write the image.
nonisolated enum QemuImgService {
    private static let log = Logger.qemuImg

    /// `-U` (force-share) keeps the list readable while a VM is running;
    /// without it qemu-img refuses to open a locked image. It is deliberately
    /// not passed to the mutating commands, where QEMU's lock is what stands
    /// between a mis-click and a corrupted disk.
    static func info(diskURL: URL) async throws -> QemuImgInfo {
        let data = try await run(["info", "-U", "--output=json", diskURL.path(percentEncoded: false)],
                                 securedURL: diskURL)
        do {
            return try JSONDecoder().decode(QemuImgInfo.self, from: data)
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? String(localized: "(binary)", comment: "Stands in for qemu-img output that is not text")
            throw QemuImgError.invalidOutput(raw.prefix(200).description)
        }
    }

    static func createSnapshot(name: String, diskURL: URL) async throws {
        _ = try await run(["snapshot", "-c", name, diskURL.path(percentEncoded: false)], securedURL: diskURL)
    }

    /// By ID, which `-a` looks up before tags: a tag can name several snapshots.
    static func applySnapshot(_ snapshot: Snapshot, diskURL: URL) async throws {
        _ = try await run(["snapshot", "-a", snapshot.id, diskURL.path(percentEncoded: false)], securedURL: diskURL)
    }

    /// By tag, the only thing `-d` accepts; it deletes the first snapshot
    /// carrying it, so the caller makes sure there is only one.
    static func deleteSnapshot(_ snapshot: Snapshot, diskURL: URL) async throws {
        _ = try await run(["snapshot", "-d", snapshot.name, diskURL.path(percentEncoded: false)], securedURL: diskURL)
    }

    private static func helperURL() throws -> URL {
        let url = Bundle.main.bundleURL.appending(components: "Contents", "Helpers", "qemu-img")
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            log.error("Helper binary not found at \(url.path(percentEncoded: false), privacy: .public)")
            throw QemuImgError.binaryNotFound
        }
        return url
    }

    private static func run(_ args: [String], securedURL: URL) async throws -> Data {
        let process = Process()
        process.executableURL = try helperURL()
        process.arguments = args
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        let (exit, exited) = AsyncStream<Int32>.makeStream()
        process.terminationHandler = { exited.yield($0.terminationStatus); exited.finish() }

        let accessing = securedURL.startAccessingSecurityScopedResource()
        defer { if accessing { securedURL.stopAccessingSecurityScopedResource() } }
        log.info("▶ qemu-img \(args.joined(separator: " "), privacy: .public) | scope=\(accessing, privacy: .public)")

        do {
            try process.run()
        } catch {
            log.error("Failed to launch qemu-img: \(error, privacy: .public)")
            throw error
        }
        // Drained while the child runs: a pipe holds 64 KiB, and a child that
        // fills it blocks until someone reads.
        async let stdout = drain(stdoutPipe.fileHandleForReading)
        async let stderr = drain(stderrPipe.fileHandleForReading)
        var status: Int32 = -1
        for await code in exit { status = code }
        let (stdoutData, stderrData) = await (stdout, stderr)

        guard status == 0 else {
            let message = String(data: stderrData, encoding: .utf8) ?? ""
            log.error("✗ qemu-img exit \(status, privacy: .public): \(message, privacy: .public)")
            throw mapError(stderr: message, args: args, exitCode: status)
        }
        log.info("✓ qemu-img exit 0, stdout \(stdoutData.count, privacy: .public) bytes")
        return stdoutData
    }

    /// Not `FileHandle.bytes`, which never finishes on a pipe.
    private static func drain(_ handle: FileHandle) async -> Data {
        await withCheckedContinuation { continuation in
            let collected = Collected()
            handle.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard chunk.isEmpty else { collected.append(chunk); return }
                handle.readabilityHandler = nil
                continuation.resume(returning: collected.data)
            }
        }
    }

    private nonisolated final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()

        func append(_ chunk: Data) { lock.withLock { buffer.append(chunk) } }
        var data: Data { lock.withLock { buffer } }
    }

    /// The spellings current QEMU prints. A running VM holds the image with
    /// shared locks, which qemu-img reports as failing to get the "write"
    /// lock; "failed to lock byte" is what an exclusive lock produces. A
    /// snapshot that is gone reads as ENOENT from `-a`, so that check comes
    /// before the one for a missing image.
    static func mapError(stderr: String, args: [String], exitCode: Int32) -> QemuImgError {
        let lower = stderr.lowercased()
        if lower.contains("is another process using the image") || lower.contains("failed to get \"write\" lock") ||
           lower.contains("failed to get shared") || lower.contains("failed to lock byte") {
            return .imageLocked
        }
        if lower.contains("snapshot not found") || lower.contains("failed to load snapshot") {
            return .snapshotNotFound
        }
        if lower.contains("no such file or directory") {
            return .imageNotFound(path: args.last ?? "")
        }
        return .commandFailed(exitCode: exitCode, stderr: stderr)
    }
}
