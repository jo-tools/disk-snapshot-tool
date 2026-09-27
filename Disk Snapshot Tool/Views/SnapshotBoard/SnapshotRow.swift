import SwiftUI

struct SnapshotRow: View {
    let snapshot: Snapshot
    let isLastApplied: Bool
    let canMutate: Bool
    let group: DiskGroup
    let disk: DiskImage
    let onApply: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "camera.fill")
                .foregroundStyle(.tertiary)
                .frame(width: 18, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(snapshot.name)
                    .font(.body)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(snapshot.formattedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if snapshot.vmStateSize > 0 {
                        Text(snapshot.formattedVMStateSize)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer(minLength: 0)

            if isLastApplied {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("This snapshot was last applied. The VM has not run since.")
            }
        }
        .padding(.vertical, 5)
        // Same order as the toolbar: Apply | Delete | Reveal.
        .contextMenu {
            Button("Apply / Revert to This", systemImage: "arrow.uturn.backward.circle", action: onApply)
                .disabled(!canMutate)
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                .disabled(!canMutate)
            Divider()
            RevealButtons(group: group, disk: disk)
        }
    }
}
