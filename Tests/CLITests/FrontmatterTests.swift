//
//  FrontmatterTests.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import XCTest
@testable import md

final class FrontmatterTests: XCTestCase {

    // MARK: - YAML Parsing

    func testParseYAMLFrontmatter() {
        let content = "---\ntitle: Hello\nauthor: John\n---\n# Heading\n"
        let fm = Frontmatter.parse(content)
        XCTAssertNotNil(fm)
        XCTAssertEqual(fm?.format, .yaml)
        XCTAssertEqual(fm?.data["title"] as? String, "Hello")
        XCTAssertEqual(fm?.data["author"] as? String, "John")
        XCTAssertEqual(fm?.body, "# Heading\n")
    }

    func testParseYAMLWithNestedData() {
        let content = "---\nauthor:\n  name: John\n  email: john@example.com\n---\nBody\n"
        let fm = Frontmatter.parse(content)
        XCTAssertNotNil(fm)
        let author = fm?.data["author"] as? [String: Any]
        XCTAssertEqual(author?["name"] as? String, "John")
        XCTAssertEqual(author?["email"] as? String, "john@example.com")
    }

    func testParseYAMLWithArray() {
        let content = "---\ntags:\n  - swift\n  - markdown\n---\nBody\n"
        let fm = Frontmatter.parse(content)
        XCTAssertNotNil(fm)
        let tags = fm?.data["tags"] as? [String]
        XCTAssertEqual(tags, ["swift", "markdown"])
    }

    func testParseYAMLWithInlineArray() {
        let content = "---\ntags: [swift, markdown]\n---\nBody\n"
        let fm = Frontmatter.parse(content)
        XCTAssertNotNil(fm)
        let tags = fm?.data["tags"] as? [String]
        XCTAssertEqual(tags, ["swift", "markdown"])
    }

    func testParseYAMLWithBooleans() {
        let content = "---\ndraft: true\npublished: false\n---\nBody\n"
        let fm = Frontmatter.parse(content)
        XCTAssertNotNil(fm)
        XCTAssertEqual(fm?.data["draft"] as? Bool, true)
        XCTAssertEqual(fm?.data["published"] as? Bool, false)
    }

    func testParseYAMLWithNumbers() {
        let content = "---\ncount: 42\nversion: 1.5\n---\nBody\n"
        let fm = Frontmatter.parse(content)
        XCTAssertNotNil(fm)
        XCTAssertEqual(fm?.data["count"] as? Int, 42)
        XCTAssertEqual(fm?.data["version"] as? Double, 1.5)
    }

    func testParseNoFrontmatter() {
        let content = "# Just a heading\n\nSome text.\n"
        let fm = Frontmatter.parse(content)
        XCTAssertNil(fm)
    }

    func testParseEmptyFrontmatter() {
        let content = "---\n---\nBody\n"
        let fm = Frontmatter.parse(content)
        XCTAssertNotNil(fm)
        XCTAssertTrue(fm?.data.isEmpty ?? false)
        XCTAssertEqual(fm?.body, "Body\n")
    }

    func testParseFrontmatterAtEndOfFile() {
        let content = "---\ntitle: Hello\n---"
        let fm = Frontmatter.parse(content)
        XCTAssertNotNil(fm)
        XCTAssertEqual(fm?.data["title"] as? String, "Hello")
        XCTAssertEqual(fm?.body, "")
    }

    // MARK: - Dot Syntax Get

    func testGetTopLevelKey() {
        let content = "---\ntitle: Hello\n---\nBody\n"
        let fm = Frontmatter.parse(content)!
        XCTAssertEqual(fm.get("title") as? String, "Hello")
    }

    func testGetNestedKey() {
        let content = "---\nauthor:\n  name: John\n  contact:\n    email: john@test.com\n---\nBody\n"
        let fm = Frontmatter.parse(content)!
        XCTAssertEqual(fm.get("author.name") as? String, "John")
        XCTAssertEqual(fm.get("author.contact.email") as? String, "john@test.com")
    }

    func testGetMissingKey() {
        let content = "---\ntitle: Hello\n---\nBody\n"
        let fm = Frontmatter.parse(content)!
        XCTAssertNil(fm.get("missing"))
        XCTAssertNil(fm.get("title.nested"))
    }

    // MARK: - Dot Syntax Set

    func testSetTopLevelKey() {
        let content = "---\ntitle: Hello\n---\nBody\n"
        var fm = Frontmatter.parse(content)!
        fm.set("title", value: "Updated")
        XCTAssertEqual(fm.get("title") as? String, "Updated")
    }

    func testSetNewTopLevelKey() {
        let content = "---\ntitle: Hello\n---\nBody\n"
        var fm = Frontmatter.parse(content)!
        fm.set("draft", value: true)
        XCTAssertEqual(fm.get("draft") as? Bool, true)
    }

    func testSetNestedKey() {
        let content = "---\ntitle: Hello\n---\nBody\n"
        var fm = Frontmatter.parse(content)!
        fm.set("author.name", value: "John")
        XCTAssertEqual(fm.get("author.name") as? String, "John")
    }

    func testSetDeeplyNestedKey() {
        let content = "---\ntitle: Hello\n---\nBody\n"
        var fm = Frontmatter.parse(content)!
        fm.set("a.b.c", value: "deep")
        XCTAssertEqual(fm.get("a.b.c") as? String, "deep")
    }

    func testSetOverwriteNestedKey() {
        let content = "---\nauthor:\n  name: Old\n  email: old@test.com\n---\nBody\n"
        var fm = Frontmatter.parse(content)!
        fm.set("author.name", value: "New")
        XCTAssertEqual(fm.get("author.name") as? String, "New")
        XCTAssertEqual(fm.get("author.email") as? String, "old@test.com")
    }

    // MARK: - Dot Syntax Remove

    func testRemoveTopLevelKey() {
        let content = "---\ntitle: Hello\nauthor: John\n---\nBody\n"
        var fm = Frontmatter.parse(content)!
        fm.removeKey("title")
        XCTAssertNil(fm.get("title"))
        XCTAssertEqual(fm.get("author") as? String, "John")
    }

    func testRemoveNestedKey() {
        let content = "---\nauthor:\n  name: John\n  email: john@test.com\n---\nBody\n"
        var fm = Frontmatter.parse(content)!
        fm.removeKey("author.email")
        XCTAssertEqual(fm.get("author.name") as? String, "John")
        XCTAssertNil(fm.get("author.email"))
    }

    func testRemoveMissingKey() {
        let content = "---\ntitle: Hello\n---\nBody\n"
        var fm = Frontmatter.parse(content)!
        fm.removeKey("missing")
        XCTAssertEqual(fm.get("title") as? String, "Hello")
    }

    // MARK: - YAML Serialization

    func testSerializeYAML() throws {
        let content = "---\ntitle: Hello\n---\nBody\n"
        let fm = Frontmatter.parse(content)!
        let serialized = try fm.serialize()
        XCTAssertTrue(serialized.hasPrefix("---\n"))
        XCTAssertTrue(serialized.contains("title: Hello"))
        XCTAssertTrue(serialized.contains("---\nBody\n"))
    }

    func testSerializeYAMLRoundTrip() throws {
        let content = "---\ntitle: Hello\n---\nBody\n"
        let fm = Frontmatter.parse(content)!
        let serialized = try fm.serialize()
        let fm2 = Frontmatter.parse(serialized)
        XCTAssertNotNil(fm2)
        XCTAssertEqual(fm2?.get("title") as? String, "Hello")
        XCTAssertEqual(fm2?.body, "Body\n")
    }

    func testSerializeAfterSet() throws {
        let content = "---\ntitle: Hello\n---\nBody\n"
        var fm = Frontmatter.parse(content)!
        fm.set("draft", value: true)
        let serialized = try fm.serialize()
        let fm2 = Frontmatter.parse(serialized)!
        XCTAssertEqual(fm2.get("title") as? String, "Hello")
        XCTAssertEqual(fm2.get("draft") as? Bool, true)
        XCTAssertEqual(fm2.body, "Body\n")
    }

    func testSerializeAfterRemove() throws {
        let content = "---\ntitle: Hello\ndraft: true\n---\nBody\n"
        var fm = Frontmatter.parse(content)!
        fm.removeKey("draft")
        let serialized = try fm.serialize()
        let fm2 = Frontmatter.parse(serialized)!
        XCTAssertEqual(fm2.get("title") as? String, "Hello")
        XCTAssertNil(fm2.get("draft"))
    }

    // MARK: - JSON Parsing

    func testParseJSONFrontmatter() {
        let content = ";;;\n{\"title\": \"Hello\", \"author\": \"John\"}\n;;;\n# Heading\n"
        let fm = Frontmatter.parse(content)
        XCTAssertNotNil(fm)
        XCTAssertEqual(fm?.format, .json)
        XCTAssertEqual(fm?.data["title"] as? String, "Hello")
        XCTAssertEqual(fm?.data["author"] as? String, "John")
        XCTAssertEqual(fm?.body, "# Heading\n")
    }

    func testParseJSONWithNestedData() {
        let content = ";;;\n{\"author\": {\"name\": \"John\", \"email\": \"john@test.com\"}}\n;;;\nBody\n"
        let fm = Frontmatter.parse(content)
        XCTAssertNotNil(fm)
        let author = fm?.data["author"] as? [String: Any]
        XCTAssertEqual(author?["name"] as? String, "John")
        XCTAssertEqual(author?["email"] as? String, "john@test.com")
    }

    func testParseJSONWithArray() {
        let content = ";;;\n{\"tags\": [\"swift\", \"markdown\"]}\n;;;\nBody\n"
        let fm = Frontmatter.parse(content)
        XCTAssertNotNil(fm)
        let tags = fm?.data["tags"] as? [String]
        XCTAssertEqual(tags, ["swift", "markdown"])
    }

    func testParseJSONMultiline() {
        let content = ";;;\n{\n  \"title\": \"Hello\",\n  \"draft\": true\n}\n;;;\nBody\n"
        let fm = Frontmatter.parse(content)
        XCTAssertNotNil(fm)
        XCTAssertEqual(fm?.data["title"] as? String, "Hello")
        XCTAssertEqual(fm?.data["draft"] as? Bool, true)
    }

    func testParseEmptyJSONFrontmatter() {
        let content = ";;;\n;;;\nBody\n"
        let fm = Frontmatter.parse(content)
        XCTAssertNotNil(fm)
        XCTAssertEqual(fm?.format, .json)
        XCTAssertTrue(fm?.data.isEmpty ?? false)
    }

    func testSerializeJSON() throws {
        let content = ";;;\n{\"title\": \"Hello\"}\n;;;\nBody\n"
        let fm = Frontmatter.parse(content)!
        let serialized = try fm.serialize()
        XCTAssertTrue(serialized.hasPrefix(";;;\n"))
        XCTAssertTrue(serialized.contains("\"title\""))
        XCTAssertTrue(serialized.contains("Hello"))
        XCTAssertTrue(serialized.hasSuffix(";;;\nBody\n"))
    }

    func testSerializeJSONRoundTrip() throws {
        let content = ";;;\n{\"title\": \"Hello\"}\n;;;\nBody\n"
        let fm = Frontmatter.parse(content)!
        let serialized = try fm.serialize()
        let fm2 = Frontmatter.parse(serialized)
        XCTAssertNotNil(fm2)
        XCTAssertEqual(fm2?.get("title") as? String, "Hello")
        XCTAssertEqual(fm2?.body, "Body\n")
    }

    func testJSONSetAndRoundTrip() throws {
        let content = ";;;\n{\"title\": \"Hello\"}\n;;;\nBody\n"
        var fm = Frontmatter.parse(content)!
        fm.set("draft", value: true)
        let serialized = try fm.serialize()
        let fm2 = Frontmatter.parse(serialized)!
        XCTAssertEqual(fm2.get("title") as? String, "Hello")
        XCTAssertEqual(fm2.get("draft") as? Bool, true)
    }

    func testJSONDotSyntaxGet() {
        let content = ";;;\n{\"author\": {\"name\": \"John\"}}\n;;;\nBody\n"
        let fm = Frontmatter.parse(content)!
        XCTAssertEqual(fm.get("author.name") as? String, "John")
    }

    func testJSONDotSyntaxSet() throws {
        let content = ";;;\n{\"title\": \"Hello\"}\n;;;\nBody\n"
        var fm = Frontmatter.parse(content)!
        fm.set("author.name", value: "John")
        let serialized = try fm.serialize()
        let fm2 = Frontmatter.parse(serialized)!
        XCTAssertEqual(fm2.get("author.name") as? String, "John")
    }

    // MARK: - YAML takes priority over JSON

    func testYAMLTakesPriorityOverJSON() {
        let content = "---\ntitle: Hello\n---\nBody\n"
        let fm = Frontmatter.parse(content)
        XCTAssertEqual(fm?.format, .yaml)
    }

    // MARK: - Value Parsing

    func testParseValueBool() {
        XCTAssertEqual(Frontmatter.parseValue("true") as? Bool, true)
        XCTAssertEqual(Frontmatter.parseValue("false") as? Bool, false)
    }

    func testParseValueInt() {
        XCTAssertEqual(Frontmatter.parseValue("42") as? Int, 42)
    }

    func testParseValueDouble() {
        XCTAssertEqual(Frontmatter.parseValue("3.14") as? Double, 3.14)
    }

    func testParseValueArray() {
        let result = Frontmatter.parseValue("[a, b, c]")
        XCTAssertEqual(result as? [String], ["a", "b", "c"])
    }

    func testParseValueString() {
        XCTAssertEqual(Frontmatter.parseValue("hello world") as? String, "hello world")
    }

    // MARK: - TOML Parsing

    func testParseTOMLFrontmatter() {
        let content = "+++\ntitle = \"Hello\"\nauthor = \"John\"\n+++\n# Heading\n"
        let fm = Frontmatter.parse(content)
        XCTAssertNotNil(fm)
        XCTAssertEqual(fm?.format, .toml)
        XCTAssertEqual(fm?.data["title"] as? String, "Hello")
        XCTAssertEqual(fm?.data["author"] as? String, "John")
        XCTAssertEqual(fm?.body, "# Heading\n")
    }

    func testParseTOMLWithNestedData() {
        let content = "+++\n[author]\nname = \"John\"\nemail = \"john@test.com\"\n+++\nBody\n"
        let fm = Frontmatter.parse(content)
        XCTAssertNotNil(fm)
        let author = fm?.data["author"] as? [String: Any]
        XCTAssertEqual(author?["name"] as? String, "John")
        XCTAssertEqual(author?["email"] as? String, "john@test.com")
    }

    func testParseTOMLWithArray() {
        let content = "+++\ntags = [\"swift\", \"markdown\"]\n+++\nBody\n"
        let fm = Frontmatter.parse(content)
        XCTAssertNotNil(fm)
        let tags = fm?.data["tags"] as? [Any]
        XCTAssertEqual(tags?.count, 2)
        XCTAssertEqual(tags?[0] as? String, "swift")
        XCTAssertEqual(tags?[1] as? String, "markdown")
    }

    func testParseTOMLWithBooleans() {
        let content = "+++\ndraft = true\npublished = false\n+++\nBody\n"
        let fm = Frontmatter.parse(content)
        XCTAssertNotNil(fm)
        XCTAssertEqual(fm?.data["draft"] as? Bool, true)
        XCTAssertEqual(fm?.data["published"] as? Bool, false)
    }

    func testParseTOMLWithNumbers() {
        let content = "+++\ncount = 42\nversion = 1.5\n+++\nBody\n"
        let fm = Frontmatter.parse(content)
        XCTAssertNotNil(fm)
        XCTAssertEqual(fm?.data["count"] as? Int, 42)
        XCTAssertEqual(fm?.data["version"] as? Double, 1.5)
    }

    func testParseEmptyTOMLFrontmatter() {
        let content = "+++\n+++\nBody\n"
        let fm = Frontmatter.parse(content)
        XCTAssertNotNil(fm)
        XCTAssertEqual(fm?.format, .toml)
        XCTAssertTrue(fm?.data.isEmpty ?? false)
    }

    func testParseTOMLAtEndOfFile() {
        let content = "+++\ntitle = \"Hello\"\n+++"
        let fm = Frontmatter.parse(content)
        XCTAssertNotNil(fm)
        XCTAssertEqual(fm?.data["title"] as? String, "Hello")
        XCTAssertEqual(fm?.body, "")
    }

    // MARK: - TOML Dot Syntax

    func testTOMLDotSyntaxGet() {
        let content = "+++\n[author]\nname = \"John\"\n+++\nBody\n"
        let fm = Frontmatter.parse(content)!
        XCTAssertEqual(fm.get("author.name") as? String, "John")
    }

    func testTOMLDotSyntaxSet() throws {
        let content = "+++\ntitle = \"Hello\"\n+++\nBody\n"
        var fm = Frontmatter.parse(content)!
        fm.set("author.name", value: "John")
        XCTAssertEqual(fm.get("author.name") as? String, "John")
    }

    // MARK: - TOML Serialization

    func testSerializeTOML() throws {
        let content = "+++\ntitle = \"Hello\"\n+++\nBody\n"
        let fm = Frontmatter.parse(content)!
        let serialized = try fm.serialize()
        XCTAssertTrue(serialized.hasPrefix("+++\n"))
        XCTAssertTrue(serialized.contains("title"))
        XCTAssertTrue(serialized.contains("Hello"))
        XCTAssertTrue(serialized.hasSuffix("+++\nBody\n"))
    }

    func testSerializeTOMLRoundTrip() throws {
        let content = "+++\ntitle = \"Hello\"\n+++\nBody\n"
        let fm = Frontmatter.parse(content)!
        let serialized = try fm.serialize()
        let fm2 = Frontmatter.parse(serialized)
        XCTAssertNotNil(fm2)
        XCTAssertEqual(fm2?.format, .toml)
        XCTAssertEqual(fm2?.get("title") as? String, "Hello")
        XCTAssertEqual(fm2?.body, "Body\n")
    }

    func testTOMLSetAndRoundTrip() throws {
        let content = "+++\ntitle = \"Hello\"\n+++\nBody\n"
        var fm = Frontmatter.parse(content)!
        fm.set("draft", value: true)
        let serialized = try fm.serialize()
        let fm2 = Frontmatter.parse(serialized)!
        XCTAssertEqual(fm2.get("title") as? String, "Hello")
        XCTAssertEqual(fm2.get("draft") as? Bool, true)
    }

    func testTOMLNestedRoundTrip() throws {
        let content = "+++\n[author]\nname = \"John\"\nemail = \"john@test.com\"\n+++\nBody\n"
        let fm = Frontmatter.parse(content)!
        let serialized = try fm.serialize()
        let fm2 = Frontmatter.parse(serialized)!
        XCTAssertEqual(fm2.get("author.name") as? String, "John")
        XCTAssertEqual(fm2.get("author.email") as? String, "john@test.com")
    }

    // MARK: - Format Conversion

    func testConvertYAMLToJSON() throws {
        let content = "---\ntitle: Hello\nauthor: John\n---\nBody\n"
        var fm = Frontmatter.parse(content)!
        XCTAssertEqual(fm.format, .yaml)
        fm.format = .json
        let serialized = try fm.serialize()
        XCTAssertTrue(serialized.hasPrefix(";;;\n"))
        XCTAssertTrue(serialized.hasSuffix(";;;\nBody\n"))
        let fm2 = Frontmatter.parse(serialized)!
        XCTAssertEqual(fm2.format, .json)
        XCTAssertEqual(fm2.get("title") as? String, "Hello")
        XCTAssertEqual(fm2.get("author") as? String, "John")
    }

    func testConvertYAMLToTOML() throws {
        let content = "---\ntitle: Hello\n---\nBody\n"
        var fm = Frontmatter.parse(content)!
        fm.format = .toml
        let serialized = try fm.serialize()
        XCTAssertTrue(serialized.hasPrefix("+++\n"))
        XCTAssertTrue(serialized.hasSuffix("+++\nBody\n"))
        let fm2 = Frontmatter.parse(serialized)!
        XCTAssertEqual(fm2.format, .toml)
        XCTAssertEqual(fm2.get("title") as? String, "Hello")
    }

    func testConvertTOMLToYAML() throws {
        let content = "+++\ntitle = \"Hello\"\n+++\nBody\n"
        var fm = Frontmatter.parse(content)!
        fm.format = .yaml
        let serialized = try fm.serialize()
        XCTAssertTrue(serialized.hasPrefix("---\n"))
        XCTAssertTrue(serialized.hasSuffix("---\nBody\n"))
        let fm2 = Frontmatter.parse(serialized)!
        XCTAssertEqual(fm2.format, .yaml)
        XCTAssertEqual(fm2.get("title") as? String, "Hello")
    }

    func testConvertJSONToYAML() throws {
        let content = ";;;\n{\"title\": \"Hello\"}\n;;;\nBody\n"
        var fm = Frontmatter.parse(content)!
        fm.format = .yaml
        let serialized = try fm.serialize()
        XCTAssertTrue(serialized.hasPrefix("---\n"))
        let fm2 = Frontmatter.parse(serialized)!
        XCTAssertEqual(fm2.format, .yaml)
        XCTAssertEqual(fm2.get("title") as? String, "Hello")
    }

    func testConvertJSONToTOML() throws {
        let content = ";;;\n{\"title\": \"Hello\"}\n;;;\nBody\n"
        var fm = Frontmatter.parse(content)!
        fm.format = .toml
        let serialized = try fm.serialize()
        XCTAssertTrue(serialized.hasPrefix("+++\n"))
        let fm2 = Frontmatter.parse(serialized)!
        XCTAssertEqual(fm2.format, .toml)
        XCTAssertEqual(fm2.get("title") as? String, "Hello")
    }

    func testConvertTOMLToJSON() throws {
        let content = "+++\ntitle = \"Hello\"\n+++\nBody\n"
        var fm = Frontmatter.parse(content)!
        fm.format = .json
        let serialized = try fm.serialize()
        XCTAssertTrue(serialized.hasPrefix(";;;\n"))
        let fm2 = Frontmatter.parse(serialized)!
        XCTAssertEqual(fm2.format, .json)
        XCTAssertEqual(fm2.get("title") as? String, "Hello")
    }

    func testConvertPreservesBody() throws {
        let content = "---\ntitle: Hello\n---\n# Heading\n\nParagraph text.\n"
        var fm = Frontmatter.parse(content)!
        fm.format = .json
        let serialized = try fm.serialize()
        let fm2 = Frontmatter.parse(serialized)!
        XCTAssertEqual(fm2.body, "# Heading\n\nParagraph text.\n")
    }

    func testConvertWithNestedData() throws {
        let content = "---\nauthor:\n  name: John\n  email: john@test.com\n---\nBody\n"
        var fm = Frontmatter.parse(content)!
        fm.format = .json
        let serialized = try fm.serialize()
        let fm2 = Frontmatter.parse(serialized)!
        XCTAssertEqual(fm2.get("author.name") as? String, "John")
        XCTAssertEqual(fm2.get("author.email") as? String, "john@test.com")
    }

    // MARK: - Format Command Integration

    func testFormatPreservesFrontmatter() throws {
        let content = "---\ntitle: Hello\n---\n# Heading\n\nParagraph.\n"
        let fm = Frontmatter.parse(content)!
        XCTAssertFalse(fm.data.isEmpty)
        XCTAssertEqual(fm.get("title") as? String, "Hello")
        XCTAssertEqual(fm.body, "# Heading\n\nParagraph.\n")
    }

    func testFormatStripsEmptyFrontmatter() {
        let content = "---\n---\n# Heading\n"
        let fm = Frontmatter.parse(content)!
        XCTAssertTrue(fm.data.isEmpty)
    }

    func testFormatPreservesTomlFrontmatter() throws {
        let content = "+++\ntitle = \"Hello\"\n+++\n# Heading\n"
        let fm = Frontmatter.parse(content)!
        XCTAssertFalse(fm.data.isEmpty)
        XCTAssertEqual(fm.get("title") as? String, "Hello")
    }

    func testFormatPreservesJsonFrontmatter() throws {
        let content = ";;;\n{\"title\": \"Hello\"}\n;;;\n# Heading\n"
        let fm = Frontmatter.parse(content)!
        XCTAssertFalse(fm.data.isEmpty)
        XCTAssertEqual(fm.get("title") as? String, "Hello")
    }

    // MARK: - Equatable Format

    func testFormatEquatable() {
        XCTAssertEqual(FrontmatterFormat.yaml, FrontmatterFormat.yaml)
        XCTAssertNotEqual(FrontmatterFormat.yaml, FrontmatterFormat.toml)
    }

    // MARK: - Fixture Loading

    private func loadFixture(_ name: String) throws -> String {
        guard let url = Bundle.module.url(forResource: name, withExtension: "md", subdirectory: "Fixtures") else {
            XCTFail("Missing fixture: \(name).md")
            throw CocoaError(.fileReadNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testFixtureYAMLSimpleLoads() throws {
        let content = try loadFixture("yaml-simple")
        let fm = Frontmatter.parse(content)
        XCTAssertEqual(fm?.format, .yaml)
        XCTAssertEqual(fm?.get("title") as? String, "Simple")
        XCTAssertEqual(fm?.get("draft") as? Bool, true)
        XCTAssertEqual(fm?.get("count") as? Int, 3)
    }

    func testFixtureYAMLWithDateConvertsToJSON() throws {
        let content = try loadFixture("yaml-with-date")
        var fm = try XCTUnwrap(Frontmatter.parse(content))
        XCTAssertEqual(fm.format, .yaml)
        fm.format = .json

        let serialized = try fm.serialize()
        XCTAssertTrue(serialized.hasPrefix(";;;\n"))

        let fm2 = try XCTUnwrap(Frontmatter.parse(serialized))
        XCTAssertEqual(fm2.format, .json)
        XCTAssertEqual(fm2.get("title") as? String, "Dated Post")
        XCTAssertEqual(fm2.get("author") as? String, "Jane")
        XCTAssertEqual(fm2.get("date") as? String, "2026-04-18T00:00:00Z")
    }

    func testFixtureYAMLWithDatetimeConvertsToJSON() throws {
        let content = try loadFixture("yaml-with-datetime")
        var fm = try XCTUnwrap(Frontmatter.parse(content))
        fm.format = .json

        let serialized = try fm.serialize()
        let fm2 = try XCTUnwrap(Frontmatter.parse(serialized))
        XCTAssertEqual(fm2.get("title") as? String, "Timestamped")
        XCTAssertEqual(fm2.get("published_at") as? String, "2026-04-18T12:34:56Z")
    }

    // TOMLKit pre-stringifies date/time/dateTime values via debugDescription
    // in tomlValueToAny, so by the time they reach serializeJSON they are
    // already Strings — this test covers the TOML pre-stringification path,
    // not the Date-object normalization path.
    func testFixtureTOMLWithDateConvertsToJSON() throws {
        let content = try loadFixture("toml-with-date")
        var fm = try XCTUnwrap(Frontmatter.parse(content))
        XCTAssertEqual(fm.format, .toml)
        fm.format = .json

        let serialized = try fm.serialize()
        let fm2 = try XCTUnwrap(Frontmatter.parse(serialized))
        XCTAssertEqual(fm2.format, .json)
        XCTAssertEqual(fm2.get("title") as? String, "Dated TOML")
        XCTAssertEqual(fm2.get("date") as? String, "2026-04-18")
        XCTAssertEqual(fm2.get("published_at") as? String, "2026-04-18T12:34:56Z")
    }

    func testFixtureYAMLNestedDatesConvertToJSON() throws {
        let content = try loadFixture("yaml-nested-dates")
        var fm = try XCTUnwrap(Frontmatter.parse(content))
        fm.format = .json

        let serialized = try fm.serialize()
        let fm2 = try XCTUnwrap(Frontmatter.parse(serialized))
        XCTAssertEqual(fm2.get("schedule.start") as? String, "2026-04-18T00:00:00Z")
        XCTAssertEqual(fm2.get("schedule.end") as? String, "2026-05-01T09:00:00Z")
        let milestones = try XCTUnwrap(fm2.get("milestones") as? [String])
        XCTAssertEqual(milestones, ["2026-04-20T00:00:00Z", "2026-04-27T00:00:00Z"])
    }

    func testFixtureJSONLoadsAndRoundTrips() throws {
        let content = try loadFixture("json-simple")
        var fm = try XCTUnwrap(Frontmatter.parse(content))
        XCTAssertEqual(fm.format, .json)
        XCTAssertEqual(fm.get("title") as? String, "JSON Doc")

        fm.format = .json
        let serialized = try fm.serialize()
        let fm2 = try XCTUnwrap(Frontmatter.parse(serialized))
        XCTAssertEqual(fm2.get("title") as? String, "JSON Doc")
        XCTAssertEqual(fm2.get("date") as? String, "2026-04-18")
    }
}
