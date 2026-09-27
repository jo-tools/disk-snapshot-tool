import Foundation
import OSLog

/// One entry of library.json.
///
/// The associated values are labelled so the file reads `record` rather than
/// the `_0` a synthesised unlabelled payload would produce.
enum LibraryRecord: Codable {
    case vmBundle(record: VMBundleRecord)
    case diskImage(record: DiskImageRecord)

    struct VMBundleRecord: Codable {
        let id: UUID
        let bookmarkData: Data
        var cachedName: String
        var cachedPath: String
    }

    /// Only a disk image added on its own. A VM's disks are rebuilt from the
    /// bundle's config.plist on every launch and are not stored.
    struct DiskImageRecord: Codable {
        let id: UUID
        let bookmarkData: Data
        var cachedLabel: String
        var cachedPath: String
    }
}

/// Reads and writes library.json. Each item is an app-scoped bookmark plus
/// the name and path to show while the file is unavailable.
///
/// Which file that is, is the caller's decision: see AppEnvironment.
final class LibraryStore {
    /// nil keeps the library in memory only.
    private let fileURL: URL?
    /// Off once the file could neither be read nor set aside, so that the
    /// empty list the app carries on with never replaces it.
    private var mayWrite = true

    init(fileURL: URL?) {
        self.fileURL = fileURL
    }

    // MARK: Load

    /// Decodes one record or nothing. Returning normally from `init(from:)` is
    /// what lets the array decoder move on to the next element.
    private struct LenientRecord: Decodable {
        let record: LibraryRecord?
        init(from decoder: Decoder) throws {
            record = try? LibraryRecord(from: decoder)
        }
    }

    func load() -> [LibraryRecord] {
        guard let fileURL else { return [] }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            Logger.library.info("No library file — starting empty")
            return []
        } catch {
            Logger.library.error("Library file unreadable, leaving it untouched: \(error, privacy: .public)")
            mayWrite = false
            return []
        }
        guard let decoded = try? Self.decodeRecords(from: data) else {
            mayWrite = setAside(fileURL)
            return []
        }
        if decoded.skipped > 0 {
            Logger.library.error("Skipped \(decoded.skipped, privacy: .public) unreadable record(s)")
        }
        Logger.library.info("Loaded \(decoded.records.count, privacy: .public) record(s) from library")
        return decoded.records
    }

    /// Record by record, so one unreadable entry does not discard every good
    /// one. Throws only when the data is not a JSON array at all.
    static func decodeRecords(from data: Data) throws -> (records: [LibraryRecord], skipped: Int) {
        let entries = try JSONDecoder().decode([LenientRecord].self, from: data)
        let records = entries.compactMap(\.record)
        return (records, entries.count - records.count)
    }

    /// Moves an undecodable file out of the way so the user's only copy
    /// survives the next save. Returns whether that worked.
    private func setAside(_ fileURL: URL) -> Bool {
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        let aside = fileURL.deletingLastPathComponent()
            .appending(component: "library-unreadable-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: fileURL, to: aside)
            Logger.library.error("Library file undecodable — kept as \(aside.lastPathComponent, privacy: .public)")
            return true
        } catch {
            Logger.library.error("Library file undecodable and could not be set aside: \(error, privacy: .public)")
            return false
        }
    }

    // MARK: Save

    func save(_ records: [LibraryRecord]) {
        guard let fileURL, mayWrite else { return }
        guard let data = try? JSONEncoder().encode(records) else {
            Logger.library.error("Failed to encode library records")
            return
        }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            Logger.library.info("Saved \(records.count, privacy: .public) record(s) to library")
        } catch {
            Logger.library.error("Failed to write library file: \(error, privacy: .public)")
        }
    }
}

extension LibraryRecord {
    init(_ item: LibraryItem) {
        switch item {
        case .vm(let vm):
            self = .vmBundle(record: .init(id: vm.id, bookmarkData: vm.bookmarkData,
                                           cachedName: vm.name, cachedPath: vm.lastKnownPath))
        case .disk(let disk):
            self = .diskImage(record: .init(id: disk.id, bookmarkData: disk.bookmarkData,
                                            cachedLabel: disk.label, cachedPath: disk.lastKnownPath))
        }
    }
}
