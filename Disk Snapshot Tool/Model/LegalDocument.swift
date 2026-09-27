import Foundation

/// A licensing document the build copied into `Contents/Resources`, shown in the
/// app's own window rather than handed to whatever app happens to own `.md`.
///
/// These are not decoration. The bundled `qemu-img` is GPL-2.0-only and GLib is
/// statically linked into it under LGPL-2.1, whose §6 asks for a notice in each
/// copy of the work — so every copy carries these files, and the app can show
/// them without a network connection.
nonisolated enum LegalDocument: String, Identifiable, Hashable, Codable, CaseIterable {
    case license
    case thirdPartyNotices
    case qemuOverview
    case qemuGPL
    case glib
    case proxyLibintl
    case zstd

    var id: String { rawValue }

    static let windowID = "legal-document"

    /// Window title and menu label.
    ///
    /// A license text on its own says nothing about why it is in this app, so
    /// every entry names the component it belongs to first.
    var title: String {
        switch self {
        case .license:           return String(localized: "License")
        case .thirdPartyNotices: return String(localized: "Third-Party Notices")
        case .qemuOverview:      return String(localized: "QEMU — licensing overview")
        case .qemuGPL:           return "QEMU — GPL-2.0"
        case .glib:              return "GLib — LGPL-2.1"
        case .proxyLibintl:      return "proxy-libintl — LGPL-2.0"
        case .zstd:              return "Zstandard — BSD-3-Clause"
        }
    }

    /// The full license texts, alphabetically by component. Sorted rather than
    /// listed so that adding one cannot put it out of order.
    static let fullTexts: [LegalDocument] = [
        .glib, .proxyLibintl, .qemuGPL, .qemuOverview, .zstd,
    ].sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

    /// Path inside `Contents/Resources`.
    private var resourcePath: String {
        switch self {
        case .license:           return "LICENSE"
        case .thirdPartyNotices: return "THIRD-PARTY-NOTICES.md"
        case .qemuOverview:      return "THIRD-PARTY-LICENSES/QEMU-LICENSE.txt"
        case .qemuGPL:           return "THIRD-PARTY-LICENSES/QEMU-GPL-2.0.txt"
        case .glib:              return "THIRD-PARTY-LICENSES/GLib-LGPL-2.1.txt"
        case .proxyLibintl:      return "THIRD-PARTY-LICENSES/proxy-libintl-LGPL-2.0.txt"
        case .zstd:              return "THIRD-PARTY-LICENSES/Zstandard-LICENSE.txt"
        }
    }

    init?(resourcePath: String) {
        guard let match = Self.allCases.first(where: { $0.resourcePath == resourcePath }) else { return nil }
        self = match
    }

    /// Only the notices are Markdown; a license text is verbatim and must stay
    /// that way — reflowing one would misrepresent it.
    var isMarkdown: Bool { self == .thirdPartyNotices }

    var url: URL {
        Bundle.main.bundleURL.appending(components: "Contents", "Resources")
            .appending(path: resourcePath)
    }

    /// False when the file is missing, so a menu item can disable itself instead
    /// of opening an empty window.
    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    func read() throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
