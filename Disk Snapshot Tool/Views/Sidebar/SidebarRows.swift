import SwiftUI

/// Every context menu in the sidebar has the same shape as the snapshot
/// board's: reveal the container, reveal the file if the row is one file, then
/// remove.
struct ContainerRow: View {
    @Environment(SidebarModel.self) private var sidebar
    let container: SidebarContainer
    let onRemove: () -> Void

    private var isExpanded: Bool { sidebar.isExpanded(container.group.containerURL) }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    sidebar.setExpanded(!isExpanded, for: container.group.containerURL)
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 12, height: 16)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? Text("Collapse") : Text("Expand"))

            Label {
                HStack(spacing: 4) {
                    Text(container.name).fontWeight(.medium)
                    Spacer(minLength: 0)
                    if let status = DiskStatus.summary(availability: container.availability,
                                                       disks: container.disks) {
                        DiskStatusBadge(status: status)
                    }
                }
            } icon: {
                ContainerIcon(group: container.group, isAvailable: container.availability.isAvailable)
            }
        }
        .contextMenu {
            RevealButtons(group: container.group)
            Divider()
            Button("Remove from List", systemImage: "minus.circle", role: .destructive, action: onRemove)
        }
        .tag(SidebarSelection.container(container.group.containerURL))
    }
}

/// Both kinds are the same drawn folder; the bundle carries the UTM mark. An
/// unreachable container is dimmed, not swapped for a warning: the row's
/// trailing badge already says what is wrong.
struct ContainerIcon: View {
    let group: DiskGroup
    let isAvailable: Bool

    var body: some View {
        Image(group.kind == .utmVM ? "UTMBundleIcon" : "FolderIcon")
            .resizable()
            .frame(width: 16, height: 16)
            .opacity(isAvailable ? 1 : 0.4)
    }
}

struct DiskRow: View {
    let disk: DiskImage
    let group: DiskGroup
    let onRemove: () -> Void

    var body: some View {
        Label {
            HStack(spacing: 4) {
                Text(disk.label)
                Spacer(minLength: 0)
                ForEach(DiskStatus.all(for: disk)) { status in
                    DiskStatusBadge(status: status)
                }
            }
        } icon: {
            Image(systemName: disk.availability.isAvailable ? "internaldrive" : "internaldrive.fill")
                .foregroundStyle(disk.availability.isAvailable ? Color.primary : Color.orange)
        }
        .padding(.leading, 18)
        .contextMenu {
            RevealButtons(group: group, disk: disk)
            Divider()
            Button("Remove from List", systemImage: "minus.circle", role: .destructive, action: onRemove)
        }
        .tag(SidebarSelection.disk(disk.id))
    }
}
