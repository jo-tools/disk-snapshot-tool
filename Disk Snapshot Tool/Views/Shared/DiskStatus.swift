import SwiftUI

/// The one place a disk's state becomes UI. The sidebar shows these as badges,
/// the snapshot board as banners, so symbol, tint, wording and precedence are
/// defined once. The board's error banner is not one of these: it reports a
/// failed qemu-img call and has its own Dismiss.
enum DiskStatus: Identifiable, Equatable {
    case unavailable(reason: String)
    case cannotSnapshot(format: String)
    case inUse(snapshotsReadable: Bool)

    var id: String {
        switch self {
        case .unavailable:    return "unavailable"
        case .cannotSnapshot: return "cannotSnapshot"
        case .inUse:          return "inUse"
        }
    }

    /// Every status that applies, most structural first. `unavailable` stands
    /// alone: while the file is out of reach its format and lock state are
    /// unknown. The other two can both apply; the format comes first because it
    /// is the permanent reason.
    static func all(for disk: DiskImage) -> [DiskStatus] {
        if case .unavailable(let reason) = disk.availability {
            return [.unavailable(reason: reason)]
        }
        var statuses: [DiskStatus] = []
        if disk.hasKnownUnsupportedFormat {
            statuses.append(.cannotSnapshot(format: disk.formatDisplayName))
        }
        if disk.isInUse {
            statuses.append(.inUse(snapshotsReadable: disk.supportsSnapshots))
        }
        return statuses
    }

    /// The single badge for a whole VM bundle or folder. A container reports
    /// its children's unreachability because a collapsed row hides their own
    /// badges. `cannotSnapshot` does not aggregate: it belongs to one disk, and
    /// flagging the whole VM for it would overstate the case.
    static func summary(availability: Availability, disks: [DiskImage]) -> DiskStatus? {
        if case .unavailable(let reason) = availability {
            return .unavailable(reason: reason)
        }
        let missing = disks.filter { !$0.availability.isAvailable }
        if let only = missing.first, missing.count == 1 {
            return .unavailable(reason: String(localized: "\"\(only.label)\" cannot be reached."))
        }
        if !missing.isEmpty {
            return .unavailable(reason: String(localized: "\(missing.count) of these disk images cannot be reached."))
        }
        guard let running = disks.first(where: { $0.isInUse }) else { return nil }
        return .inUse(snapshotsReadable: running.supportsSnapshots)
    }

    var symbol: String {
        switch self {
        case .unavailable:    return "exclamationmark.circle.fill"
        case .cannotSnapshot: return "slash.circle.fill"
        case .inUse:          return "play.circle.fill"
        }
    }

    /// `cannotSnapshot` is neutral on purpose: nothing is wrong with a raw
    /// image. Orange stays reserved for real problems.
    var tint: Color {
        switch self {
        case .unavailable:    return .orange
        case .cannotSnapshot: return .secondary
        case .inUse:          return .green
        }
    }

    /// One sentence per line in the banner, so a narrow window wraps a whole
    /// sentence rather than leaving one word of it on a line of its own.
    var lines: [String] {
        switch self {
        case .unavailable(let reason):
            return [reason]
        case .cannotSnapshot(let format):
            return [String(localized: "This disk image is in \(format) format."), String(localized: "Snapshots require qcow2.")]
        case .inUse(let snapshotsReadable):
            let base = String(localized: "This disk image is in use by another process, such as a running virtual machine.")
            return snapshotsReadable ? [base, String(localized: "Snapshots can be viewed but not changed.")] : [base]
        }
    }

    /// The badge's tooltip, where line breaks would only get in the way.
    var message: String { lines.joined(separator: " ") }
}

/// Icon only: a caption would change the row height whenever a VM starts or
/// stops and make the sidebar jump.
struct DiskStatusBadge: View {
    let status: DiskStatus

    var body: some View {
        Image(systemName: status.symbol)
            .foregroundStyle(status.tint)
            .help(status.message)
    }
}

struct DiskStatusBanner: View {
    let status: DiskStatus

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: status.symbol)
                .foregroundStyle(status.tint)
            Text(status.lines.joined(separator: "\n"))
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(status.tint.opacity(0.12))
    }
}
