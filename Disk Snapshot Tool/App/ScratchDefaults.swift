import Foundation

/// Defaults that live in memory and nowhere else.
///
/// A suite of its own would still leave its plist in the container: cfprefsd
/// writes the file back even after the domain has been emptied and the file
/// removed. Scratch storage is meant to leave nothing behind, so it never
/// reaches a domain at all.
///
/// UserDefaults' typed accessors read through `object(forKey:)`, so the three
/// primitives below are the whole of it.
nonisolated final class ScratchDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Any] = [:]

    override func object(forKey key: String) -> Any? {
        lock.withLock { storage[key] }
    }

    override func set(_ value: Any?, forKey key: String) {
        lock.withLock { storage[key] = value }
    }

    override func removeObject(forKey key: String) {
        lock.withLock { _ = storage.removeValue(forKey: key) }
    }
}
