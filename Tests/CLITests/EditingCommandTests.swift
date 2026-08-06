//
//  EditingCommandTests.swift
//  md
//
//  Exercises the four commands that rewrite a document — remove, replace,
//  insert-after and insert-before — through their happy paths, their index
//  guards, and their in-place writes.
//

import ArgumentParser
import XCTest
@testable import md

final class EditingCommandTests: XCTestCase {

    private var scratch: ScratchDirectory!

    /// Two headings, so block 1 and block 2 both exist and 3 does not.
    private let twoHeadings = "# One\n\n# Two\n"

    override func setUpWithError() throws {
        scratch = try ScratchDirectory()
    }

    override func tearDownWithError() throws {
        scratch = nil
    }

    // MARK: - Helpers

    private func run<Command: AsyncParsableCommandStub>(
        _ type: Command.Type,
        _ arguments: [String],
        on content: String
    ) async throws -> String {
        let path = try scratch.write(content, to: "document.md")
        let command = try type.parse(arguments + ["--file", path])
        return try await StandardStream.capturingStandardOutput {
            try await command.runCommand()
        }
    }

    private func runInPlace<Command: AsyncParsableCommandStub>(
        _ type: Command.Type,
        _ arguments: [String],
        on content: String
    ) async throws -> String {
        let path = try scratch.write(content, to: "document.md")
        let command = try type.parse(arguments + ["--in-place", "--file", path])
        try await command.runCommand()
        return try scratch.read("document.md")
    }

    func testEditingCommandsCanTargetAnExistingHtmlBlock() async throws {
        let source = "Before.\n\n<!--  raw HTML  -->\n\nAfter.\n"

        let removed = try await run(RemoveCommand.self, ["2"], on: source)
        XCTAssertEqual(removed, "Before.\n\nAfter.\n")

        let replaced = try await run(
            ReplaceCommand.self,
            ["2", "Replacement."],
            on: source
        )
        XCTAssertEqual(replaced, "Before.\n\nReplacement.\n\nAfter.\n")

        let insertedBefore = try await run(
            InsertBeforeCommand.self,
            ["2", "Inserted."],
            on: source
        )
        XCTAssertEqual(
            insertedBefore,
            "Before.\n\nInserted.\n\n<!--  raw HTML  -->\n\nAfter.\n"
        )

        let insertedAfter = try await run(
            InsertAfterCommand.self,
            ["2", "Inserted."],
            on: source
        )
        XCTAssertEqual(
            insertedAfter,
            "Before.\n\n<!--  raw HTML  -->\n\nInserted.\n\nAfter.\n"
        )
    }

    func testEditingCommandsUseTheWholeMultilineDelimiterTerminatedHtmlRange() async throws {
        let htmlBlocks = [
            "<script>\nscript body\n</script>",
            "<!--\ncomment body\n-->",
            "<?target\nprocessing body\n?>",
            "<!DOCTYPE\ndeclaration body>",
            "<![CDATA[\ncdata body\n]]>"
        ]

        for html in htmlBlocks {
            let source = "Before.\n\n\(html)\n\nAfter.\n"

            let removed = try await run(RemoveCommand.self, ["2"], on: source)
            XCTAssertEqual(removed, "Before.\n\nAfter.\n", "remove \(html)")

            let replaced = try await run(
                ReplaceCommand.self,
                ["2", "Replacement."],
                on: source
            )
            XCTAssertEqual(
                replaced,
                "Before.\n\nReplacement.\n\nAfter.\n",
                "replace \(html)"
            )

            let insertedAfter = try await run(
                InsertAfterCommand.self,
                ["2", "Inserted."],
                on: source
            )
            XCTAssertEqual(
                insertedAfter,
                "Before.\n\n\(html)\n\nInserted.\n\nAfter.\n",
                "insert after \(html)"
            )
        }
    }

    func testEditingAnHtmlBlockDoesNotConsumeTheParagraphAfterAUnicodeLineSeparator() async throws {
        let html = "<!-- alpha\u{2028}omega -->"
        let source = "\(html)\nAfter.\n"

        let removed = try await run(RemoveCommand.self, ["1"], on: source)
        XCTAssertEqual(removed, "After.\n")

        let insertedAfter = try await run(
            InsertAfterCommand.self,
            ["1", "Inserted."],
            on: source
        )
        XCTAssertEqual(insertedAfter, "\(html)\n\nInserted.\n\nAfter.\n")
    }

    // MARK: - remove: happy paths

    func testRemoveDropsTheNamedBlock() async throws {
        let output = try await run(RemoveCommand.self, ["1"], on: twoHeadings)
        XCTAssertEqual(output, "# Two\n")
    }

    func testRemoveDropsAnInclusiveRange() async throws {
        let content = "# One\n\n# Two\n\n# Three\n"
        let output = try await run(RemoveCommand.self, ["1", "2"], on: content)
        XCTAssertEqual(output, "# Three\n")
    }

    func testRemoveEndDefaultsToStart() async throws {
        let single = try await run(RemoveCommand.self, ["1"], on: twoHeadings)
        let explicit = try await run(RemoveCommand.self, ["1", "1"], on: twoHeadings)
        XCTAssertEqual(single, explicit)
    }

    func testRemovingEveryBlockLeavesAnEmptyDocument() async throws {
        let output = try await run(RemoveCommand.self, ["1", "2"], on: twoHeadings)
        XCTAssertEqual(output, "")
    }

    func testRemoveLeavesUntouchedBlocksByteForByte() async throws {
        let output = try await run(
            RemoveCommand.self,
            ["1"],
            on: "# One\n\n#    Loosely   spaced\n"
        )
        XCTAssertEqual(output, "#    Loosely   spaced\n")
    }

    func testRemoveInPlaceRewritesTheFile() async throws {
        let written = try await runInPlace(RemoveCommand.self, ["2"], on: twoHeadings)
        XCTAssertEqual(written, "# One\n")
    }

    // MARK: - remove: index guards

    func testRemoveRejectsAStartBelowOne() async {
        await XCTAssertThrowsErrorMessage("Start index must be >= 1, got 0") {
            _ = try await self.run(RemoveCommand.self, ["0"], on: self.twoHeadings)
        }
    }

    func testRemoveRejectsAnEndBeforeTheStart() async {
        await XCTAssertThrowsErrorMessage("End index must be >= start, got 2...1") {
            _ = try await self.run(RemoveCommand.self, ["2", "1"], on: self.twoHeadings)
        }
    }

    func testRemoveRejectsAnEndPastTheLastBlock() async {
        await XCTAssertThrowsErrorMessage("End index must be <= 2, got 3") {
            _ = try await self.run(RemoveCommand.self, ["1", "3"], on: self.twoHeadings)
        }
    }

    func testRemoveRejectsAnyIndexInAnEmptyDocument() async {
        await XCTAssertThrowsErrorMessage("End index must be <= 0, got 1") {
            _ = try await self.run(RemoveCommand.self, ["1"], on: "")
        }
    }

    func testRemoveRejectsInPlaceWithStandardInput() {
        XCTAssertThrowsError(
            try RemoveCommand.parse(["--in-place", "--stdin", "1"])
        ) { error in
            XCTAssertEqual(
                RemoveCommand.message(for: error),
                "Cannot use --in-place with --stdin"
            )
        }
    }

    // MARK: - replace: happy paths

    func testReplaceSwapsASingleBlock() async throws {
        let output = try await run(
            ReplaceCommand.self,
            ["1", "# New"],
            on: twoHeadings
        )
        XCTAssertEqual(output, "# New\n\n# Two\n")
    }

    func testReplaceSwapsAnInclusiveRangeForOneBlock() async throws {
        let content = "# One\n\n# Two\n\n# Three\n"
        let output = try await run(
            ReplaceCommand.self,
            ["1", "2", "# New"],
            on: content
        )
        XCTAssertEqual(output, "# New\n\n# Three\n")
    }

    func testReplaceAcceptsMultiBlockReplacementContent() async throws {
        let output = try await run(
            ReplaceCommand.self,
            ["1", "# New\n\nAnd a paragraph."],
            on: twoHeadings
        )
        XCTAssertEqual(output, "# New\n\nAnd a paragraph.\n\n# Two\n")
    }

    /// A second argument that parses as an integer is read as an end index, so
    /// replacing a block with the literal text "2" needs the three-argument form.
    func testReplaceReadsANumericSecondArgumentAsAnEndIndex() async {
        await XCTAssertThrowsErrorMessage(
            "Expected: md replace <start> <end> \"content\" --file <file>"
        ) {
            _ = try await self.run(ReplaceCommand.self, ["1", "2"], on: self.twoHeadings)
        }
    }

    func testReplaceReadsANonNumericSecondArgumentAsContent() async throws {
        let output = try await run(
            ReplaceCommand.self,
            ["1", "2 apples"],
            on: twoHeadings
        )
        XCTAssertEqual(output, "2 apples\n\n# Two\n")
    }

    func testReplaceTheLastBlock() async throws {
        let output = try await run(
            ReplaceCommand.self,
            ["2", "# New"],
            on: twoHeadings
        )
        XCTAssertEqual(output, "# One\n\n# New\n")
    }

    func testReplaceInPlaceRewritesTheFile() async throws {
        let written = try await runInPlace(
            ReplaceCommand.self,
            ["1", "# New"],
            on: twoHeadings
        )
        XCTAssertEqual(written, "# New\n\n# Two\n")
    }

    // MARK: - replace: index guards

    func testReplaceRejectsAStartBelowOne() async {
        await XCTAssertThrowsErrorMessage("Start index must be >= 1, got 0") {
            _ = try await self.run(
                ReplaceCommand.self, ["0", "# New"], on: self.twoHeadings
            )
        }
    }

    func testReplaceRejectsAnEndBeforeTheStart() async {
        await XCTAssertThrowsErrorMessage("End index must be >= start, got 2...1") {
            _ = try await self.run(
                ReplaceCommand.self, ["2", "1", "# New"], on: self.twoHeadings
            )
        }
    }

    func testReplaceRejectsAnEndPastTheLastBlock() async {
        await XCTAssertThrowsErrorMessage("End index must be <= 2, got 3") {
            _ = try await self.run(
                ReplaceCommand.self, ["1", "3", "# New"], on: self.twoHeadings
            )
        }
    }

    func testReplaceRejectsInPlaceWithStandardInput() {
        XCTAssertThrowsError(
            try ReplaceCommand.parse(["--in-place", "--stdin", "1", "# New"])
        ) { error in
            XCTAssertEqual(
                ReplaceCommand.message(for: error),
                "Cannot use --in-place with --stdin"
            )
        }
    }

    // MARK: - insert-after

    func testInsertAfterPlacesContentBelowTheNamedBlock() async throws {
        let output = try await run(
            InsertAfterCommand.self,
            ["1", "New."],
            on: twoHeadings
        )
        XCTAssertEqual(output, "# One\n\nNew.\n\n# Two\n")
    }

    func testInsertAfterTheLastBlockAppendsToTheDocument() async throws {
        let output = try await run(
            InsertAfterCommand.self,
            ["2", "New."],
            on: twoHeadings
        )
        XCTAssertEqual(output, "# One\n\n# Two\n\nNew.\n")
    }

    func testInsertAfterAcceptsMultiBlockContent() async throws {
        let output = try await run(
            InsertAfterCommand.self,
            ["1", "## Sub\n\nText."],
            on: twoHeadings
        )
        XCTAssertEqual(output, "# One\n\n## Sub\n\nText.\n\n# Two\n")
    }

    func testInsertAfterInPlaceRewritesTheFile() async throws {
        let written = try await runInPlace(
            InsertAfterCommand.self,
            ["1", "New."],
            on: twoHeadings
        )
        XCTAssertEqual(written, "# One\n\nNew.\n\n# Two\n")
    }

    func testInsertAfterRejectsAnIndexBelowOne() async {
        await XCTAssertThrowsErrorMessage(
            "Block index must be in range 1...2, got 0"
        ) {
            _ = try await self.run(
                InsertAfterCommand.self, ["0", "New."], on: self.twoHeadings
            )
        }
    }

    func testInsertAfterRejectsAnIndexPastTheLastBlock() async {
        await XCTAssertThrowsErrorMessage(
            "Block index must be in range 1...2, got 3"
        ) {
            _ = try await self.run(
                InsertAfterCommand.self, ["3", "New."], on: self.twoHeadings
            )
        }
    }

    func testInsertAfterRejectsAnyIndexInAnEmptyDocument() async {
        await XCTAssertThrowsErrorMessage(
            "Block index must be in range 1...0, got 1"
        ) {
            _ = try await self.run(InsertAfterCommand.self, ["1", "New."], on: "")
        }
    }

    func testInsertAfterRejectsInPlaceWithStandardInput() {
        XCTAssertThrowsError(
            try InsertAfterCommand.parse(["--in-place", "--stdin", "1", "New."])
        ) { error in
            XCTAssertEqual(
                InsertAfterCommand.message(for: error),
                "Cannot use --in-place with --stdin"
            )
        }
    }

    // MARK: - insert-before

    func testInsertBeforePlacesContentAboveTheNamedBlock() async throws {
        let output = try await run(
            InsertBeforeCommand.self,
            ["2", "New."],
            on: twoHeadings
        )
        XCTAssertEqual(output, "# One\n\nNew.\n\n# Two\n")
    }

    func testInsertBeforeTheFirstBlockPrependsToTheDocument() async throws {
        let output = try await run(
            InsertBeforeCommand.self,
            ["1", "New."],
            on: twoHeadings
        )
        XCTAssertEqual(output, "New.\n\n# One\n\n# Two\n")
    }

    /// insert-before splices into the source rather than reformatting, so text
    /// it does not touch survives byte for byte — including frontmatter.
    func testInsertBeforeLeavesFrontmatterAndSpacingUntouched() async throws {
        let content = "---\ntitle: A\n---\n\n#    Loosely  spaced\n\n# Target\n"
        let output = try await run(
            InsertBeforeCommand.self,
            ["2", "New."],
            on: content
        )
        XCTAssertEqual(
            output,
            "---\ntitle: A\n---\n\n#    Loosely  spaced\n\nNew.\n\n# Target\n"
        )
    }

    func testInsertBeforeInPlaceRewritesTheFile() async throws {
        let written = try await runInPlace(
            InsertBeforeCommand.self,
            ["2", "New."],
            on: twoHeadings
        )
        XCTAssertEqual(written, "# One\n\nNew.\n\n# Two\n")
    }

    func testInsertBeforeRejectsAnIndexBelowOne() async {
        await XCTAssertThrowsErrorMessage(
            "Block index must be in range 1...2, got 0"
        ) {
            _ = try await self.run(
                InsertBeforeCommand.self, ["0", "New."], on: self.twoHeadings
            )
        }
    }

    func testInsertBeforeRejectsAnIndexPastTheLastBlock() async {
        await XCTAssertThrowsErrorMessage(
            "Block index must be in range 1...2, got 3"
        ) {
            _ = try await self.run(
                InsertBeforeCommand.self, ["3", "New."], on: self.twoHeadings
            )
        }
    }

    func testInsertBeforeRejectsInPlaceWithStandardInput() {
        XCTAssertThrowsError(
            try InsertBeforeCommand.parse(["--in-place", "--stdin", "1", "New."])
        ) { error in
            XCTAssertEqual(
                InsertBeforeCommand.message(for: error),
                "Cannot use --in-place with --stdin"
            )
        }
    }

    // MARK: - Block numbering must agree across commands

    /// `md blocks` counts the two body blocks of this document. The editing
    /// commands must number blocks the same way, or an index the user reads
    /// from `md blocks` points at a different block when they edit.
    private let frontmatterDocument = "---\ntitle: A\n---\n\n# Heading\n\nBody.\n"

    func testBlocksCommandCountsOnlyTheBodyBlocks() async throws {
        let path = try scratch.write(frontmatterDocument, to: "counted.md")
        let command = try BlocksCommand.parse(["--count", "--file", path])
        let output = try await StandardStream.capturingStandardOutput {
            try await command.run()
        }
        XCTAssertEqual(output, "2\n")
    }

    func testRemoveNumbersBlocksTheSameWayAsBlocksCommand() async {
        await XCTAssertThrowsErrorMessage("End index must be <= 2, got 3") {
            _ = try await self.run(
                RemoveCommand.self, ["3"], on: self.frontmatterDocument
            )
        }
    }

    func testReplaceNumbersBlocksTheSameWayAsBlocksCommand() async {
        await XCTAssertThrowsErrorMessage("End index must be <= 2, got 3") {
            _ = try await self.run(
                ReplaceCommand.self, ["3", "# New"], on: self.frontmatterDocument
            )
        }
    }

    func testInsertAfterNumbersBlocksTheSameWayAsBlocksCommand() async {
        await XCTAssertThrowsErrorMessage(
            "Block index must be in range 1...2, got 3"
        ) {
            _ = try await self.run(
                InsertAfterCommand.self, ["3", "New."], on: self.frontmatterDocument
            )
        }
    }

    func testInsertBeforeNumbersBlocksTheSameWayAsBlocksCommand() async {
        await XCTAssertThrowsErrorMessage(
            "Block index must be in range 1...2, got 3"
        ) {
            _ = try await self.run(
                InsertBeforeCommand.self, ["3", "New."], on: self.frontmatterDocument
            )
        }
    }

    // MARK: - Frontmatter must survive an edit

    func testRemoveKeepsFrontmatterOutOfTheReformattedBody() async throws {
        let output = try await run(
            RemoveCommand.self, ["1"], on: frontmatterDocument
        )
        XCTAssertEqual(output, "---\ntitle: A\n---\n\nBody.\n")
    }
}

/// Lets the helpers above drive any of the four editing commands through one
/// generic entry point. `AsyncParsableCommand.run()` cannot be called through
/// the protocol existential, so each command restates it here.
protocol AsyncParsableCommandStub: AsyncParsableCommand {
    func runCommand() async throws
}

extension RemoveCommand: AsyncParsableCommandStub {
    func runCommand() async throws { try await run() }
}

extension ReplaceCommand: AsyncParsableCommandStub {
    func runCommand() async throws { try await run() }
}

extension InsertAfterCommand: AsyncParsableCommandStub {
    func runCommand() async throws { try await run() }
}

extension InsertBeforeCommand: AsyncParsableCommandStub {
    func runCommand() async throws { try await run() }
}
