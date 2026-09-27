import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SidebarView: View {
    @Environment(Library.self) private var library
    @Environment(SidebarModel.self) private var sidebar
    @Environment(\.self) private var environment
    @State private var removalTarget: SidebarModel.RemovalTarget?
    @State private var dropPosition: Int?
    @State private var rowFrames: [String: CGRect] = [:]

    private nonisolated static let rowSpace = "sidebarRows"

    var body: some View {
        @Bindable var sidebar = sidebar
        List(selection: $sidebar.selection) {
            // Not List's onMove: it offers a slot between every two rows and cannot be told otherwise.
            ForEach(sidebar.rows) { row in
                rowView(row)
                    .overlay(alignment: .top) {
                        if case .container = row.kind, row.containerIndex == 0, dropPosition == 0 {
                            DropLine()
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if row.isLastInContainer, dropPosition == row.containerIndex + 1 {
                            DropLine()
                        }
                    }
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: RowFramesKey.self,
                                                   value: [row.id: geometry.frame(in: .named(Self.rowSpace))])
                        }
                    }
            }
        }
        .coordinateSpace(name: Self.rowSpace)
        .onPreferenceChange(RowFramesKey.self) { frames in
            MainActor.assumeIsolated { rowFrames = frames }
        }
        .listStyle(.sidebar)
        .onKeyPress(.leftArrow)  { sidebar.collapseOrGoToParent()   ? .handled : .ignored }
        .onKeyPress(.rightArrow) { sidebar.expandOrGoToFirstChild() ? .handled : .ignored }
        .navigationTitle("Disk Snapshot Tool")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Add", systemImage: "plus") { OpenPanel.run(completion: add) }
                    .help("Add a disk image or a UTM VM")
            }
        }
        .onDrop(of: [.fileURL, .plainText], delegate: SidebarDropDelegate(
            containers: ContainerDropDelegate(sidebar: sidebar, rows: sidebar.rows,
                                              rowFrames: rowFrames, dropPosition: $dropPosition),
            files: DiskDropDelegate(accept: add)))
        .focusedSceneValue(\.sidebar, SidebarActions(
            openImporter: { OpenPanel.run(completion: add) },
            removeSelected: sidebar.selectedRemovalTarget.map { target in { removalTarget = target } }
        ))
        .alert("Remove from List?",
               isPresented: Binding(get: { removalTarget != nil },
                                    set: { if !$0 { removalTarget = nil } }),
               presenting: removalTarget) { target in
            Button("Remove", role: .destructive) { sidebar.remove(target) }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            if target.itemIDs.count == 1 {
                Text("\"\(target.name)\" will be removed from the sidebar. The file on disk is not affected.")
            } else {
                Text("\(target.itemIDs.count) disk images under \"\(target.name)\" will be removed from the sidebar. The files on disk are not affected.")
            }
        }
        .alert("Could Not Add File",
               isPresented: Binding(get: { library.importError != nil },
                                    set: { if !$0 { library.importError = nil } }),
               presenting: library.importError) { _ in
            Button("OK", role: .cancel) { library.importError = nil }
        } message: { message in
            Text(message)
        }
    }

    @ViewBuilder
    private func rowView(_ row: SidebarRow) -> some View {
        switch row.kind {
        case .container:
            ContainerRow(container: row.container) {
                removalTarget = sidebar.removalTarget(for: row.container)
            }
            .onDrag {
                NSItemProvider(object: sidebar.dragPayload(for: row.container) as NSString)
            } preview: {
                // The row again, at the row's size. Drag images are rendered without
                // the window's appearance, so the vibrant text is pinned to the
                // resolved label colour here and left vibrant in the row itself.
                ContainerRow(container: row.container, onRemove: {})
                    .environment(sidebar)
                    .foregroundStyle(Color(Color.primary.resolve(in: environment)))
                    .frame(width: rowFrames[row.id]?.width, height: rowFrames[row.id]?.height)
            }
        case .disk(let disk):
            DiskRow(disk: disk, group: row.container.group) {
                removalTarget = sidebar.removalTarget(forDisk: disk)
            }
        }
    }

    private func add(_ urls: [URL]) {
        Task { for url in urls { await sidebar.add(url) } }
    }
}

private nonisolated struct RowFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
