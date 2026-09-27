import Testing
import Foundation
@testable import Disk_Snapshot_Tool

struct UTMBundleReaderTests {
    private let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0"><dict>
      <key>ConfigurationVersion</key><integer>4</integer>
      <key>Information</key><dict>
        <key>Name</key><string>Debian 13</string>
        <key>UUID</key><string>0C9D2E4A-1111-2222-3333-444444444444</string>
      </dict>
      <key>Drive</key><array>
        <dict>
          <key>Identifier</key><string>drive0</string>
          <key>ImageName</key><string>disk.qcow2</string>
          <key>ImageType</key><string>Disk</string>
          <key>Interface</key><string>VirtIO</string>
        </dict>
        <dict>
          <key>Identifier</key><string>drive1</string>
          <key>ImageType</key><string>CD</string>
          <key>Interface</key><string>USB</string>
        </dict>
        <dict>
          <key>Identifier</key><string>drive2</string>
          <key>ImageType</key><string>Disk</string>
        </dict>
      </array>
    </dict></plist>
    """

    @Test func decodesNameAndDrives() throws {
        let config = try PropertyListDecoder().decode(UTMConfig.self, from: Data(plist.utf8))
        #expect(config.information.name == "Debian 13")
        #expect(config.drive.count == 3)
        #expect(config.drive[0].isDisk)
        #expect(config.drive[0].imageName == "disk.qcow2")
        #expect(config.drive[0].interface == "VirtIO")
        #expect(!config.drive[1].isDisk)
        #expect(config.drive[2].isDisk)
        #expect(config.drive[2].imageName == nil)
        #expect(config.drive[2].interface == nil)
    }

    /// Apple Virtualization drives have no ImageType or Interface.
    @Test func decodesAppleBackendDrives() throws {
        let apple = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
          <key>Backend</key><string>Apple</string>
          <key>Information</key><dict><key>Name</key><string>macOS</string></dict>
          <key>Drive</key><array>
            <dict>
              <key>Identifier</key><string>A</string>
              <key>ImageName</key><string>disk.img</string>
              <key>Nvme</key><false/>
              <key>ReadOnly</key><false/>
            </dict>
            <dict>
              <key>Identifier</key><string>B</string>
              <key>ImageName</key><string>installer.iso</string>
              <key>ReadOnly</key><true/>
            </dict>
          </array>
        </dict></plist>
        """
        let config = try PropertyListDecoder().decode(UTMConfig.self, from: Data(apple.utf8))
        #expect(config.drive.map(\.isDisk) == [true, false])
        #expect(config.drive[0].imageType == nil)
    }

    @Test func scopedDiskIDIsStableAndScopedToBundle() {
        let vmA = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let vmB = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        let a1 = UTMBundleReader.scopedDiskID(vmID: vmA, driveIdentifier: "drive0")
        let a2 = UTMBundleReader.scopedDiskID(vmID: vmA, driveIdentifier: "drive0")
        let b1 = UTMBundleReader.scopedDiskID(vmID: vmB, driveIdentifier: "drive0")
        let a3 = UTMBundleReader.scopedDiskID(vmID: vmA, driveIdentifier: "drive1")
        #expect(a1 == a2)
        #expect(a1 != b1)
        #expect(a1 != a3)
    }
}
