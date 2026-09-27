import SwiftUI
import AppKit

struct DiskInfoBar: View {
    let disk: DiskImage
    let group: DiskGroup

    var body: some View {
        HStack(spacing: 12) {
            icon

            VStack(alignment: .leading, spacing: 2) {
                Text(disk.label)
                    .font(.headline)
                    .lineLimit(1)
                let typeParts = [disk.imageType, disk.interface, disk.format ?? ""]
                    .filter { !$0.isEmpty }
                if !typeParts.isEmpty {
                    Text(typeParts.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // For every image qemu-img could read, including a fully sparse raw
            // one whose on-disk size is 0.
            if disk.format != nil {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 2) {
                    GridRow {
                        Text("Virtual")
                            .foregroundStyle(.tertiary)
                            .gridColumnAlignment(.trailing)
                        Text(disk.formattedVirtualSize)
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.leading)
                    }
                    GridRow {
                        Text("On Disk")
                            .foregroundStyle(.tertiary)
                        Text(disk.formattedActualSize)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }

            // Only before the first read, so a background refresh never pushes
            // the sizes aside.
            if disk.isLoading && disk.format == nil {
                ProgressView().scaleEffect(0.7)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .contextMenu { RevealButtons(group: group, disk: disk) }
    }

    /// The VM's own document icon says which VM this disk belongs to. A loose
    /// file gets a symbol instead: .qcow2 has no declared type and would show a
    /// blank page, and .img would wrongly show the macOS disk-image icon.
    @ViewBuilder
    private var icon: some View {
        if group.kind == .utmVM {
            Image(nsImage: NSWorkspace.shared.icon(forFile: group.containerURL.path(percentEncoded: false)))
                .resizable()
                .frame(width: 30, height: 30)
        } else {
            Image(systemName: "internaldrive")
                .font(.system(size: 23))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
        }
    }
}
