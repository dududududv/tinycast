import Foundation

@main
@MainActor
struct JSONEditorTests {
    static var failures = 0

    static func check(_ message: String, _ condition: @autoclosure () -> Bool) {
        guard !condition() else { return }
        failures += 1
        print("FAIL: \(message)")
    }

    static func tokenText(_ token: JSONSyntaxToken, in source: String) -> String {
        (source as NSString).substring(with: token.range)
    }

    static func testValidation() {
        check("blank input has a neutral empty state", JSONEditorEngine.validate("  \n") == .empty)
        check("objects validate", JSONEditorEngine.validate(#"{"name":"Tinycast"}"#) == .valid)
        check("arrays validate", JSONEditorEngine.validate("[1, true, null]") == .valid)
        check("top-level fragments validate", JSONEditorEngine.validate("42") == .valid)

        let invalid = "{\n  \"name\": nope\n}"
        guard case .invalid(let issue) = JSONEditorEngine.validate(invalid) else {
            check("invalid JSON reports an issue", false)
            return
        }
        check("an issue identifies a positive line", issue.line > 0)
        check("an issue identifies a positive column", issue.column > 0)
        check(
            "an issue points inside the UTF-16 source",
            issue.utf16Offset >= 0 && issue.utf16Offset < invalid.utf16.count)
    }

    static func testTransforms() throws {
        let source = #"{"url":"https://tinycast.app","enabled":true,"count":2}"#
        let pretty = try JSONEditorEngine.prettyPrinted(source)
        check("pretty printing adds lines", pretty.contains("\n"))
        check("pretty printing indents values", pretty.contains("  \"enabled\""))
        check("pretty printing leaves slashes readable", pretty.contains("https://tinycast.app"))
        check("pretty printing ends at the closing brace", pretty.hasSuffix("}"))
        check("pretty printing adds no trailing newline", !pretty.hasSuffix("\n"))

        let minified = try JSONEditorEngine.minified(pretty)
        check("minifying removes layout whitespace", !minified.contains("\n"))
        check("minified output remains valid", JSONEditorEngine.validate(minified) == .valid)

        do {
            _ = try JSONEditorEngine.prettyPrinted("{")
            check("formatting invalid JSON throws", false)
        } catch let issue as JSONIssue {
            check("a transform preserves the structured issue", issue.line > 0)
        }
    }

    static func testSyntaxTokens() {
        let source = #"{"name":"Tinycast","count":2,"enabled":true,"missing":null}"#
        let tokens = JSONEditorEngine.syntaxTokens(in: source)
        let pairs = tokens.map { ($0.kind, tokenText($0, in: source)) }
        check("object keys have their own token kind", pairs.contains { $0 == (.key, #""name""#) })
        check("string values are tokenized", pairs.contains { $0 == (.string, #""Tinycast""#) })
        check("numbers are tokenized", pairs.contains { $0 == (.number, "2") })
        check("booleans are tokenized", pairs.contains { $0 == (.keyword, "true") })
        check("null is tokenized", pairs.contains { $0 == (.keyword, "null") })

        let escaped = #"{"quote":"a\\\"b","after":1}"#
        let escapedTokens = JSONEditorEngine.syntaxTokens(in: escaped)
        check(
            "escaped quotes stay inside one string token",
            escapedTokens.contains {
                $0.kind == .string && tokenText($0, in: escaped) == #""a\\\"b""#
            })
    }

    static func main() {
        check("valid paste is formatted", JSONEditorEngine.formatPastedSource("{\"a\":1}").contains("\n"))
        check("invalid paste is preserved exactly", JSONEditorEngine.formatPastedSource("{ bad\n") == "{ bad\n")
        let starts = JSONEditorEngine.lineStarts(in: "中文\n😀\n")
        check("line index uses UTF-16", starts == [0, 3, 6])
        check("line index locates emoji line", JSONEditorEngine.lineIndex(at: 5, starts: starts) == 1)
        check(
            "line index includes trailing empty line", JSONEditorEngine.lineIndex(at: 6, starts: starts) == 2)
        let large =
            "[" + Array(repeating: "{\"key\":123,\"value\":\"test\"}", count: 30_000).joined(separator: ",\n")
            + "]"
        let clock = ContinuousClock()
        let start = clock.now
        let analysis = JSONEditorEngine.analyze(large)
        check("large documents still validate", analysis.validation == .valid)
        check("large documents avoid full token allocation", analysis.tokens.isEmpty)
        let lines = JSONEditorEngine.lineStarts(in: large)
        for _ in 0..<10_000 {
            check(
                "indexed lookup finds final line",
                JSONEditorEngine.lineIndex(at: large.utf16.count, starts: lines) == 29_999)
        }
        print("Large JSON analysis + index + 10000 lookups: \(start.duration(to: clock.now))")
        check("brackets in strings are literal", JSONEditorEngine.isInsideString(#"{"key":"["#))
        check("escaped quotes do not end strings", JSONEditorEngine.isInsideString(#""a\"b"#))
        check("closed strings allow pairing", !JSONEditorEngine.isInsideString(#"{"key": "value","#))
        let nested = JSONEditorEngine.newline(in: "  {}", at: 3)
        check("newline expands a bracket pair", nested.text == "\n    \n  ")
        check("caret stays on the inner line", nested.caret == 5)
        check("newline keeps indentation", JSONEditorEngine.newline(in: "  1,", at: 4).text == "\n  ")
        check("empty newline is safe", JSONEditorEngine.newline(in: "", at: 0).text == "\n")
        do {
            testValidation()
            try testTransforms()
            testSyntaxTokens()
        } catch {
            failures += 1
            print("FAIL: unexpected error: \(error)")
        }

        print(failures == 0 ? "JSON editor tests passed" : "\(failures) tests failed")
        exit(failures == 0 ? 0 : 1)
    }
}
