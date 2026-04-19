//
//  ListCommandTests.swift
//  md
//
//  Created by Adam Wulf on 4/12/26.
//

import XCTest
@testable import md

final class ListCommandTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("md-list-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    // MARK: - Helpers

    @discardableResult
    private func write(_ contents: String, to relativePath: String) throws -> URL {
        let url = tempRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Parse the list command with the given extra args (directories are
    /// appended automatically), collect entries, and return rendered output.
    private func runList(_ extraArgs: [String] = [], dirs: [String]? = nil) throws -> String {
        let directories = dirs ?? [tempRoot.path]
        var args = extraArgs
        args.append(contentsOf: directories)
        let cmd = try ListCommand.parse(args)
        return try cmd.render(cmd.collectEntries())
    }

    // MARK: - Validation

    func testRejectsBothKeyAndKeys() {
        XCTAssertThrowsError(try ListCommand.parse([tempRoot.path, "--key", "a", "--keys", "b,c"]).validate())
    }

    func testRejectsEmptyDirectoryList() {
        XCTAssertThrowsError(try ListCommand.parse([]))
    }

    // MARK: - Walking

    func testCollectsOnlyMdFiles() throws {
        try write("---\ntitle: A\n---\nbody\n", to: "a.md")
        try write("not markdown", to: "readme.txt")
        try write("---\ntitle: B\n---\nbody\n", to: "b.md")

        let out = try runList()
        XCTAssertTrue(out.contains("/a.md =="))
        XCTAssertTrue(out.contains("/b.md =="))
        XCTAssertFalse(out.contains("readme.txt"))
    }

    func testUppercaseExtensionIncluded() throws {
        try write("---\ntitle: Upper\n---\n", to: "upper.MD")
        let out = try runList()
        XCTAssertTrue(out.contains("/upper.MD =="))
        XCTAssertTrue(out.contains("title: Upper"))
    }

    func testNonRecursiveSkipsSubdirectories() throws {
        try write("---\ntitle: Top\n---\n", to: "top.md")
        try write("---\ntitle: Nested\n---\n", to: "sub/nested.md")

        let out = try runList()
        XCTAssertTrue(out.contains("/top.md =="))
        XCTAssertFalse(out.contains("/sub/nested.md =="))
    }

    func testRecursiveIncludesSubdirectories() throws {
        try write("---\ntitle: Top\n---\n", to: "top.md")
        try write("---\ntitle: Nested\n---\n", to: "sub/nested.md")

        let out = try runList(["-r"])
        XCTAssertTrue(out.contains("/top.md =="))
        XCTAssertTrue(out.contains("/sub/nested.md =="))
    }

    func testSymlinkedDirectoryNotDescended() throws {
        try write("---\ntitle: Real\n---\n", to: "real/a.md")
        let linkURL = tempRoot.appendingPathComponent("linkdir")
        let target = tempRoot.appendingPathComponent("real").path
        try FileManager.default.createSymbolicLink(atPath: linkURL.path, withDestinationPath: target)

        let out = try runList(["-r"])
        XCTAssertTrue(out.contains("/real/a.md =="))
        XCTAssertFalse(out.contains("/linkdir/a.md =="))
    }

    func testOverlappingDirectoryArgsDeduplicated() throws {
        try write("---\ntitle: A\n---\n", to: "sub/a.md")
        let sub = tempRoot.appendingPathComponent("sub").path
        let out = try runList(["-r"], dirs: [tempRoot.path, sub])
        let occurrences = out.components(separatedBy: "/sub/a.md ==").count - 1
        XCTAssertEqual(occurrences, 1)
    }

    func testMissingDirectoryEmitsStderrAndContinues() throws {
        try write("---\ntitle: A\n---\n", to: "a.md")
        let out = try runList([], dirs: [tempRoot.path, "/does/not/exist"])
        XCTAssertTrue(out.contains("/a.md =="))
    }

    func testEmptyDirectoryProducesEmptyOutput() throws {
        let out = try runList()
        XCTAssertEqual(out, "")
    }

    // MARK: - Missing-mode filtering

    func testMissingIncludeKeepsFilesWithoutFrontmatter() throws {
        try write("---\ntitle: A\n---\n", to: "a.md")
        try write("# just a heading\n", to: "b.md")

        let out = try runList()
        XCTAssertTrue(out.contains("/a.md =="))
        XCTAssertTrue(out.contains("/b.md =="))
        XCTAssertTrue(out.contains("(no frontmatter)"))
    }

    func testMissingSkipDropsFilesWithoutFrontmatter() throws {
        try write("---\ntitle: A\n---\n", to: "a.md")
        try write("# no fm\n", to: "b.md")

        let out = try runList(["--missing", "skip"])
        XCTAssertTrue(out.contains("/a.md =="))
        XCTAssertFalse(out.contains("/b.md =="))
    }

    func testMissingOnlyReturnsFilesWithoutFrontmatter() throws {
        try write("---\ntitle: A\n---\n", to: "a.md")
        try write("# no fm\n", to: "b.md")

        let out = try runList(["--missing", "only"])
        XCTAssertFalse(out.contains("/a.md =="))
        XCTAssertTrue(out.contains("/b.md =="))
        XCTAssertTrue(out.contains("(no frontmatter)"))
    }

    // MARK: - Sort

    func testSortByName() throws {
        try write("---\ntitle: Z\n---\n", to: "z.md")
        try write("---\ntitle: A\n---\n", to: "a.md")

        let out = try runList(["--sort", "name"])
        let aIdx = out.range(of: "/a.md ==")?.lowerBound
        let zIdx = out.range(of: "/z.md ==")?.lowerBound
        XCTAssertNotNil(aIdx)
        XCTAssertNotNil(zIdx)
        XCTAssertTrue(aIdx! < zIdx!)
    }

    // MARK: - Plain output

    func testPlainOutputDefaultYAML() throws {
        try write("---\ntitle: Hello\n---\n", to: "a.md")
        try write("# no fm\n", to: "b.md")

        let out = try runList()
        XCTAssertTrue(out.contains("== "))
        XCTAssertTrue(out.contains("title: Hello"))
        XCTAssertTrue(out.contains("(no frontmatter)"))
    }

    func testPlainOutputConvertsFromTOMLToJSON() throws {
        try write("+++\ntitle = \"Hi\"\n+++\n", to: "a.md")

        let out = try runList(["--format", "json"])
        XCTAssertTrue(out.contains("\"title\""))
        XCTAssertTrue(out.contains("\"Hi\""))
    }

    func testPlainOutputNormalizesMixedFormats() throws {
        try write("---\ntitle: FromYAML\n---\n", to: "yaml.md")
        try write("+++\ntitle = \"FromTOML\"\n+++\n", to: "toml.md")
        try write(";;;\n{\"title\": \"FromJSON\"}\n;;;\n", to: "json.md")

        let out = try runList()
        XCTAssertTrue(out.contains("title: FromYAML"))
        XCTAssertTrue(out.contains("title: FromTOML"))
        XCTAssertTrue(out.contains("title: FromJSON"))
        XCTAssertFalse(out.contains("+++"))
        XCTAssertFalse(out.contains(";;;"))
    }

    func testPlainKeyProjectionTSV() throws {
        try write("---\ntitle: First\n---\n", to: "a.md")
        try write("---\ntitle: Second\n---\n", to: "b.md")
        try write("---\nauthor: Jane\n---\n", to: "c.md")

        let out = try runList(["--key", "title"])
        XCTAssertFalse(out.contains("c.md"))
        let lines = out.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].hasSuffix("\tFirst"))
        XCTAssertTrue(lines[1].hasSuffix("\tSecond"))
    }

    func testPlainKeyOnNestedDict() throws {
        try write("---\nauthor:\n  name: Jane\n  email: j@e.com\n---\n", to: "a.md")
        let out = try runList(["--key", "author"])
        XCTAssertTrue(out.contains("\"name\":\"Jane\""))
        XCTAssertTrue(out.contains("\"email\":\"j@e.com\""))
        XCTAssertFalse(out.contains("\"name\": \"Jane\""))
    }

    // MARK: - JSON output

    func testJSONOutputShape() throws {
        try write("---\ntitle: Hello\ntags: [a, b]\n---\n", to: "a.md")
        try write("# no fm\n", to: "b.md")

        let out = try runList(["--output", "json"])
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(out.utf8)) as? [[String: Any]])
        XCTAssertEqual(array.count, 2)

        let first = array[0]
        XCTAssertEqual(first["format"] as? String, "yaml")
        let fm = first["frontmatter"] as? [String: Any]
        XCTAssertEqual(fm?["title"] as? String, "Hello")

        let second = array[1]
        XCTAssertTrue(second["frontmatter"] is NSNull)
        XCTAssertTrue(second["format"] is NSNull)
    }

    func testJSONKeyProducesNestedShape() throws {
        try write("---\nauthor:\n  name: Jane\n  email: j@e.com\n---\n", to: "a.md")

        let out = try runList(["--output", "json", "--key", "author.name"])
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(out.utf8)) as? [[String: Any]])
        let fm = try XCTUnwrap(array[0]["frontmatter"] as? [String: Any])
        let author = try XCTUnwrap(fm["author"] as? [String: Any])
        XCTAssertEqual(author["name"] as? String, "Jane")
        XCTAssertNil(author["email"])
        XCTAssertNil(fm["author.name"])
    }

    func testNDJSONOutputEmitsOnePerLine() throws {
        try write("---\ntitle: A\n---\n", to: "a.md")
        try write("---\ntitle: B\n---\n", to: "b.md")

        let out = try runList(["--output", "ndjson"])
        let lines = out.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 2)
        for line in lines {
            let obj = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            XCTAssertNotNil(obj?["path"])
        }
    }

    func testKeysProjectionSubsetsFrontmatter() throws {
        try write("---\ntitle: Hello\nauthor: Jane\ndraft: true\n---\n", to: "a.md")

        let out = try runList(["--output", "json", "--keys", "title,author"])
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(out.utf8)) as? [[String: Any]])
        let fm = try XCTUnwrap(array[0]["frontmatter"] as? [String: Any])
        XCTAssertEqual(fm["title"] as? String, "Hello")
        XCTAssertEqual(fm["author"] as? String, "Jane")
        XCTAssertNil(fm["draft"])
    }

    func testKeysProjectionNestedPath() throws {
        try write("---\nauthor:\n  name: Jane\n  email: j@e.com\nother: x\n---\n", to: "a.md")

        let out = try runList(["--output", "json", "--keys", "author.name"])
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(out.utf8)) as? [[String: Any]])
        let fm = try XCTUnwrap(array[0]["frontmatter"] as? [String: Any])
        let author = try XCTUnwrap(fm["author"] as? [String: Any])
        XCTAssertEqual(author["name"] as? String, "Jane")
        XCTAssertNil(author["email"])
        XCTAssertNil(fm["other"])
    }

    func testKeysProjectionTrimsWhitespaceAndEmpties() throws {
        try write("---\ntitle: Hello\nauthor: Jane\n---\n", to: "a.md")

        let out = try runList(["--output", "json", "--keys", " title , , author , "])
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(out.utf8)) as? [[String: Any]])
        let fm = try XCTUnwrap(array[0]["frontmatter"] as? [String: Any])
        XCTAssertEqual(fm["title"] as? String, "Hello")
        XCTAssertEqual(fm["author"] as? String, "Jane")
    }
}
