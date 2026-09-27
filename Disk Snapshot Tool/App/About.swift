import AppKit

/// The project's outward-facing links.
///
/// There is deliberately no code here for the About panel. macOS builds that
/// itself from the bundle: the name, version and `NSHumanReadableCopyright` come
/// from `Info.plist`, and the credits area is read from `Resources/Credits.html`.
/// Replacing the standard About menu item to do the same thing by hand only
/// costs it the system's own icon and behaviour.
enum About {
    static let repositoryURL = URL(string: "https://github.com/jo-tools/disk-snapshot-tool")!
    static let issuesURL     = URL(string: "https://github.com/jo-tools/disk-snapshot-tool/issues")!
    static let donationURL   = URL(string: "https://paypal.me/jotools")!

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
