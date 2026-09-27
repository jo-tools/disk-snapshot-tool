import SwiftUI

/// Names a new snapshot. The name becomes the qcow2 tag, which cannot be
/// changed afterwards.
struct CreateSnapshotSheet: View {
    let existing: [Snapshot]
    let onCreate: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var fieldFocused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    private var problem: String? { Snapshot.problem(withName: trimmedName, existing: existing) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "camera.badge.plus")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New Snapshot")
                        .font(.headline)
                    Text("The name is stored as the QEMU snapshot tag and cannot be changed later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Snapshot Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextField("e.g. before-update, fresh-install", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onSubmit(submit)
                // An empty field needs no explanation; the disabled button says enough.
                Text(trimmedName.isEmpty ? " " : problem ?? " ")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create Snapshot", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(problem != nil)
            }
        }
        .padding(20)
        .frame(width: 380)
        .onAppear { fieldFocused = true }
    }

    private func submit() {
        guard problem == nil else { return }
        dismiss()
        onCreate(trimmedName)
    }
}
