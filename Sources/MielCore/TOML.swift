import Foundation

// The part of TOML that AeroSpace configs use, enough to import one.

indirect enum TOMLValue: Equatable {
    case number(Double), string(String), bool(Bool), array([TOMLValue]), table([String: TOMLValue])

    /// A string, or the strings of an array.
    var strings: [String] {
        switch self {
        case let .string(s): [s]
        case let .array(items): items.compactMap { if case let .string(s) = $0 { s } else { nil } }
        default: []
        }
    }
}

/// Key-value lines with their table: `section` is the header's dotted path,
/// `block` counts `[[array tables]]` so their entries stay apart. A line it
/// can't read is skipped.
func parseTOML(_ text: String) -> [(section: String, block: Int, key: String, value: TOMLValue)] {
    var reader = TOMLReader(chars: Array(text))
    var entries: [(String, Int, String, TOMLValue)] = []
    var section = "", block = 0
    while true {
        reader.skip(newlines: true)
        guard let c = reader.peek else { break }
        if c == "[" {
            reader.i += 1
            let isArray = reader.eat("[")
            if let key = reader.key(), reader.eat("]"), !isArray || reader.eat("]") {
                section = key
                if isArray { block += 1 }
            }
        } else if let key = reader.key(), reader.eat("="), let value = reader.value() {
            entries.append((section, block, key, value))
        }
        reader.skipLine()
    }
    return entries
}

private struct TOMLReader {
    let chars: [Character]
    var i = 0

    var peek: Character? { i < chars.count ? chars[i] : nil }

    /// Spaces and comments; newlines too when asked.
    mutating func skip(newlines: Bool = false) {
        while let c = peek {
            if c == " " || c == "\t" || (newlines && (c == "\n" || c == "\r")) {
                i += 1
            } else if c == "#" {
                while let d = peek, d != "\n" { i += 1 }
            } else {
                break
            }
        }
    }

    mutating func skipLine() {
        while let c = peek, c != "\n" { i += 1 }
    }

    mutating func eat(_ c: Character) -> Bool {
        skip()
        guard peek == c else { return false }
        i += 1
        return true
    }

    /// `a.b`, `if.app-id`, `monitor."built-in"`, joined with dots, quotes gone.
    mutating func key() -> String? {
        var parts: [String] = []
        repeat {
            skip()
            if peek == "\"" || peek == "'" {
                guard case let .string(s)? = value() else { return nil }
                parts.append(s)
            } else {
                var part = ""
                while let c = peek, c.isLetter || c.isNumber || c == "_" || c == "-" { part.append(c); i += 1 }
                guard !part.isEmpty else { return nil }
                parts.append(part)
            }
            skip()
        } while eat(".")
        return parts.joined(separator: ".")
    }

    mutating func value() -> TOMLValue? {
        skip()
        guard let c = peek else { return nil }
        switch c {
        case "\"", "'": return string(quote: c)
        case "[":
            i += 1
            var items: [TOMLValue] = []
            while true {
                skip(newlines: true)
                if peek == "]" { i += 1; return .array(items) }
                guard let item = value() else { return nil }
                items.append(item)
                skip(newlines: true)
                if peek == "," { i += 1 }
            }
        case "{":
            i += 1
            var table: [String: TOMLValue] = [:]
            while true {
                skip()
                if peek == "}" { i += 1; return .table(table) }
                guard let k = key(), eat("="), let v = value() else { return nil }
                table[k] = v
                skip()
                if peek == "," { i += 1 }
            }
        case "t", "f":
            for word in ["true", "false"] where String(chars[i ..< min(i + word.count, chars.count)]) == word {
                i += word.count
                return .bool(word == "true")
            }
            return nil
        default:
            var text = ""
            while let d = peek, d.isNumber || "+-._eE".contains(d) { text.append(d); i += 1 }
            return Double(text.replacingOccurrences(of: "_", with: "")).map(TOMLValue.number)
        }
    }

    /// 'literal', "basic" with escapes, and the ''' / """ multi-line forms.
    private mutating func string(quote: Character) -> TOMLValue? {
        let triple = i + 2 < chars.count && chars[i + 1] == quote && chars[i + 2] == quote
        i += triple ? 3 : 1
        if triple, peek == "\n" { i += 1 } // a newline right after the opening quotes is not part of it
        var s = ""
        while let c = peek {
            if c == quote, !triple || (i + 2 < chars.count && chars[i + 1] == quote && chars[i + 2] == quote) {
                i += triple ? 3 : 1
                return .string(s)
            }
            if c == "\n", !triple { return nil }
            if c == "\\", quote == "\"", i + 1 < chars.count {
                let e = chars[i + 1]
                s.append(["n": "\n", "t": "\t", "\"": "\"", "\\": "\\"][e] ?? e)
                i += 2
                continue
            }
            s.append(c)
            i += 1
        }
        return nil
    }
}
