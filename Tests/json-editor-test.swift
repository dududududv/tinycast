import Foundation

var failures = 0

func check(_ message: String, _ condition: @autoclosure () -> Bool) {
    guard !condition() else { return }
    failures += 1
    print("FAIL: \(message)")
}

func tokenText(_ token: JSONSyntaxToken, in source: String) -> String {
    (source as NSString).substring(with: token.range)
}

func testValidation() {
    check("blank input has a neutral empty state", JSONEditorEngine.validate("  \n") == .empty)
    check("objects validate", JSONEditorEngine.validate(#"{"name":"Tinycast"}"#) == .valid)
    check("arrays validate", JSONEditorEngine.validate("[1, true, null]") == .valid)
    check("top-level fragments validate", JSONEditorEngine.validate("42") == .valid)

    guard case .invalid(let issue) = JSONEditorEngine.validate("{\n  \"name\": true,\n}") else {
        check("invalid JSON reports an issue", false)
        return
    }
    check("an issue identifies a positive line", issue.line > 0)
    check("an issue identifies a positive column", issue.column > 0)
    check("an issue points inside the UTF-16 source", issue.utf16Offset >= 0 && issue.utf16Offset < 19)
}

func testTransforms() throws {
    let source = #"{"url":"https://tinycast.app","enabled":true,"count":2}"#
    let pretty = try JSONEditorEngine.prettyPrinted(source)
    check("pretty printing adds lines", pretty.contains("\n"))
    check("pretty printing indents values", pretty.contains("  \"enabled\""))
    check("pretty printing leaves slashes readable", pretty.contains("https://tinycast.app"))
    check("pretty printing ends in one newline", pretty.hasSuffix("\n") && !pretty.hasSuffix("\n\n"))

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

func testSyntaxTokens() {
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
        escapedTokens.contains { $0.kind == .string && tokenText($0, in: escaped) == #""a\\\"b""# })
}

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
