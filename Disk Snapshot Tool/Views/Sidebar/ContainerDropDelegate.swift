import SwiftUI
import AppKit

/// Receives a dragged container row for the whole List. Rows carry no drop
/// modifier of their own: on macOS one would swallow the click that selects
/// the row. The target row is found from the drop point instead.
struct ContainerDropDelegate: DropDelegate {
    let sidebar: SidebarModel
    let rows: [SidebarRow]
    /// Row frames in the List's coordinate space.
    let rowFrames: [String: CGRect]
    let dropPosition: Binding<Int?>

    /// Whether the current drag is one of ours; read from the drag pasteboard,
    /// which can be consulted synchronously while the drag is judged.
    static var payload: String? {
        guard let text = NSPasteboard(name: .drag).string(forType: .string),
              text.hasPrefix(SidebarModel.dragPayloadPrefix) else { return nil }
        return text
    }

    private func position(at point: CGPoint, dragging payload: String) -> Int? {
        for row in rows {
            guard let frame = rowFrames[row.id] else { continue }
            if point.y < frame.minY { return sidebar.dropPosition(over: row, inLowerHalf: false, dragging: payload) }
            if point.y <= frame.maxY { return sidebar.dropPosition(over: row, inLowerHalf: point.y > frame.midY, dragging: payload) }
        }
        guard let last = rows.last else { return nil }
        return sidebar.dropPosition(over: last, inLowerHalf: true, dragging: payload)
    }

    func validateDrop(info: DropInfo) -> Bool {
        Self.payload != nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let position = Self.payload.flatMap { position(at: info.location, dragging: $0) }
        dropPosition.wrappedValue = position
        return DropProposal(operation: position == nil ? .forbidden : .move)
    }

    func dropExited(info: DropInfo) {
        dropPosition.wrappedValue = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { dropPosition.wrappedValue = nil }
        guard let payload = Self.payload, let position = position(at: info.location, dragging: payload) else {
            return false
        }
        sidebar.moveContainer(dragging: payload, to: position)
        return true
    }
}

/// The List's single drop target: container rows being reordered, or files
/// being added.
struct SidebarDropDelegate: DropDelegate {
    let containers: ContainerDropDelegate
    let files: DiskDropDelegate

    private var active: any DropDelegate { ContainerDropDelegate.payload != nil ? containers : files }

    func validateDrop(info: DropInfo) -> Bool { active.validateDrop(info: info) }
    func dropUpdated(info: DropInfo) -> DropProposal? { active.dropUpdated(info: info) }
    func dropExited(info: DropInfo) { active.dropExited(info: info) }
    func performDrop(info: DropInfo) -> Bool { active.performDrop(info: info) }
}

struct DropLine: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color.accentColor)
            .frame(height: 2)
            .padding(.horizontal, -4)
    }
}
