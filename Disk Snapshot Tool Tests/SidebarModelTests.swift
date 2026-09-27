import Testing
import Foundation
@testable import Disk_Snapshot_Tool

@Suite(.serialized)
final class SidebarModelTests {
    private let library: Library
    private let sidebar: SidebarModel
    private let defaults: UserDefaults
    private let storeURL: URL
    private let vm: VMBundle
    private let vmDisk: DiskImage
    private let folderA: DiskImage
    private let folderB: DiskImage
    private let looseInBundle: DiskImage

    private static func disk(_ path: String) -> DiskImage {
        let url = URL(filePath: path)
        return DiskImage(label: url.lastPathComponent, url: url, bookmarkData: Data())
    }

    init() {
        defaults = ScratchDefaults(suiteName: nil)!

        vm = VMBundle(name: "Debian", url: URL(filePath: "/vms/Debian.utm/"), bookmarkData: Data())
        vmDisk = Self.disk("/vms/Debian.utm/Data/root.qcow2")
        vm.disks = [vmDisk]
        folderB = Self.disk("/images/b.qcow2")
        folderA = Self.disk("/images/a.qcow2")
        looseInBundle = Self.disk("/vms/Other.utm/Data/disk.qcow2")

        storeURL = FileManager.default.temporaryDirectory.appending(component: "SidebarModelTests-\(UUID().uuidString).json")
        library = Library(items: [.vm(vm), .disk(folderB), .disk(folderA), .disk(looseInBundle)],
                          store: LibraryStore(fileURL: storeURL))
        sidebar = SidebarModel(library: library, defaults: defaults)
    }

    deinit {
        try? FileManager.default.removeItem(at: storeURL)
    }

    private var folderRow: SidebarContainer { sidebar.containers[1] }

    @Test func rowsGroupBareDisksByContainer() {
        let rows = sidebar.containers
        #expect(rows.map(\.name) == ["Debian", "images", "Other"])
        #expect(rows[0].isBundle && rows[0].itemIDs == [vm.id])
        #expect(!rows[1].isBundle && rows[1].disks.map(\.label) == ["a.qcow2", "b.qcow2"], "alphabetical, not library order")
        #expect(rows[1].itemIDs == [folderB.id, folderA.id], "item ids keep library order")
        #expect(rows[2].group.kind == .utmVM && !rows[2].isBundle)
        #expect(Set(rows.map(\.id)).count == 3)
    }

    @Test func leftArrowStepsUpThenCollapses() {
        sidebar.selection = .disk(folderA.id)
        #expect(sidebar.collapseOrGoToParent())
        #expect(sidebar.selection == .container(folderRow.group.containerURL))
        #expect(sidebar.isExpanded(folderRow.group.containerURL))

        #expect(sidebar.collapseOrGoToParent())
        #expect(!sidebar.isExpanded(folderRow.group.containerURL))
        #expect(!sidebar.collapseOrGoToParent(), "nothing left to do")
        #expect(defaults.stringArray(forKey: "collapsedContainers") == [folderRow.path])
    }

    @Test func rightArrowExpandsThenEnters() {
        sidebar.setExpanded(false, for: folderRow.group.containerURL)
        sidebar.selection = .container(folderRow.group.containerURL)
        #expect(sidebar.expandOrGoToFirstChild())
        #expect(sidebar.isExpanded(folderRow.group.containerURL))
        #expect(sidebar.expandOrGoToFirstChild())
        #expect(sidebar.selection == .disk(folderA.id))
        #expect(!sidebar.expandOrGoToFirstChild(), "a disk row has nothing to expand")
    }

    @Test func removalTargetsFollowLibraryItems() throws {
        let forVMDisk = try #require(sidebar.removalTarget(forDisk: vmDisk))
        #expect(forVMDisk.name == "Debian" && forVMDisk.itemIDs == [vm.id])

        let forBareDisk = try #require(sidebar.removalTarget(forDisk: folderA))
        #expect(forBareDisk.name == "a.qcow2" && forBareDisk.itemIDs == [folderA.id])

        sidebar.selection = .container(folderRow.group.containerURL)
        #expect(sidebar.selectedRemovalTarget?.itemIDs == [folderB.id, folderA.id])
        sidebar.selection = nil
        #expect(sidebar.selectedRemovalTarget == nil)
    }

    @Test func removingAFolderRowDropsItsDisksSelectionAndCollapsedState() {
        let url = folderRow.group.containerURL
        sidebar.setExpanded(false, for: url)
        sidebar.selection = .disk(folderB.id)
        sidebar.remove(sidebar.removalTarget(for: folderRow))

        #expect(library.items.count == 2)
        #expect(library.disk(id: folderA.id) == nil && library.disk(id: folderB.id) == nil)
        #expect(sidebar.selection == nil)
        #expect(sidebar.isExpanded(url), "collapsed state must not outlive the row")
    }

    @Test func restoreSelectionOpensTheContainer() {
        sidebar.setExpanded(false, for: folderRow.group.containerURL)
        defaults.set(SidebarSelection.disk(folderB.id).storageKey, forKey: "sidebarSelection")
        sidebar.restore()
        #expect(sidebar.selection == .disk(folderB.id))
        #expect(sidebar.isExpanded(folderRow.group.containerURL))
    }

    @Test func restoreSelectionIgnoresAVanishedItem() {
        defaults.set(SidebarSelection.disk(UUID()).storageKey, forKey: "sidebarSelection")
        sidebar.restore()
        #expect(sidebar.selection == nil)
        defaults.set(SidebarSelection.container(path: "/nowhere").storageKey, forKey: "sidebarSelection")
        sidebar.restore()
        #expect(sidebar.selection == nil)
    }

    @Test func selectionIsPersisted() {
        sidebar.selection = .disk(folderA.id)
        #expect(defaults.string(forKey: "sidebarSelection") == "disk:\(folderA.id.uuidString)")
        sidebar.selection = nil
        #expect(defaults.string(forKey: "sidebarSelection") == nil)
    }

    @Test func rowsFollowExpansion() {
        // Expanded: Debian, root, images, a, b, Other, disk.
        let rows = sidebar.rows
        #expect(rows.count == 7)
        #expect(rows.map(\.containerIndex) == [0, 0, 1, 1, 1, 2, 2])
        #expect(rows.map(\.isLastInContainer) == [false, true, false, false, true, false, true])
        guard case .disk(let d) = rows[3].kind else { Issue.record("row 3 is not a disk"); return }
        #expect(d === folderA && rows[3].container.name == "images")

        sidebar.setExpanded(false, for: folderRow.group.containerURL)
        #expect(sidebar.rows.count == 5)
        #expect(sidebar.rows[2].isLastInContainer, "a collapsed container is its own last row")
        #expect(Set(sidebar.rows.map(\.id)).count == 5)
    }

    private var rows: [SidebarRow] { sidebar.rows }
    private func payload(_ index: Int) -> String { sidebar.dragPayload(for: sidebar.containers[index]) }

    @Test func dropPositionsAreContainerBoundariesOnly() {
        // Rows: [0 Debian, 1 root, 2 images, 3 a, 4 b, 5 Other, 6 disk]. Dragging Other (container 2).
        let other = payload(2)
        #expect(sidebar.dropPosition(over: rows[0], inLowerHalf: false, dragging: other) == 0)
        #expect(sidebar.dropPosition(over: rows[0], inLowerHalf: true,  dragging: other) == 1)
        #expect(sidebar.dropPosition(over: rows[1], inLowerHalf: false, dragging: other) == 1, "a disk row means after its container")
        #expect(sidebar.dropPosition(over: rows[2], inLowerHalf: false, dragging: other) == 1)
        #expect(sidebar.dropPosition(over: rows[3], inLowerHalf: true,  dragging: other) == nil, "after images is where Other already is")
        #expect(sidebar.dropPosition(over: rows[3], inLowerHalf: true,  dragging: payload(0)) == 2, "after images, below its last disk")
        #expect(sidebar.dropPosition(over: rows[6], inLowerHalf: true,  dragging: payload(0)) == 3, "after the last container")
    }

    @Test func noDropAroundTheDraggedContainerItself() {
        let images = payload(1)
        // Rows: [0 Debian, 1 root, 2 images, 3 a, 4 b, 5 Other, 6 disk].
        #expect(sidebar.dropPosition(over: rows[1], inLowerHalf: true,  dragging: images) == nil, "just above itself")
        #expect(sidebar.dropPosition(over: rows[2], inLowerHalf: false, dragging: images) == nil)
        #expect(sidebar.dropPosition(over: rows[2], inLowerHalf: true,  dragging: images) == nil, "over its own disks")
        #expect(sidebar.dropPosition(over: rows[4], inLowerHalf: true,  dragging: images) == nil, "just below itself")
        #expect(sidebar.dropPosition(over: rows[5], inLowerHalf: false, dragging: images) == nil)
        #expect(sidebar.dropPosition(over: rows[5], inLowerHalf: true,  dragging: images) == 3)
        #expect(sidebar.dropPosition(over: rows[0], inLowerHalf: false, dragging: images) == 0)
        #expect(sidebar.dropPosition(over: rows[0], inLowerHalf: false, dragging: "something else") == nil)
    }

    @Test func movingAContainerMovesItsWholeGroup() {
        sidebar.moveContainer(dragging: payload(1), to: 0)
        #expect(library.items.map(\.id) == [folderB.id, folderA.id, vm.id, looseInBundle.id],
                "the folder's disks move together and keep their library order")
        // Containers now: images, Debian, Other. Move Debian to the end.
        sidebar.moveContainer(dragging: payload(1), to: 3)
        #expect(library.items.map(\.id) == [folderB.id, folderA.id, looseInBundle.id, vm.id])
        // Move Other (index 1) before images.
        sidebar.moveContainer(dragging: payload(1), to: 0)
        #expect(library.items.map(\.id) == [looseInBundle.id, folderB.id, folderA.id, vm.id])
    }

    @Test func noOpPositionsChangeNothing() {
        let before = library.items.map(\.id)
        sidebar.moveContainer(dragging: payload(1), to: 1)
        sidebar.moveContainer(dragging: payload(1), to: 2)
        sidebar.moveContainer(dragging: "bogus", to: 0)
        #expect(library.items.map(\.id) == before)
    }

    @Test func selectedDiskAndContainer() {
        sidebar.selection = .disk(vmDisk.id)
        #expect(sidebar.selectedDisk === vmDisk)
        #expect(sidebar.selectedContainer == nil)
        sidebar.selection = .container(vm.url)
        #expect(sidebar.selectedDisk == nil)
        #expect(sidebar.selectedContainer?.name == "Debian")
    }
}
