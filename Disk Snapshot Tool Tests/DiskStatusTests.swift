import Testing
import Foundation
@testable import Disk_Snapshot_Tool

struct DiskStatusTests {
    private func disk(_ label: String = "disk.qcow2", format: String? = "qcow2",
                      inUse: Bool = false, availability: Availability = .available) -> DiskImage {
        let d = DiskImage(label: label, url: URL(filePath: "/vm/\(label)"), bookmarkData: Data())
        d.format = format
        d.isInUse = inUse
        d.availability = availability
        return d
    }

    @Test func unavailableStandsAlone() {
        let d = disk(format: "raw", inUse: true, availability: .unavailable(reason: "gone"))
        #expect(DiskStatus.all(for: d) == [.unavailable(reason: "gone")])
    }

    @Test func formatBeforeInUse() {
        #expect(DiskStatus.all(for: disk(format: "raw", inUse: true))
                == [.cannotSnapshot(format: "raw"), .inUse(snapshotsReadable: false)])
        #expect(DiskStatus.all(for: disk(inUse: true)) == [.inUse(snapshotsReadable: true)])
        #expect(DiskStatus.all(for: disk()) == [])
    }

    @Test func unknownFormatClaimsNothing() {
        #expect(DiskStatus.all(for: disk(format: nil)) == [])
        #expect(!disk(format: nil).canMutate)
        #expect(!disk(format: nil).hasKnownUnsupportedFormat)
    }

    @Test func canMutateNeedsEverything() {
        #expect(disk().canMutate)
        #expect(!disk(inUse: true).canMutate)
        #expect(!disk(format: "vmdk").canMutate)
        #expect(!disk(availability: .unavailable(reason: "x")).canMutate)
        let loading = disk(); loading.isLoading = true
        #expect(!loading.canMutate)
    }

    @Test func summaryPrefersContainerThenMissingThenRunning() {
        let running = disk("a.qcow2", inUse: true)
        let missing1 = disk("b.qcow2", availability: .unavailable(reason: "gone"))
        let missing2 = disk("c.qcow2", availability: .unavailable(reason: "gone"))

        #expect(DiskStatus.summary(availability: .unavailable(reason: "bundle gone"), disks: [running])
                == .unavailable(reason: "bundle gone"))
        #expect(DiskStatus.summary(availability: .available, disks: [running, missing1])
                == .unavailable(reason: "\"b.qcow2\" cannot be reached."))
        #expect(DiskStatus.summary(availability: .available, disks: [missing1, missing2])
                == .unavailable(reason: "2 of these disk images cannot be reached."))
        #expect(DiskStatus.summary(availability: .available, disks: [disk(), running])
                == .inUse(snapshotsReadable: true))
        #expect(DiskStatus.summary(availability: .available, disks: [disk()]) == nil)
    }

    @Test func formatDisplayNames() {
        #expect(disk(format: "vmdk").formatDisplayName == "VMDK")
        #expect(disk(format: "qcow2").formatDisplayName == "qcow2")
        #expect(disk(format: nil).formatDisplayName == "unknown")
    }
}
