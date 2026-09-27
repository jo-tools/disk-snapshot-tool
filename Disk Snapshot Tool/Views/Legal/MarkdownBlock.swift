import Foundation

/// One rendered block of a Markdown document.
///
/// Foundation parses the Markdown; this only regroups the result. An
/// `AttributedString` from `AttributedString(markdown:)` is a flat run of
/// characters carrying `presentationIntent`, and the intent's components spell
/// out the block structure the run sits in, innermost first — a table cell's
/// intent reads `tableCell > tableRow > table`. Runs that share the same chain
/// of component identities belong to the same block, which is all the grouping
/// below does.
nonisolated enum MarkdownBlock {
    case heading(level: Int, text: AttributedString)
    case paragraph(AttributedString)
    case listItem(marker: String, text: AttributedString, indent: Int)
    case blockQuote(AttributedString)
    case codeBlock(String)
    case table(MarkdownTable)
    case thematicBreak
}

nonisolated struct MarkdownTable {
    enum Alignment { case leading, center, trailing }

    var alignments: [Alignment] = []
    var header: [AttributedString] = []
    var rows: [[AttributedString]] = []

    var columnCount: Int {
        max(alignments.count, max(header.count, rows.map(\.count).max() ?? 0))
    }

    func alignment(column: Int) -> Alignment {
        column < alignments.count ? alignments[column] : .leading
    }
}

extension MarkdownBlock {
    /// Parses `markdown` into blocks. Never throws: a document that cannot be
    /// parsed is shown as plain paragraphs rather than not shown at all, because
    /// these documents are license notices and failing to display one is worse
    /// than displaying it unformatted.
    static func blocks(from markdown: String) -> [MarkdownBlock] {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible)

        guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
            return markdown
                .components(separatedBy: "\n\n")
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { .paragraph(AttributedString($0)) }
        }
        return blocks(from: parsed)
    }

    private static func blocks(from parsed: AttributedString) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var table: MarkdownTable?
        var tableIdentity: Int?
        var pendingRow: (identity: Int, isHeader: Bool, cells: [AttributedString])?

        /// Finishes the row being collected, into the table being collected.
        func flushRow() {
            guard let row = pendingRow else { return }
            if row.isHeader {
                table?.header = row.cells
            } else {
                table?.rows.append(row.cells)
            }
            pendingRow = nil
        }

        /// Finishes the table being collected, if any.
        func flushTable() {
            flushRow()
            if let table { blocks.append(.table(table)) }
            table = nil
            tableIdentity = nil
        }

        for group in groupedRuns(of: parsed) {
            let components = group.intent?.components ?? []

            // A table arrives cell by cell, so it is assembled across groups and
            // only emitted once a run outside it turns up.
            if let cell = components.first(where: { if case .tableCell = $0.kind { return true } else { return false } }),
               let rowComponent = components.first(where: {
                   switch $0.kind {
                   case .tableRow, .tableHeaderRow: return true
                   default: return false
                   }
               }),
               let tableComponent = components.first(where: {
                   if case .table = $0.kind { return true } else { return false }
               }) {

                if tableIdentity != tableComponent.identity {
                    flushTable()
                    table = MarkdownTable(alignments: alignments(of: tableComponent))
                    tableIdentity = tableComponent.identity
                }
                let isHeader: Bool = {
                    if case .tableHeaderRow = rowComponent.kind { return true }
                    return false
                }()
                if pendingRow?.identity != rowComponent.identity {
                    flushRow()
                    pendingRow = (rowComponent.identity, isHeader, [])
                }
                guard case .tableCell(let column) = cell.kind else { continue }
                while (pendingRow?.cells.count ?? 0) < column {
                    pendingRow?.cells.append(AttributedString())
                }
                pendingRow?.cells.append(group.text)
                continue
            }

            flushTable()

            guard let block = block(for: components, text: group.text) else { continue }
            blocks.append(block)
        }
        flushTable()

        return blocks
    }

    private static func block(for components: [PresentationIntent.IntentType],
                              text: AttributedString) -> MarkdownBlock? {
        let trimmed = text.trimmedTrailingNewlines()

        // A list item's intent is `paragraph > listItem > unorderedList`, so the
        // list components are looked for before falling back to the innermost.
        if let item = components.first(where: {
            if case .listItem = $0.kind { return true } else { return false }
        }) {
            guard case .listItem(let ordinal) = item.kind else { return nil }
            let lists = components.filter {
                switch $0.kind {
                case .unorderedList, .orderedList: return true
                default: return false
                }
            }
            let isOrdered = lists.first.map {
                if case .orderedList = $0.kind { return true } else { return false }
            } ?? false
            return .listItem(marker: isOrdered ? "\(ordinal)." : "•",
                             text: trimmed,
                             indent: max(0, lists.count - 1))
        }

        // Order matters, and it is not the order the components come in. A
        // block quote's chain is `paragraph > blockQuote`, so scanning for the
        // first recognised component would find the paragraph and quietly
        // demote every quote to body text. Paragraph is the fallback, checked
        // last, never first.
        for component in components {
            if case .header(let level) = component.kind {
                return .heading(level: level, text: trimmed)
            }
        }
        for component in components {
            if case .codeBlock = component.kind {
                return .codeBlock(String(text.characters).trimmedTrailingNewlines())
            }
        }
        for component in components {
            if case .thematicBreak = component.kind { return .thematicBreak }
        }
        for component in components {
            if case .blockQuote = component.kind {
                return trimmed.characters.isEmpty ? nil : .blockQuote(trimmed)
            }
        }
        return trimmed.characters.isEmpty ? nil : .paragraph(trimmed)
    }

    private static func alignments(of table: PresentationIntent.IntentType) -> [MarkdownTable.Alignment] {
        guard case .table(let columns) = table.kind else { return [] }
        return columns.map {
            switch $0.alignment {
            case .left:   return .leading
            case .center: return .center
            case .right:  return .trailing
            @unknown default: return .leading
            }
        }
    }

    // MARK: Run grouping

    private struct RunGroup {
        let intent: PresentationIntent?
        var text: AttributedString
    }

    /// Consecutive runs that sit in the same block, merged. Two runs belong
    /// together when their intents' component identities match; the identities
    /// are what distinguish two adjacent paragraphs from one.
    private static func groupedRuns(of parsed: AttributedString) -> [RunGroup] {
        var groups: [RunGroup] = []
        var previousKey: [Int]?

        for run in parsed.runs {
            let intent = run.presentationIntent
            let key = intent?.components.map(\.identity) ?? []
            var piece = AttributedString(parsed[run.range])
            piece.presentationIntent = nil

            if key == previousKey, !groups.isEmpty, previousKey != nil {
                groups[groups.count - 1].text.append(piece)
            } else {
                groups.append(RunGroup(intent: intent, text: piece))
                previousKey = key
            }
        }
        return groups
    }
}

private extension AttributedString {
    /// Markdown blocks arrive with their trailing newline attached.
    func trimmedTrailingNewlines() -> AttributedString {
        var copy = self
        while let last = copy.characters.last, last.isNewline {
            copy.removeSubrange(copy.index(beforeCharacter: copy.endIndex)..<copy.endIndex)
        }
        return copy
    }
}

private extension String {
    func trimmedTrailingNewlines() -> String {
        var copy = self
        while let last = copy.last, last.isNewline { copy.removeLast() }
        return copy
    }
}
