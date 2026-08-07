//
//  FormatCommandTests.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import XCTest
@testable import md
@testable import MarkdownKit

final class FormatCommandTests: XCTestCase {

    // MARK: - Helpers

    /// Run `md format` against in-memory content with the given target frontmatter format.
    private func runFormat(_ content: String, frontmatter: FrontmatterFormat? = nil) -> String {
        return FormatCommand.format(content: content, targetFrontmatter: frontmatter)
    }

    // MARK: - Failing test for the new --frontmatter flag

    func testFormatConvertsYAMLToJSONFrontmatter() throws {
        let input = """
            ---
            title: Hello
            ---
            #   Heading

            paragraph
            """

        let out = runFormat(input, frontmatter: .json)
        // JSON delimiter pair
        XCTAssertTrue(out.hasPrefix(";;;\n"), "expected output to start with ';;;\\n', got: \(out)")
        // Body normalized via cmark-gfm: "#   Heading" → "# Heading"
        XCTAssertTrue(out.contains("# Heading\n"))
        XCTAssertTrue(out.contains("paragraph"))
        // No YAML delimiter remains in output
        XCTAssertFalse(out.contains("---\ntitle"))

        // The portion between the two ;;; lines should be valid JSON parseable by JSONSerialization
        let pattern = ";;;\n"
        guard let firstRange = out.range(of: pattern),
              let secondRange = out.range(of: pattern, range: firstRange.upperBound..<out.endIndex) else {
            XCTFail("expected two ';;;' delimiters")
            return
        }
        let jsonPortion = String(out[firstRange.upperBound..<secondRange.lowerBound])
        let parsed = try JSONSerialization.jsonObject(with: Data(jsonPortion.utf8)) as? [String: Any]
        XCTAssertEqual(parsed?["title"] as? String, "Hello")
    }

    // MARK: - Edge cases

    /// No frontmatter in source AND --frontmatter X specified → ignore the flag.
    func testNoFrontmatterFlagIsIgnoredWhenSourceHasNoFrontmatter() {
        let input = "# Heading\n\nparagraph\n"
        let withFlag = runFormat(input, frontmatter: .json)
        let withoutFlag = runFormat(input, frontmatter: nil)
        XCTAssertEqual(withFlag, withoutFlag)
        XCTAssertFalse(withFlag.contains(";;;"))
        XCTAssertFalse(withFlag.contains("---"))
        XCTAssertFalse(withFlag.contains("+++"))
    }

    /// Empty frontmatter (`---\n---`) AND --frontmatter X specified → strip it as today.
    func testEmptyFrontmatterIsStrippedEvenWithFlag() {
        let input = "---\n---\n# Heading\n"
        let withFlag = runFormat(input, frontmatter: .json)
        let withoutFlag = runFormat(input, frontmatter: nil)
        XCTAssertEqual(withFlag, withoutFlag)
        XCTAssertFalse(withFlag.contains(";;;"))
        XCTAssertFalse(withFlag.contains("---"))
    }

    func testMalformedFrontmatterIsPreservedWithoutFormattingOrConversion() {
        let inputs = [
            "---\ntitle: [unclosed\n---\n#   Heading\n",
            "+++\ntitle = \n+++\n#   Heading\n",
            ";;;\n{not json}\n;;;\n#   Heading\n",
        ]

        for input in inputs {
            XCTAssertEqual(runFormat(input), input)
            XCTAssertEqual(runFormat(input, frontmatter: .json), input)
        }
    }

    func testNonMappingFrontmatterIsPreservedInsteadOfTreatedAsEmpty() {
        let inputs = [
            "---\n- one\n- two\n---\n#   Heading\n",
            ";;;\n[1, 2, 3]\n;;;\n#   Heading\n",
        ]

        for input in inputs {
            XCTAssertEqual(runFormat(input), input)
            XCTAssertEqual(runFormat(input, frontmatter: .yaml), input)
        }
    }

    /// Source format matches --frontmatter X → output should be byte-identical to running without --frontmatter.
    func testSameFormatProducesByteIdenticalOutput() {
        let input = """
            ---
            title: Hello
            ---
            #   Heading

            paragraph
            """
        let withFlag = runFormat(input, frontmatter: .yaml)
        let withoutFlag = runFormat(input, frontmatter: nil)
        XCTAssertEqual(withFlag, withoutFlag)
    }

    /// --frontmatter not specified → today's behavior, unchanged.
    func testFlagAbsentPreservesFrontmatterVerbatim() {
        let input = """
            +++
            title = "Hello"
            +++
            #   Heading
            """
        let out = runFormat(input, frontmatter: nil)
        XCTAssertTrue(out.hasPrefix("+++\n"))
        XCTAssertTrue(out.contains("title = \"Hello\""))
        XCTAssertTrue(out.contains("# Heading\n"))
    }

    // MARK: - Happy paths

    func testYAMLToTOML() {
        let input = """
            ---
            title: Hello
            ---
            #   Body
            """
        let out = runFormat(input, frontmatter: .toml)
        XCTAssertTrue(out.hasPrefix("+++\n"))
        XCTAssertTrue(out.contains("title = 'Hello'") || out.contains("title = \"Hello\""))
        XCTAssertTrue(out.contains("# Body\n"))
    }

    func testYAMLToJSON() {
        let input = """
            ---
            title: Hello
            ---
            #   Body
            """
        let out = runFormat(input, frontmatter: .json)
        XCTAssertTrue(out.hasPrefix(";;;\n"))
        XCTAssertTrue(out.contains("\"title\""))
        XCTAssertTrue(out.contains("\"Hello\""))
        XCTAssertTrue(out.contains("# Body\n"))
    }

    func testTOMLToYAML() {
        let input = """
            +++
            title = "Hello"
            +++
            #   Body
            """
        let out = runFormat(input, frontmatter: .yaml)
        XCTAssertTrue(out.hasPrefix("---\n"))
        XCTAssertTrue(out.contains("title: Hello"))
        XCTAssertTrue(out.contains("# Body\n"))
        XCTAssertFalse(out.contains("+++"))
    }

    func testJSONToYAML() {
        let input = """
            ;;;
            {"title": "Hello"}
            ;;;
            #   Body
            """
        let out = runFormat(input, frontmatter: .yaml)
        XCTAssertTrue(out.hasPrefix("---\n"))
        XCTAssertTrue(out.contains("title: Hello"))
        XCTAssertTrue(out.contains("# Body\n"))
        XCTAssertFalse(out.contains(";;;"))
    }

    /// Regression test: JSONSerialization returns numeric values as `NSNumber`,
    /// which bridges to `Bool` first — so `as? Bool` matches any non-zero number.
    /// Without explicit unbridging, integers like `1` were silently turned into
    /// `true` when converted to YAML or TOML. This ensures int / bool / double
    /// preserve their types across JSON → YAML and JSON → TOML.
    func testJSONSourceNumericTypesSurviveConversion() {
        let input = """
            ;;;
            {"version": 1, "active": true, "ratio": 1.5, "title": "Doc"}
            ;;;
            #   Body
            """

        let yaml = runFormat(input, frontmatter: .yaml)
        XCTAssertTrue(yaml.contains("version: 1"), "expected 'version: 1' in YAML output, got: \(yaml)")
        XCTAssertFalse(yaml.contains("version: true"))
        XCTAssertTrue(yaml.contains("active: true"))
        XCTAssertTrue(yaml.contains("title: Doc"))

        let toml = runFormat(input, frontmatter: .toml)
        XCTAssertTrue(toml.contains("version = 1"), "expected 'version = 1' in TOML output, got: \(toml)")
        XCTAssertFalse(toml.contains("version = true"))
        XCTAssertTrue(toml.contains("active = true"))
        XCTAssertTrue(toml.contains("ratio = 1.5"))
    }

    // MARK: - Body normalization regardless of conversion

    func testBodyIsNormalizedInAllPaths() {
        let inputs: [(String, FrontmatterFormat?)] = [
            ("---\ntitle: A\n---\n#   Hi", nil),
            ("---\ntitle: A\n---\n#   Hi", .yaml),
            ("---\ntitle: A\n---\n#   Hi", .json),
            ("---\ntitle: A\n---\n#   Hi", .toml),
            ("#   Hi", nil),
            ("#   Hi", .json),
        ]
        for (input, fm) in inputs {
            let out = runFormat(input, frontmatter: fm)
            XCTAssertTrue(out.contains("# Hi"), "body not normalized for input=\(input) fm=\(String(describing: fm))")
            XCTAssertFalse(out.contains("#   Hi"), "body still has triple space for input=\(input) fm=\(String(describing: fm))")
        }
    }

    // MARK: - Soft line breaks

    func testFormatKeepsSoftLineBreaksInParagraph() {
        let out = runFormat("line1\nline2\nline3\n")
        XCTAssertEqual(out, "line1\nline2\nline3\n")
    }

    func testFormatOfMultilineParagraphKeepsTheBlockCount() {
        // Every command that writes a file (`md format`, `md replace -i`,
        // `md insert-after -i`) sends each block through BlockFormatter. If the
        // number of blocks moves, block indices move with it and a later
        // `md replace N` hits the wrong block.
        let source = "line1\nline2\nline3\n\npara2\n"
        let parser = MarkdownParser()
        XCTAssertEqual(parser.parse(runFormat(source)).count, parser.parse(source).count)
    }

    /// REGRESSION cover for the soft-break change.
    ///
    /// The first form of that change let a setext heading written on two lines hold a
    /// newline in its text, but BlockFormatter writes a heading as one ATX line. Thus
    /// `md format` turned one heading into a heading plus a paragraph, the block count
    /// moved from 2 to 3, and a second `md format` gave a different result again.
    ///
    /// `MarkdownParser` now holds heading text on one line. See
    /// `MarkdownParserTests.testParseSetextHeadingKeepsTextOnOneLine`.
    func testFormatKeepsMultilineSetextHeadingAsOneBlock() {
        let source = "First part\nSecond part\n===\n\nnext para\n"
        let parser = MarkdownParser()

        let once = runFormat(source)
        XCTAssertEqual(
            parser.parse(once).count,
            parser.parse(source).count,
            "md format changed the number of blocks: \(once.debugDescription)"
        )
        XCTAssertEqual(once, runFormat(once), "md format is not idempotent")

        let formattedBlocks = parser.parse(once)
        if let first = formattedBlocks.first, case .heading(_, let text, _, _, _) = first {
            XCTAssertEqual(text, "First part Second part")
        } else {
            XCTFail("Expected the first block to stay a heading, got: \(once.debugDescription)")
        }
    }

    /// A soft break keeps its newline, thus the second line of a paragraph starts at
    /// column 0 of the written file. A marker that the author escaped there would
    /// become live markdown, and one paragraph would divide into two blocks.
    ///
    /// The escape work in `MarkdownEscaper` answers this: the backslash goes back on.
    /// A character reference (`&#35;`) is inert text in the source in the same way,
    /// and `getNodeText` loses it in the same way, thus it gets the same backslash.
    func testFormatKeepsEscapedMarkdownOnContinuationLines() {
        let parser = MarkdownParser()
        let sources = [
            "foo\n\\# bar\n",
            "foo\n\\- bar\n",
            "foo\n\\> bar\n",
            "foo\n\\`\\`\\`js\n",
            // A character reference is inert text in the source, the same as a
            // backslash escape, and `getNodeText` loses it in the same way.
            "foo\n&#35; bar\n",
            "foo\n&gt; bar\n",
            "foo\n&#96;&#96;&#96;js\n",
        ]
        for source in sources {
            let once = runFormat(source)
            XCTAssertEqual(
                parser.parse(once).count,
                parser.parse(source).count,
                "md format changed the number of blocks for \(source.debugDescription): \(once.debugDescription)"
            )
        }
    }

    /// The same class of loss, but here the number of blocks does not move.
    ///
    /// `&#45;&#45;&#45;` is inert text in the source, thus the paragraph keeps it,
    /// but the block text holds `---`. Written at column 0 below its paragraph line,
    /// that would become a setext underline, and a second `md format` would make the
    /// paragraph into a heading and lose the text of the second line. `MarkdownEscaper`
    /// puts a backslash on it, thus the paragraph stays a paragraph.
    func testFormatKeepsEscapedSetextUnderlineOnContinuationLine() {
        let parser = MarkdownParser()
        let source = "foo\n&#45;&#45;&#45;\n"
        let once = runFormat(source)
        XCTAssertEqual(runFormat(once), once, "md format is not idempotent: \(once.debugDescription)")

        let blocks = parser.parse(once)
        XCTAssertEqual(blocks.count, 1, "expected one block, got: \(once.debugDescription)")
        guard case .paragraph = blocks[0] else {
            XCTFail("Expected the block to stay a paragraph, got: \(once.debugDescription)")
            return
        }
    }

    // MARK: - Link reference definitions (defects 7 and 27)

    /// Defect 7: a definition that no link uses is still text the author
    /// wrote, and the URL appears nowhere else in the file. `format` writes
    /// it back instead of deleting it.
    func testFormatKeepsAnUnusedLinkReferenceDefinition() {
        let input = "Just a paragraph.\n\n[unused]: https://example.org\n"
        XCTAssertEqual(runFormat(input), input)
    }

    /// Defect 27: a used definition keeps the author's reference style. The
    /// link stays `[ref]`, not the resolved `[ref](url)`, and the definition
    /// line stays below it, so the URL appears once.
    func testFormatKeepsAUsedLinkReferenceDefinitionAndItsLink() {
        let input = "paragraph [ref] here\n\n[ref]: url\n"
        XCTAssertEqual(runFormat(input), input)
    }

    /// Defect 7 in a list: a definition that was an item's only content goes
    /// back inside its bullet, not after the list.
    func testFormatKeepsADefinitionThatIsAnItemsOnlyContent() {
        let input = "# Title\n\n- [ref]: /url\n"
        XCTAssertEqual(runFormat(input), input)
    }

    /// Defect 7 in a list: a definition below an item's text goes back at the
    /// item's content indent, where the author put it.
    func testFormatKeepsADefinitionBelowItemText() {
        let input = "- Some text\n\n  [ref]: /url\n"
        XCTAssertEqual(runFormat(input), input)
    }

    /// A titled definition and a full `[text][label]` reference survive a
    /// round trip unchanged, and a second pass changes nothing.
    func testFormatKeepsAFullReferenceAndATitledDefinition() {
        let input = "See [the docs][ref] here.\n\n[ref]: /url \"A title\"\n"
        let once = runFormat(input)
        XCTAssertEqual(once, input)
        XCTAssertEqual(runFormat(once), once)
    }

    /// A reference-style link can wrap an inline image, making a clickable
    /// badge. Restoring the outer link replaces the link node and its whole
    /// subtree, so the inner image must already be decided by then.
    func testFormatKeepsAReferenceLinkWrappingAnInlineImage() {
        let input = "[![alt](i.png)][link]\n\n[link]: /url\n"
        XCTAssertEqual(runFormat(input), input)
    }

    /// The same badge with the image itself in reference style: both labels
    /// resolve, and both authored spellings survive.
    func testFormatKeepsAReferenceLinkWrappingAReferenceImage() {
        let input = "[![alt][img]][link]\n\n[img]: /i.png\n[link]: /url\n"
        XCTAssertEqual(runFormat(input), input)
    }
}
