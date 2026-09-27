import Foundation

/// Watches one file with kqueue and reports changes as an async stream.
final class DiskWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var pending: Task<Void, Never>?

    /// Emits once per burst of writes, `debounce` after the last one, so a
    /// running VM's continuous writes do not cause constant reloads. Ends at
    /// once if the file cannot be opened; stops watching when the consumer
    /// stops iterating.
    static func changes(at url: URL, debounce: Duration = .seconds(1.5)) -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let watcher = DiskWatcher()
        guard watcher.start(url: url, debounce: debounce, continuation: continuation) else {
            continuation.finish()
            return stream
        }
        continuation.onTermination = { _ in
            Task { @MainActor in watcher.stop() }
        }
        return stream
    }

    private func start(url: URL, debounce: Duration,
                       continuation: AsyncStream<Void>.Continuation) -> Bool {
        let accessing = url.startAccessingSecurityScopedResource()
        let fd = open(url.path(percentEncoded: false), O_EVTONLY)
        guard fd >= 0 else {
            if accessing { url.stopAccessingSecurityScopedResource() }
            return false
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete, .extend],
            queue: .main
        )
        source.setEventHandler {
            MainActor.assumeIsolated {
                self.pending?.cancel()
                self.pending = Task {
                    try? await Task.sleep(for: debounce)
                    guard !Task.isCancelled else { return }
                    continuation.yield()
                }
            }
        }
        source.setCancelHandler {
            close(fd)
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        source.resume()
        self.source = source
        return true
    }

    private func stop() {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
    }
}
