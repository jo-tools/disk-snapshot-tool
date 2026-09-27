import Foundation
import OSLog

enum SecurityScopeError: LocalizedError {
    case bookmarkCreationFailed(URL, underlying: Error)

    var errorDescription: String? {
        switch self {
        case .bookmarkCreationFailed(let url, let err):
            return String(localized: "Failed to create bookmark for \(url.lastPathComponent): \(err.localizedDescription)")
        }
    }
}

/// App-scoped security-scoped bookmarks: created once when the user opens or
/// drops a file, persisted so the file can be reopened across launches
/// without asking again.
enum SecurityScope {
    static func bookmark(for url: URL) throws -> Data {
        do {
            let data = try url.bookmarkData(options: .withSecurityScope,
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil)
            Logger.security.debug("Bookmark created for \(url.lastPathComponent, privacy: .public)")
            return data
        } catch {
            Logger.security.error("Bookmark creation failed for \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
            throw SecurityScopeError.bookmarkCreationFailed(url, underlying: error)
        }
    }

    struct ResolvedBookmark {
        let url: URL
        /// The stored data should be replaced with a fresh bookmark.
        let isStale: Bool
    }

    /// nil if the data is corrupt.
    static func resolve(_ bookmarkData: Data) -> ResolvedBookmark? {
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmarkData,
                              options: .withSecurityScope,
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            if isStale {
                Logger.security.warning("Stale bookmark resolved to \(url.lastPathComponent, privacy: .public)")
            }
            return ResolvedBookmark(url: url, isStale: isStale)
        } catch {
            Logger.security.error("Bookmark resolution failed: \(error, privacy: .public)")
            return nil
        }
    }

    /// A stored bookmark brought back to life: where it points now, a fresh
    /// bookmark if the stored one was stale, and whether the file is there.
    struct ReopenedItem {
        let url: URL
        let bookmarkData: Data
        let availability: Availability
    }

    /// nil only if the bookmark data itself cannot be resolved.
    static func reopen(_ bookmarkData: Data, name: String) -> ReopenedItem? {
        guard let resolved = resolve(bookmarkData) else {
            Logger.security.error("Bookmark unresolvable for '\(name, privacy: .public)'")
            return nil
        }
        var bookmark = bookmarkData
        if resolved.isStale {
            let accessing = resolved.url.startAccessingSecurityScopedResource()
            defer { if accessing { resolved.url.stopAccessingSecurityScopedResource() } }
            if let fresh = try? self.bookmark(for: resolved.url) {
                bookmark = fresh
                Logger.security.info("Refreshed stale bookmark for '\(name, privacy: .public)'")
            }
        }
        guard isReachable(resolved.url) else {
            Logger.security.warning("'\(name, privacy: .public)' not reachable at \(resolved.url.path(percentEncoded: false), privacy: .public)")
            return ReopenedItem(url: resolved.url, bookmarkData: bookmark,
                                availability: .unavailable(reason: String(localized: "Not found at its last known location.")))
        }
        return ReopenedItem(url: resolved.url, bookmarkData: bookmark, availability: .available)
    }

    static func isReachable(_ url: URL) -> Bool {
        (try? url.checkResourceIsReachable()) == true
    }
}
