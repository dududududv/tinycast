import Foundation

struct JSONIssue: Error, Equatable, Sendable {
    let message: String
    let line: Int
    let column: Int
    let utf16Offset: Int
}

enum JSONValidation: Equatable, Sendable {
    case empty
    case valid
    case invalid(JSONIssue)

    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }
}

enum JSONSyntaxKind: Equatable, Sendable {
    case key
    case string
    case number
    case keyword
}

struct JSONSyntaxToken: Equatable, Sendable {
    let kind: JSONSyntaxKind
    let range: NSRange
}

struct JSONEditorAnalysis: Equatable, Sendable {
    let validation: JSONValidation
    let tokens: [JSONSyntaxToken]
}

enum JSONEditorEngine {
    static func analyze(_ source: String) -> JSONEditorAnalysis {
        JSONEditorAnalysis(validation: validate(source), tokens: syntaxTokens(in: source))
    }

    static func validate(_ source: String) -> JSONValidation {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .empty
        }
        do {
            _ = try object(from: source)
            return .valid
        } catch {
            return .invalid(issue(for: error, source: source))
        }
    }

    static func prettyPrinted(_ source: String) throws -> String {
        let value = try object(from: source)
        let data = try JSONSerialization.data(
            withJSONObject: value,
            options: [.prettyPrinted, .fragmentsAllowed, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    static func minified(_ source: String) throws -> String {
        let value = try object(from: source)
        let data = try JSONSerialization.data(
            withJSONObject: value,
            options: [.fragmentsAllowed, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }

    static func syntaxTokens(in source: String) -> [JSONSyntaxToken] {
        let source = source as NSString
        var tokens: [JSONSyntaxToken] = []
        var index = 0
        while index < source.length {
            let character = source.character(at: index)
            if character == quote {
                let end = stringEnd(in: source, from: index)
                let range = NSRange(location: index, length: end - index)
                let kind: JSONSyntaxKind = nextNonWhitespace(in: source, after: end) == colon
                    ? .key : .string
                tokens.append(JSONSyntaxToken(kind: kind, range: range))
                index = end
            } else if isNumberStart(character) {
                let end = numberEnd(in: source, from: index)
                tokens.append(
                    JSONSyntaxToken(
                        kind: .number, range: NSRange(location: index, length: end - index)))
                index = end
            } else if isLetter(character) {
                let end = wordEnd(in: source, from: index)
                let word = source.substring(with: NSRange(location: index, length: end - index))
                if word == "true" || word == "false" || word == "null" {
                    tokens.append(
                        JSONSyntaxToken(
                            kind: .keyword,
                            range: NSRange(location: index, length: end - index)))
                }
                index = end
            } else {
                index += 1
            }
        }
        return tokens
    }

    private static func object(from source: String) throws -> Any {
        let data = Data(source.utf8)
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw issue(for: error, source: source)
        }
    }

    private static func issue(for error: Error, source: String) -> JSONIssue {
        if let issue = error as? JSONIssue { return issue }
        let error = error as NSError
        let message = error.userInfo[NSDebugDescriptionErrorKey] as? String
            ?? error.localizedDescription
        if let line = number(after: "line ", in: message),
            let column = number(after: "column ", in: message)
        {
            return JSONIssue(
                message: message, line: line, column: column,
                utf16Offset: utf16Offset(line: line, column: column, in: source))
        }
        let byteOffset = (error.userInfo["NSJSONSerializationErrorIndex"] as? NSNumber)?.intValue
            ?? number(after: "character ", in: message)
            ?? 0
        let position = position(atUTF8Offset: byteOffset, in: source)
        return JSONIssue(
            message: message, line: position.line, column: position.column,
            utf16Offset: position.utf16Offset)
    }

    private static func number(after marker: String, in text: String) -> Int? {
        guard let markerRange = text.range(of: marker) else { return nil }
        let digits = text[markerRange.upperBound...].prefix { $0.isNumber }
        return Int(digits)
    }

    private static func utf16Offset(line: Int, column: Int, in source: String) -> Int {
        let source = source as NSString
        var offset = 0
        var currentLine = 1
        while currentLine < line, offset < source.length {
            offset = NSMaxRange(source.lineRange(for: NSRange(location: offset, length: 0)))
            currentLine += 1
        }
        return min(offset + max(column - 1, 0), source.length)
    }

    private static func position(
        atUTF8Offset requestedOffset: Int, in source: String
    ) -> (line: Int, column: Int, utf16Offset: Int) {
        let bytes = source.utf8
        let offset = min(max(requestedOffset, 0), bytes.count)
        let end = bytes.index(bytes.startIndex, offsetBy: offset)
        let prefix = String(decoding: bytes[..<end], as: UTF8.self)
        let lines = prefix.split(separator: "\n", omittingEmptySubsequences: false)
        return (
            line: lines.count,
            column: (lines.last?.count ?? 0) + 1,
            utf16Offset: (prefix as NSString).length)
    }

    private static func stringEnd(in source: NSString, from start: Int) -> Int {
        var index = start + 1
        var escaped = false
        while index < source.length {
            let character = source.character(at: index)
            if character == quote, !escaped { return index + 1 }
            if character == backslash {
                escaped.toggle()
            } else {
                escaped = false
            }
            index += 1
        }
        return source.length
    }

    private static func nextNonWhitespace(in source: NSString, after start: Int) -> unichar? {
        var index = start
        while index < source.length {
            let character = source.character(at: index)
            guard jsonWhitespace.contains(character) else { return character }
            index += 1
        }
        return nil
    }

    private static func numberEnd(in source: NSString, from start: Int) -> Int {
        var index = start + 1
        while index < source.length, numberCharacters.contains(source.character(at: index)) {
            index += 1
        }
        return index
    }

    private static func wordEnd(in source: NSString, from start: Int) -> Int {
        var index = start + 1
        while index < source.length, isLetter(source.character(at: index)) { index += 1 }
        return index
    }

    private static func isNumberStart(_ character: unichar) -> Bool {
        character == minus || (zero...nine).contains(character)
    }

    private static func isLetter(_ character: unichar) -> Bool {
        (lowercaseA...lowercaseZ).contains(character) || (uppercaseA...uppercaseZ).contains(character)
    }

    private static let quote = unichar(34)
    private static let colon = unichar(58)
    private static let backslash = unichar(92)
    private static let minus = unichar(45)
    private static let zero = unichar(48)
    private static let nine = unichar(57)
    private static let lowercaseA = unichar(97)
    private static let lowercaseZ = unichar(122)
    private static let uppercaseA = unichar(65)
    private static let uppercaseZ = unichar(90)
    private static let numberCharacters = Set("-+0123456789.eE".utf16)
    private static let jsonWhitespace: Set<unichar> = [9, 10, 13, 32]
}
