import Testing
import Foundation
@testable import Disk_Snapshot_Tool

struct MarkdownBlockTests {
    private func blocks(_ markdown: String) -> [MarkdownBlock] {
        MarkdownBlock.blocks(from: markdown)
    }

    @Test func headingsKeepTheirLevel() {
        let parsed = blocks("# One\n\n## Two\n\n### Three")
        let levels: [Int] = parsed.compactMap {
            if case .heading(let level, _) = $0 { return level }
            return nil
        }
        #expect(levels == [1, 2, 3])
    }

    @Test func adjacentParagraphsDoNotMerge() {
        let parsed = blocks("First one.\n\nSecond one.")
        let texts: [String] = parsed.compactMap {
            if case .paragraph(let text) = $0 { return String(text.characters) }
            return nil
        }
        #expect(texts == ["First one.", "Second one."])
    }

    @Test func inlineMarkupStaysInOneParagraph() {
        let parsed = blocks("Plain *emphasis* and **strong** and `code`.")
        #expect(parsed.count == 1)
        guard case .paragraph(let text) = parsed[0] else {
            Issue.record("expected a paragraph, got \(parsed)")
            return
        }
        #expect(String(text.characters) == "Plain emphasis and strong and code.")
        // The intents must survive grouping — MarkdownView turns them into fonts.
        let intents = text.runs.compactMap(\.inlinePresentationIntent)
        #expect(intents.contains(.emphasized))
        #expect(intents.contains(.stronglyEmphasized))
        #expect(intents.contains(.code))
    }

    @Test func linksSurviveGrouping() {
        let parsed = blocks("See [the notices](https://example.com/notices) for details.")
        guard case .paragraph(let text) = parsed[0] else {
            Issue.record("expected a paragraph")
            return
        }
        let links = text.runs.compactMap(\.link)
        #expect(links.map(\.absoluteString) == ["https://example.com/notices"])
    }

    @Test func listsCarryMarkersAndOrdinals() {
        let parsed = blocks("- alpha\n- beta\n\n1. first\n2. second")
        let markers: [String] = parsed.compactMap {
            if case .listItem(let marker, _, _) = $0 { return marker }
            return nil
        }
        #expect(markers == ["•", "•", "1.", "2."])
    }

    @Test func tablesKeepHeaderRowsAndAlignment() {
        let parsed = blocks("""
        | Component | Version | License |
        |---|:---:|---:|
        | QEMU | 11.1.1 | GPL-2.0 |
        | GLib | 2.88.0 | LGPL-2.1 |
        """)
        guard parsed.count == 1, case .table(let table) = parsed[0] else {
            Issue.record("expected one table, got \(parsed)")
            return
        }
        #expect(table.header.map { String($0.characters) } == ["Component", "Version", "License"])
        #expect(table.rows.count == 2)
        #expect(table.rows[0].map { String($0.characters) } == ["QEMU", "11.1.1", "GPL-2.0"])
        #expect(table.columnCount == 3)
        #expect(table.alignment(column: 0) == .leading)
        #expect(table.alignment(column: 1) == .center)
        #expect(table.alignment(column: 2) == .trailing)
    }

    @Test func twoTablesDoNotRunTogether() {
        let parsed = blocks("""
        | A |
        |---|
        | 1 |

        Between them.

        | B |
        |---|
        | 2 |
        """)
        let tables: [MarkdownTable] = parsed.compactMap {
            if case .table(let table) = $0 { return table }
            return nil
        }
        #expect(tables.count == 2)
        #expect(tables[0].header.map { String($0.characters) } == ["A"])
        #expect(tables[1].header.map { String($0.characters) } == ["B"])
    }

    @Test func blockQuotesCodeBlocksAndRulesAreRecognised() {
        let parsed = blocks("> quoted\n\n```\ncode line\n```\n\n---")
        var sawQuote = false, sawCode = false, sawRule = false
        for block in parsed {
            switch block {
            case .blockQuote(let text): sawQuote = String(text.characters) == "quoted"
            case .codeBlock(let code):  sawCode = code == "code line"
            case .thematicBreak:        sawRule = true
            default: break
            }
        }
        #expect(sawQuote)
        #expect(sawCode)
        #expect(sawRule)
    }

    /// The document this viewer exists for. Asserted by shape rather than by
    /// counts, so that editing the notices cannot fail this test for the wrong
    /// reason — what matters is that the structure survives, not how much of it
    /// there currently is.
    @Test func theRealNoticesDocumentParses() throws {
        let document = LegalDocument.thirdPartyNotices
        try #require(document.isAvailable, "THIRD-PARTY-NOTICES.md was not copied into the bundle")

        let text = try document.read()
        let parsed = blocks(text)

        // It opens with its own title, so the chain starts at a heading.
        guard case .heading(let level, let title) = parsed.first else {
            Issue.record("expected a heading first, got \(String(describing: parsed.first))")
            return
        }
        #expect(level == 1)
        #expect(String(title.characters) == "Third-Party Notices")

        // Every kind the document actually uses must survive the round trip.
        var kinds = Set<String>()
        for block in parsed {
            switch block {
            case .heading:   kinds.insert("heading")
            case .paragraph: kinds.insert("paragraph")
            case .listItem:  kinds.insert("listItem")
            case .table:     kinds.insert("table")
            default: break
            }
        }
        #expect(kinds == ["heading", "paragraph", "listItem", "table"])

        // The point of the test: no block may swallow the document. A parser that
        // failed to split blocks would return one run holding nearly everything.
        let longest = parsed.map(plainTextLength).max() ?? 0
        #expect(longest < text.count / 4,
                "one block holds \(longest) of \(text.count) characters — blocks are not being split")
    }

    private func plainTextLength(_ block: MarkdownBlock) -> Int {
        switch block {
        case .heading(_, let text), .paragraph(let text),
             .listItem(_, let text, _), .blockQuote(let text):
            return text.characters.count
        case .codeBlock(let code):
            return code.count
        case .table(let table):
            return (table.header + table.rows.flatMap { $0 })
                .reduce(0) { $0 + $1.characters.count }
        case .thematicBreak:
            return 0
        }
    }

    @Test func everyLegalDocumentIsInTheBundle() {
        for document in LegalDocument.allCases {
            #expect(document.isAvailable, "missing from the app bundle: \(document.title)")
        }
    }
}
