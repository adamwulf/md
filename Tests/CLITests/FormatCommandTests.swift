//
//  FormatCommandTests.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import XCTest
@testable import md

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
}
