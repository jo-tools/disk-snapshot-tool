import Testing
import Foundation
@testable import Disk_Snapshot_Tool

struct SidebarSelectionTests {
    @Test func diskSelectionRoundTrips() {
        let id = UUID()
        let selection = SidebarSelection.disk(id)
        #expect(SidebarSelection(storageKey: selection.storageKey) == selection)
    }

    @Test func containerSelectionRoundTripsWithColonInPath() {
        let selection = SidebarSelection.container(URL(filePath: "/Volumes/VMs/odd:name/Test.utm"))
        #expect(SidebarSelection(storageKey: selection.storageKey) == selection)
        #expect(selection.containerPath == "/Volumes/VMs/odd:name/Test.utm")
    }

    @Test func rejectsUnknownAndEmptyKeys() {
        #expect(SidebarSelection(storageKey: "bogus:123") == nil)
        #expect(SidebarSelection(storageKey: "disk:not-a-uuid") == nil)
        #expect(SidebarSelection(storageKey: "container:") == nil)
        #expect(SidebarSelection(storageKey: "no-separator") == nil)
    }

    @Test func containerKeyNormalisesSpelling() {
        let plain = URL(filePath: "/Users/me/VMs/Test.utm")
        let slash = URL(filePath: "/Users/me/VMs/Test.utm/")
        let encoded = URL(string: "file:///Users/me/VMs/Test%2Eutm")!
        #expect(SidebarSelection.key(for: plain) == SidebarSelection.key(for: slash))
        #expect(SidebarSelection.key(for: plain) == SidebarSelection.key(for: encoded))
        #expect(SidebarSelection.container(plain) == SidebarSelection.container(slash))
    }

    @Test func accessorsMatchCase() {
        let id = UUID()
        #expect(SidebarSelection.disk(id).diskID == id)
        #expect(SidebarSelection.disk(id).containerPath == nil)
        #expect(SidebarSelection.container(path: "/x").diskID == nil)
    }
}
