//
//  FrontmatterConversionTests.swift
//  md
//
//  Covers the parts of Frontmatter the round-trip tests do not reach: what
//  happens to malformed frontmatter, to key paths that do not resolve, and to
//  values the target format cannot represent directly.
//

import XCTest
import TOMLKit
@testable import md

final class FrontmatterConversionTests: XCTestCase {

    // MARK: - Delimiters that do not open frontmatter

    func testAClosingDelimiterOnItsOwnIsNotFrontmatter() {
        XCTAssertNil(Frontmatter.parse("title: Hello\n---\nBody\n"))
    }

    func testAnOpeningDelimiterWithoutACloserIsNotFrontmatter() {
        XCTAssertNil(Frontmatter.parse("---\ntitle: Hello\nBody\n"))
    }

    func testADelimiterAfterTheFirstLineIsNotFrontmatter() {
        XCTAssertNil(Frontmatter.parse("\n---\ntitle: Hello\n---\nBody\n"))
    }

    func testADelimiterWithTrailingSpacesStillOpensFrontmatter() {
        let frontmatter = Frontmatter.parse("---  \ntitle: Hello\n---  \nBody\n")
        XCTAssertEqual(frontmatter?.get("title") as? String, "Hello")
    }

    /// The delimiter comparison trims whitespace from both ends of the line, so
    /// leading indentation does not stop a line from opening frontmatter. This
    /// is more lenient than Jekyll or Hugo, which both require column zero.
    func testAnIndentedDelimiterStillOpensFrontmatter() {
        let frontmatter = Frontmatter.parse("  ---\ntitle: Hello\n---\nBody\n")
        XCTAssertEqual(frontmatter?.get("title") as? String, "Hello")
    }

    /// Four spaces would make the line an indented code block to cmark, yet the
    /// frontmatter scanner still treats it as a delimiter.
    func testADelimiterIndentedIntoCodeBlockTerritoryStillOpensFrontmatter() {
        let frontmatter = Frontmatter.parse("    ---\ntitle: Hello\n---\nBody\n")
        XCTAssertEqual(frontmatter?.get("title") as? String, "Hello")
    }

    func testAFourDashDelimiterDoesNotOpenFrontmatter() {
        XCTAssertNil(Frontmatter.parse("----\ntitle: Hello\n----\nBody\n"))
    }

    func testAnEmptyDocumentHasNoFrontmatter() {
        XCTAssertNil(Frontmatter.parse(""))
    }

    func testADocumentOfOneDelimiterLineHasNoFrontmatter() {
        XCTAssertNil(Frontmatter.parse("---"))
    }

    func testFormatIsChosenByTheDelimiterThatMatchesFirst() {
        XCTAssertEqual(Frontmatter.parse("---\na: 1\n---\n")?.format, .yaml)
        XCTAssertEqual(Frontmatter.parse("+++\na = 1\n+++\n")?.format, .toml)
        XCTAssertEqual(Frontmatter.parse(";;;\n{\"a\": 1}\n;;;\n")?.format, .json)
    }

    // MARK: - Carriage returns

    func testCarriageReturnLineFeedDelimitersAreRecognized() {
        let frontmatter = Frontmatter.parse("---\r\ntitle: Hello\r\n---\r\nBody\r\n")
        XCTAssertEqual(frontmatter?.get("title") as? String, "Hello")
        XCTAssertEqual(frontmatter?.body, "Body\r\n")
    }

    func testLoneCarriageReturnDelimitersAreRecognized() {
        let frontmatter = Frontmatter.parse("---\rtitle: Hello\r---\rBody\r")
        XCTAssertEqual(frontmatter?.get("title") as? String, "Hello")
        XCTAssertEqual(frontmatter?.body, "Body\r")
    }

    // MARK: - Malformed payloads remain distinct from valid empty mappings

    func testAbsentValidEmptyAndMalformedAreThreeDistinctResults() {
        guard case .absent = Frontmatter.parseResult("# Body\n") else {
            return XCTFail("Expected absent frontmatter")
        }
        guard case .valid(let empty) = Frontmatter.parseResult("---\n---\nBody\n") else {
            return XCTFail("Expected valid empty frontmatter")
        }
        XCTAssertTrue(empty.data.isEmpty)
        guard case .malformed = Frontmatter.parseResult(
            "---\ntitle: [unclosed\n---\nBody\n"
        ) else {
            return XCTFail("Expected malformed frontmatter")
        }
    }

    func testMalformedYAMLReturnsASyntaxErrorInsteadOfEmptyData() {
        let content = "---\n\tbad:\n  - [unclosed\n---\nBody\n"
        guard case .malformed(let error) = Frontmatter.parseResult(content) else {
            return XCTFail("Expected malformed frontmatter")
        }
        XCTAssertEqual(error.format, .yaml)
        XCTAssertEqual(error.kind, .invalidSyntax)
        XCTAssertEqual(error.body, "Body\n")
        XCTAssertNil(Frontmatter.parse(content))
    }

    func testAYAMLScalarReturnsANonMappingError() {
        let content = "---\njust a string\n---\nBody\n"
        guard case .malformed(let error) = Frontmatter.parseResult(content) else {
            return XCTFail("Expected malformed frontmatter")
        }
        XCTAssertEqual(error.format, .yaml)
        XCTAssertEqual(error.kind, .nonMapping)
        XCTAssertNil(Frontmatter.parse(content))
    }

    func testAYAMLSequenceAtTheTopLevelReturnsANonMappingError() {
        let content = "---\n- one\n- two\n---\nBody\n"
        guard case .malformed(let error) = Frontmatter.parseResult(content) else {
            return XCTFail("Expected malformed frontmatter")
        }
        XCTAssertEqual(error.kind, .nonMapping)
        XCTAssertNil(Frontmatter.parse(content))
    }

    func testMalformedJSONReturnsASyntaxErrorInsteadOfEmptyData() {
        let content = ";;;\n{not json}\n;;;\nBody\n"
        guard case .malformed(let error) = Frontmatter.parseResult(content) else {
            return XCTFail("Expected malformed frontmatter")
        }
        XCTAssertEqual(error.format, .json)
        XCTAssertEqual(error.kind, .invalidSyntax)
        XCTAssertNil(Frontmatter.parse(content))
    }

    func testAJSONArrayAtTheTopLevelReturnsANonMappingError() {
        let content = ";;;\n[1, 2, 3]\n;;;\nBody\n"
        guard case .malformed(let error) = Frontmatter.parseResult(content) else {
            return XCTFail("Expected malformed frontmatter")
        }
        XCTAssertEqual(error.format, .json)
        XCTAssertEqual(error.kind, .nonMapping)
        XCTAssertNil(Frontmatter.parse(content))
    }

    func testMalformedTOMLReturnsASyntaxErrorInsteadOfEmptyData() {
        let content = "+++\ntitle = \n+++\nBody\n"
        guard case .malformed(let error) = Frontmatter.parseResult(content) else {
            return XCTFail("Expected malformed frontmatter")
        }
        XCTAssertEqual(error.format, .toml)
        XCTAssertEqual(error.kind, .invalidSyntax)
        XCTAssertNil(Frontmatter.parse(content))
    }

    // MARK: - Body extraction

    func testTheBodyStartsAfterTheClosingDelimiterLine() {
        let frontmatter = Frontmatter.parse("---\na: 1\n---\n\n# Heading\n")
        XCTAssertEqual(frontmatter?.body, "\n# Heading\n")
    }

    func testRawContentExcludesBothDelimiterLines() {
        let frontmatter = Frontmatter.parse("---\na: 1\nb: 2\n---\nBody\n")
        XCTAssertEqual(frontmatter?.rawContent, "a: 1\nb: 2")
    }

    func testRawContentOfEmptyFrontmatterIsEmpty() {
        let frontmatter = Frontmatter.parse("---\n---\nBody\n")
        XCTAssertEqual(frontmatter?.rawContent, "")
    }

    func testOriginalContentIsTheWholeDocument() {
        let content = "---\na: 1\n---\nBody\n"
        XCTAssertEqual(Frontmatter.parse(content)?.originalContent, content)
    }

    // MARK: - Key paths

    func testAnEmptyKeyPathReturnsTheWholeDataDictionary() {
        let frontmatter = Frontmatter.parse("---\na: 1\n---\nBody\n")!
        let value = frontmatter.get("") as? [String: Any]
        XCTAssertEqual(value?["a"] as? Int, 1)
    }

    func testDescendingThroughAScalarReturnsNil() {
        let frontmatter = Frontmatter.parse("---\na: 1\n---\nBody\n")!
        XCTAssertNil(frontmatter.get("a.b"))
    }

    func testDescendingThroughAnArrayReturnsNil() {
        let frontmatter = Frontmatter.parse("---\na:\n  - one\n---\nBody\n")!
        XCTAssertNil(frontmatter.get("a.0"))
    }

    func testSettingAnEmptyKeyPathLeavesTheDataUnchanged() {
        var frontmatter = Frontmatter.parse("---\na: 1\n---\nBody\n")!
        frontmatter.set("", value: "ignored")
        XCTAssertEqual(frontmatter.data.count, 1)
        XCTAssertEqual(frontmatter.get("a") as? Int, 1)
    }

    func testRemovingAnEmptyKeyPathLeavesTheDataUnchanged() {
        var frontmatter = Frontmatter.parse("---\na: 1\n---\nBody\n")!
        frontmatter.removeKey("")
        XCTAssertEqual(frontmatter.get("a") as? Int, 1)
    }

    func testSettingThroughAScalarReplacesItWithADictionary() {
        var frontmatter = Frontmatter.parse("---\na: 1\n---\nBody\n")!
        frontmatter.set("a.b", value: "deep")
        XCTAssertEqual(frontmatter.get("a.b") as? String, "deep")
        XCTAssertNil(frontmatter.get("a") as? Int)
    }

    func testRemovingThroughAScalarLeavesItAlone() {
        var frontmatter = Frontmatter.parse("---\na: 1\n---\nBody\n")!
        frontmatter.removeKey("a.b")
        XCTAssertEqual(frontmatter.get("a") as? Int, 1)
    }

    func testRemovingANestedKeyKeepsTheEmptyParent() {
        var frontmatter = Frontmatter.parse("---\na:\n  b: 1\n---\nBody\n")!
        frontmatter.removeKey("a.b")
        let parent = frontmatter.get("a") as? [String: Any]
        XCTAssertEqual(parent?.count, 0)
    }

    // MARK: - Serializing empty data

    func testSerializingEmptyYAMLDataProducesAnEmptyString() throws {
        let frontmatter = Frontmatter.parse("---\n---\nBody\n")!
        XCTAssertEqual(try frontmatter.serializeData(), "")
    }

    func testSerializingEmptyTOMLDataProducesAnEmptyString() throws {
        let frontmatter = Frontmatter.parse("+++\n+++\nBody\n")!
        XCTAssertEqual(try frontmatter.serializeData(), "")
    }

    func testSerializingEmptyJSONDataProducesAnEmptyString() throws {
        let frontmatter = Frontmatter.parse(";;;\n;;;\nBody\n")!
        XCTAssertEqual(try frontmatter.serializeData(), "")
    }

    func testSerializingEmptyFrontmatterStillEmitsBothDelimiters() throws {
        let frontmatter = Frontmatter.parse("---\n---\nBody\n")!
        XCTAssertEqual(try frontmatter.serialize(), "---\n---\nBody\n")
    }

    // MARK: - unbridgeNSNumber

    func testUnbridgeTurnsABooleanNSNumberIntoABool() {
        XCTAssertEqual(Frontmatter.unbridgeNSNumber(NSNumber(value: true)) as? Bool, true)
    }

    func testUnbridgeTurnsAnIntegerNSNumberIntoAnInt() {
        let value = Frontmatter.unbridgeNSNumber(NSNumber(value: 1))
        XCTAssertEqual(value as? Int, 1)
        XCTAssertNil(value as? Bool)
    }

    func testUnbridgeTurnsADoubleNSNumberIntoADouble() {
        XCTAssertEqual(
            Frontmatter.unbridgeNSNumber(NSNumber(value: 1.5)) as? Double,
            1.5
        )
    }

    func testUnbridgeTurnsAFloatNSNumberIntoADouble() {
        XCTAssertEqual(
            Frontmatter.unbridgeNSNumber(NSNumber(value: Float(0.5))) as? Double,
            0.5
        )
    }

    func testUnbridgeDescendsIntoDictionariesAndArrays() {
        let input: [String: Any] = [
            "nested": ["count": NSNumber(value: 2)],
            "list": [NSNumber(value: 3), NSNumber(value: false)]
        ]
        let result = Frontmatter.unbridgeNSNumber(input) as? [String: Any]
        let nested = result?["nested"] as? [String: Any]
        XCTAssertEqual(nested?["count"] as? Int, 2)
        let list = result?["list"] as? [Any]
        XCTAssertEqual(list?[0] as? Int, 3)
        XCTAssertEqual(list?[1] as? Bool, false)
    }

    func testUnbridgeLeavesNonNumbersAlone() {
        XCTAssertEqual(Frontmatter.unbridgeNSNumber("text") as? String, "text")
        XCTAssertTrue(Frontmatter.unbridgeNSNumber(NSNull()) is NSNull)
    }

    // MARK: - normalizeForJSON

    func testNormalizeForJSONTurnsDatesIntoInternetDateTimeStrings() {
        let date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(
            Frontmatter.normalizeForJSON(date) as? String,
            "1970-01-01T00:00:00Z"
        )
    }

    func testNormalizeForJSONPreservesNull() {
        XCTAssertTrue(Frontmatter.normalizeForJSON(NSNull()) is NSNull)
    }

    func testNormalizeForJSONPreservesScalarTypes() {
        XCTAssertEqual(Frontmatter.normalizeForJSON(true) as? Bool, true)
        XCTAssertEqual(Frontmatter.normalizeForJSON(7) as? Int, 7)
        XCTAssertEqual(Frontmatter.normalizeForJSON(1.25) as? Double, 1.25)
        XCTAssertEqual(Frontmatter.normalizeForJSON("s") as? String, "s")
    }

    func testNormalizeForJSONDescribesUnsupportedValues() {
        XCTAssertEqual(
            Frontmatter.normalizeForJSON(URL(fileURLWithPath: "/tmp/x")) as? String,
            "file:///tmp/x"
        )
    }

    func testNormalizeForJSONDescendsIntoDictionariesAndArrays() {
        let input: [String: Any] = ["dates": [Date(timeIntervalSince1970: 0)]]
        let result = Frontmatter.normalizeForJSON(input) as? [String: Any]
        XCTAssertEqual(result?["dates"] as? [String], ["1970-01-01T00:00:00Z"])
    }

    // MARK: - normalizeForYAML

    func testNormalizeForYAMLPreservesNull() {
        XCTAssertTrue(Frontmatter.normalizeForYAML(NSNull()) is NSNull)
    }

    func testNormalizeForYAMLPreservesScalarTypes() {
        XCTAssertEqual(Frontmatter.normalizeForYAML(true) as? Bool, true)
        XCTAssertEqual(Frontmatter.normalizeForYAML(7) as? Int, 7)
        XCTAssertEqual(Frontmatter.normalizeForYAML(1.25) as? Double, 1.25)
        XCTAssertEqual(Frontmatter.normalizeForYAML("s") as? String, "s")
    }

    func testNormalizeForYAMLDescribesUnsupportedValues() {
        XCTAssertEqual(
            Frontmatter.normalizeForYAML(URL(fileURLWithPath: "/tmp/x")) as? String,
            "file:///tmp/x"
        )
    }

    func testNormalizeForYAMLDescendsIntoDictionariesAndArrays() {
        let input: [String: Any] = ["list": [1, "two", true]]
        let result = Frontmatter.normalizeForYAML(input) as? [String: Any]
        let list = result?["list"] as? [Any]
        XCTAssertEqual(list?.count, 3)
        XCTAssertEqual(list?[0] as? Int, 1)
        XCTAssertEqual(list?[1] as? String, "two")
        XCTAssertEqual(list?[2] as? Bool, true)
    }

    // MARK: - TOML conversion

    func testTOMLValuesConvertToTheirSwiftCounterparts() {
        let table = try! TOMLTable(
            string: "s = \"x\"\ni = 3\nd = 1.5\nb = true\n"
        )
        let dict = Frontmatter.tomlTableToDict(table)
        XCTAssertEqual(dict["s"] as? String, "x")
        XCTAssertEqual(dict["i"] as? Int, 3)
        XCTAssertEqual(dict["d"] as? Double, 1.5)
        XCTAssertEqual(dict["b"] as? Bool, true)
    }

    func testTOMLNestedTablesBecomeNestedDictionaries() {
        let table = try! TOMLTable(string: "[outer]\ninner = 1\n")
        let dict = Frontmatter.tomlTableToDict(table)
        let outer = dict["outer"] as? [String: Any]
        XCTAssertEqual(outer?["inner"] as? Int, 1)
    }

    func testTOMLArraysBecomeSwiftArrays() {
        let table = try! TOMLTable(string: "a = [1, 2, 3]\n")
        let dict = Frontmatter.tomlTableToDict(table)
        XCTAssertEqual(dict["a"] as? [Int], [1, 2, 3])
    }

    func testTOMLArraysOfTablesBecomeArraysOfDictionaries() {
        let table = try! TOMLTable(string: "a = [{x = 1}, {x = 2}]\n")
        let dict = Frontmatter.tomlTableToDict(table)
        let array = dict["a"] as? [Any]
        XCTAssertEqual((array?[0] as? [String: Any])?["x"] as? Int, 1)
        XCTAssertEqual((array?[1] as? [String: Any])?["x"] as? Int, 2)
    }

    func testTOMLDateTimeValuesBecomeStrings() {
        let table = try! TOMLTable(
            string: "d = 2026-04-18\nt = 12:34:56\ndt = 2026-04-18T12:34:56Z\n"
        )
        let dict = Frontmatter.tomlTableToDict(table)
        XCTAssertEqual(dict["d"] as? String, "2026-04-18")
        XCTAssertEqual(dict["t"] as? String, "12:34:56")
        XCTAssertEqual(dict["dt"] as? String, "2026-04-18T12:34:56Z")
    }

    func testSwiftValuesConvertBackIntoATOMLTable() throws {
        let table = try Frontmatter.dictToTOMLTable([
            "s": "x",
            "i": 3,
            "d": 1.5,
            "b": true,
            "nested": ["inner": 1],
            "list": [1, 2]
        ])
        XCTAssertEqual(table["s"]?.string, "x")
        XCTAssertEqual(table["i"]?.int, 3)
        XCTAssertEqual(table["d"]?.double, 1.5)
        XCTAssertEqual(table["b"]?.bool, true)
        XCTAssertEqual(table["nested"]?.table?["inner"]?.int, 1)
        XCTAssertEqual(table["list"]?.array?.count, 2)
    }

    func testAValueTOMLCannotHoldIsStoredAsItsDescription() throws {
        let table = try Frontmatter.dictToTOMLTable([
            "url": URL(fileURLWithPath: "/tmp/x")
        ])
        XCTAssertEqual(table["url"]?.string, "file:///tmp/x")
    }

    func testTOMLSerializationRefusesANullValue() {
        let frontmatter = Frontmatter(
            format: .toml,
            data: ["published": NSNull()],
            rawContent: "",
            body: "",
            originalContent: ""
        )

        XCTAssertThrowsError(try frontmatter.serializeData()) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "TOML cannot represent the null value at key path published"
            )
        }
    }

    func testTOMLSerializationReportsTheFirstNullKeyInSortedOrder() {
        let keys = Array("abcdefghijklmnopqrstuvwxyz").map(String.init)
        let data = Dictionary(uniqueKeysWithValues: keys.map { ($0, NSNull()) })
        let frontmatter = Frontmatter(
            format: .toml,
            data: data,
            rawContent: "",
            body: "",
            originalContent: ""
        )

        XCTAssertThrowsError(try frontmatter.serializeData()) { error in
            XCTAssertEqual(
                error.localizedDescription,
                "TOML cannot represent the null value at key path a"
            )
        }
    }

    // MARK: - parseValue

    func testParseValueRecognizesBooleansCaseInsensitively() {
        XCTAssertEqual(Frontmatter.parseValue("TRUE") as? Bool, true)
        XCTAssertEqual(Frontmatter.parseValue("False") as? Bool, false)
    }

    func testParseValueRecognizesNegativeAndZeroIntegers() {
        XCTAssertEqual(Frontmatter.parseValue("-7") as? Int, -7)
        XCTAssertEqual(Frontmatter.parseValue("0") as? Int, 0)
    }

    func testParseValueRecognizesNegativeDoubles() {
        XCTAssertEqual(Frontmatter.parseValue("-2.5") as? Double, -2.5)
    }

    /// A double is only recognized when the text contains a decimal point, so
    /// exponent notation stays a string.
    func testParseValueLeavesExponentNotationAsAString() {
        XCTAssertEqual(Frontmatter.parseValue("1e5") as? String, "1e5")
    }

    func testParseValueSplitsBracketedListsOnCommas() {
        XCTAssertEqual(
            Frontmatter.parseValue("[ a , b ,c ]") as? [String],
            ["a", "b", "c"]
        )
    }

    func testParseValueOfAnEmptyBracketPairIsAnEmptyList() {
        XCTAssertEqual(Frontmatter.parseValue("[]") as? [String], [])
    }

    func testParseValueOfASingleElementListIsAOneElementList() {
        XCTAssertEqual(Frontmatter.parseValue("[only]") as? [String], ["only"])
    }

    func testParseValueRecognizesNullInsideAList() throws {
        let values = try XCTUnwrap(Frontmatter.parseValue("[a, null]") as? [Any])
        XCTAssertEqual(values[0] as? String, "a")
        XCTAssertTrue(values[1] is NSNull)
    }

    func testParseValueOfAnUnclosedBracketIsAString() {
        XCTAssertEqual(Frontmatter.parseValue("[a, b") as? String, "[a, b")
    }

    func testParseValueOfAnEmptyStringIsAnEmptyString() {
        XCTAssertEqual(Frontmatter.parseValue("") as? String, "")
    }

    // MARK: - FrontmatterFormat

    func testEveryFormatHasARawValue() {
        XCTAssertEqual(
            FrontmatterFormat.allCases.map(\.rawValue),
            ["yaml", "toml", "json"]
        )
    }

    func testFormatsAreConstructedFromTheirRawValues() {
        XCTAssertEqual(FrontmatterFormat(rawValue: "yaml"), .yaml)
        XCTAssertEqual(FrontmatterFormat(rawValue: "toml"), .toml)
        XCTAssertEqual(FrontmatterFormat(rawValue: "json"), .json)
        XCTAssertNil(FrontmatterFormat(rawValue: "xml"))
    }
}
