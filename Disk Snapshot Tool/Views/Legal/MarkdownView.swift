import SwiftUI

/// Renders parsed Markdown blocks.
///
/// SwiftUI's `Text` draws an `AttributedString` but does not act on
/// `inlinePresentationIntent`, so emphasis, strong and code spans are turned
/// into real font attributes here before the text is handed over.
struct MarkdownView: View {
    let blocks: [MarkdownBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Positional ids: the block list is rebuilt wholesale whenever the
            // document changes, so nothing is diffed across documents.
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(styled(text, base: headingFont(level)))
                .textSelection(.enabled)
                .padding(.top, level <= 2 ? 10 : 4)

        case .paragraph(let text):
            Text(styled(text))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

        case .listItem(let marker, let text, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(marker)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 16, alignment: .trailing)
                Text(styled(text))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, CGFloat(indent) * 20)

        case .blockQuote(let text):
            HStack(alignment: .top, spacing: 10) {
                Rectangle()
                    .fill(.tertiary)
                    .frame(width: 3)
                Text(styled(text))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .codeBlock(let code):
            Text(code)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 6))

        case .table(let table):
            MarkdownTableView(table: table, style: styled)

        case .thematicBreak:
            Divider().padding(.vertical, 4)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1:  return .title2.bold()
        case 2:  return .title3.bold()
        case 3:  return .headline
        default: return .subheadline.bold()
        }
    }

    /// Turns inline intents into font attributes, and tints links.
    ///
    /// The base font is applied here rather than with a `.font()` modifier on the
    /// `Text`, because a font carried by the `AttributedString` overrides the
    /// modifier — set one without the other and every heading comes out at body
    /// size.
    private func styled(_ text: AttributedString, base: Font = .body) -> AttributedString {
        var out = text
        for run in out.runs {
            let intent = run.inlinePresentationIntent ?? []
            var font = base
            if intent.contains(.code) {
                font = base.monospaced()
            }
            if intent.contains(.stronglyEmphasized) { font = font.bold() }
            if intent.contains(.emphasized)         { font = font.italic() }
            out[run.range].font = font
            if intent.contains(.strikethrough) {
                out[run.range].strikethroughStyle = .single
            }
            if out[run.range].link != nil {
                out[run.range].foregroundColor = .accentColor
                out[run.range].underlineStyle = .single
            }
        }
        return out
    }
}

/// A Markdown table, laid out as a Grid so columns line up across rows.
private struct MarkdownTableView: View {
    let table: MarkdownTable
    let style: (AttributedString, Font) -> AttributedString

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 7) {
            if !table.header.isEmpty {
                GridRow {
                    ForEach(Array(cells(table.header).enumerated()), id: \.offset) { column, cell in
                        Text(style(cell, .body.weight(.semibold)))
                            .cellWrapping(alignment(column))
                    }
                }
                Divider().gridCellColumns(table.columnCount)
            }
            ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(cells(row).enumerated()), id: \.offset) { column, cell in
                        Text(style(cell, .body))
                            .cellWrapping(alignment(column))
                    }
                }
            }
        }
        .textSelection(.enabled)
        .padding(.vertical, 4)
    }

    /// Pads a short row so every row has the same number of cells; a Grid with
    /// ragged rows misaligns the columns after the gap.
    private func cells(_ row: [AttributedString]) -> [AttributedString] {
        row + Array(repeating: AttributedString(), count: max(0, table.columnCount - row.count))
    }

    private func alignment(_ column: Int) -> Alignment {
        switch table.alignment(column: column) {
        case .leading:  return .leading
        case .center:   return .center
        case .trailing: return .trailing
        }
    }
}

private extension View {
    /// A table cell wraps rather than truncates. These documents carry long bare
    /// URLs, and an ellipsis in a license notice hides text that cannot then be
    /// selected or read at all.
    func cellWrapping(_ alignment: Alignment) -> some View {
        self.fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: alignment)
    }
}
