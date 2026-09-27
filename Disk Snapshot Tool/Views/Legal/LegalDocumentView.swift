import SwiftUI

/// Shows one licensing document in the app's own window.
///
/// The documents are read from `Contents/Resources`, where the build put them,
/// so this works offline and shows exactly what this copy of the app ships —
/// which is the point of carrying them at all.
struct LegalDocumentView: View {
    let document: LegalDocument

    @Environment(\.openWindow) private var openWindow
    @State private var content: Result<String, Error>?

    var body: some View {
        ScrollView {
            Group {
                switch content {
                case .success(let text) where document.isMarkdown:
                    MarkdownView(blocks: MarkdownBlock.blocks(from: text))
                case .success(let text):
                    // A license text is verbatim: fixed pitch, no reflow, no
                    // styling. Rewrapping one would misrepresent it.
                    Text(text)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .failure(let error):
                    unavailable(error.localizedDescription)
                case nil:
                    ProgressView().controlSize(.small)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // The notices link the other documents by their repository paths, which
        // are also their paths in the bundle.
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == nil, let linked = LegalDocument(resourcePath: url.relativeString) else {
                return .systemAction
            }
            openWindow(id: LegalDocument.windowID, value: linked)
            return .handled
        })
        .navigationTitle(document.title)
        .toolbar {
            ToolbarItem {
                Button("Reveal in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([document.url])
                }
                .help("Show this file inside the application bundle")
            }
        }
        .task(id: document) {
            content = Result { try document.read() }
        }
    }

    private func unavailable(_ reason: String) -> some View {
        ContentUnavailableView {
            Label("Document Unavailable", systemImage: "doc.questionmark")
        } description: {
            Text(reason)
        }
    }
}

#Preview("Third-Party Notices") {
    LegalDocumentView(document: .thirdPartyNotices)
        .frame(width: 720, height: 680)
}

#Preview("License") {
    LegalDocumentView(document: .license)
        .frame(width: 720, height: 680)
}
