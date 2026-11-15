//
//  iTermLuaLiteralParser.swift
//  iTerm2SharedARC
//
//  Zach's fork. Reads the data-only Lua that World of Warcraft writes for addon
//  SavedVariables (`Name = { ["key"] = value, ... }`), so an app-docked panel can take its
//  size and place from an addon's settings. It is not a Lua interpreter: only literals
//  (strings, numbers, booleans, nil, tables) and top-level assignments are understood.
//

import Foundation

enum LuaKey: Hashable {
    case string(String)
    case number(Double)
}

indirect enum LuaValue: Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case nilValue
    case table(LuaTable)

    var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    var numberValue: Double? {
        if case .number(let n) = self { return n }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    var tableValue: LuaTable? {
        if case .table(let t) = self { return t }
        return nil
    }

    // Walks nested tables by string keys. Returns nil as soon as a step is missing or is not
    // a table.
    subscript(path: String...) -> LuaValue? {
        var current: LuaValue? = self
        for key in path {
            current = current?.tableValue?.entries[.string(key)]
        }
        return current
    }
}

struct LuaTable: Equatable {
    var entries: [LuaKey: LuaValue] = [:]
}

struct LuaParseError: Error, Equatable, CustomStringConvertible {
    let message: String
    let offset: Int

    var description: String { "\(message) at byte \(offset)" }
}

// Parses a SavedVariables file into its top-level assignments.
struct LuaLiteralParser {
    private let bytes: [UInt8]
    private var i = 0

    // Deeply nested input is not something WoW writes; the limit keeps a hostile file from
    // overflowing the stack.
    private static let maximumDepth = 200

    init(_ text: String) {
        bytes = Array(text.utf8)
    }

    static func parseAssignments(_ text: String) throws -> [String: LuaValue] {
        var parser = LuaLiteralParser(text)
        return try parser.assignments()
    }

    private mutating func assignments() throws -> [String: LuaValue] {
        var result = [String: LuaValue]()
        skipSpaceAndComments()
        while i < bytes.count {
            guard let name = identifier() else {
                throw error("Expected a variable name")
            }
            skipSpaceAndComments()
            try expect(UInt8(ascii: "="))
            result[name] = try value(depth: 0)
            skipSpaceAndComments()
            if peek == UInt8(ascii: ";") {
                i += 1
                skipSpaceAndComments()
            }
        }
        return result
    }

    private var peek: UInt8? {
        return i < bytes.count ? bytes[i] : nil
    }

    private func error(_ message: String) -> LuaParseError {
        return LuaParseError(message: message, offset: i)
    }

    private mutating func expect(_ byte: UInt8) throws {
        skipSpaceAndComments()
        guard peek == byte else {
            throw error("Expected “\(Character(UnicodeScalar(byte)))”")
        }
        i += 1
    }

    private mutating func skipSpaceAndComments() {
        while let c = peek {
            if c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d {
                i += 1
            } else if c == UInt8(ascii: "-"), i + 1 < bytes.count, bytes[i + 1] == UInt8(ascii: "-") {
                // Line comment. Long comments (--[[ ]]) are not written by WoW.
                while let d = peek, d != 0x0a {
                    i += 1
                }
            } else {
                return
            }
        }
    }

    private static func isIdentifierStart(_ c: UInt8) -> Bool {
        return (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a) || c == UInt8(ascii: "_")
    }

    private static func isIdentifierBody(_ c: UInt8) -> Bool {
        return isIdentifierStart(c) || (c >= 0x30 && c <= 0x39)
    }

    private mutating func identifier() -> String? {
        guard let c = peek, Self.isIdentifierStart(c) else {
            return nil
        }
        let start = i
        while let d = peek, Self.isIdentifierBody(d) {
            i += 1
        }
        return String(decoding: bytes[start..<i], as: UTF8.self)
    }

    private mutating func value(depth: Int) throws -> LuaValue {
        skipSpaceAndComments()
        guard let c = peek else {
            throw error("Expected a value")
        }
        switch c {
        case UInt8(ascii: "{"):
            guard depth < Self.maximumDepth else {
                throw error("Tables nested too deeply")
            }
            return .table(try table(depth: depth + 1))
        case UInt8(ascii: "\""), UInt8(ascii: "'"):
            return .string(try string())
        case UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "0")...UInt8(ascii: "9"):
            return .number(try number())
        default:
            guard let word = identifier() else {
                throw error("Unexpected character")
            }
            switch word {
            case "true": return .bool(true)
            case "false": return .bool(false)
            case "nil": return .nilValue
            default: throw error("Unexpected word “\(word)”")
            }
        }
    }

    private mutating func table(depth: Int) throws -> LuaTable {
        try expect(UInt8(ascii: "{"))
        var table = LuaTable()
        var nextIndex = 1.0
        while true {
            skipSpaceAndComments()
            guard let c = peek else {
                throw error("Unterminated table")
            }
            if c == UInt8(ascii: "}") {
                i += 1
                return table
            }
            if c == UInt8(ascii: "[") {
                i += 1
                let key = try value(depth: depth)
                try expect(UInt8(ascii: "]"))
                try expect(UInt8(ascii: "="))
                let v = try value(depth: depth)
                switch key {
                case .string(let s): table.entries[.string(s)] = v
                case .number(let n): table.entries[.number(n)] = v
                default: throw error("Unsupported table key")
                }
            } else if Self.isIdentifierStart(c), let key = keyedIdentifier() {
                try expect(UInt8(ascii: "="))
                table.entries[.string(key)] = try value(depth: depth)
            } else {
                table.entries[.number(nextIndex)] = try value(depth: depth)
                nextIndex += 1
            }
            skipSpaceAndComments()
            if let sep = peek, sep == UInt8(ascii: ",") || sep == UInt8(ascii: ";") {
                i += 1
            }
        }
    }

    // An identifier that is followed by `=`, as in `{ name = value }`. A bare `true` used as a
    // positional value is put back so value(depth:) can read it.
    private mutating func keyedIdentifier() -> String? {
        let start = i
        guard let word = identifier() else {
            return nil
        }
        skipSpaceAndComments()
        if peek == UInt8(ascii: "="), !(i + 1 < bytes.count && bytes[i + 1] == UInt8(ascii: "=")) {
            return word
        }
        i = start
        return nil
    }

    private mutating func string() throws -> String {
        guard let quote = peek else {
            throw error("Expected a string")
        }
        i += 1
        var out = [UInt8]()
        while true {
            guard let c = peek else {
                throw error("Unterminated string")
            }
            i += 1
            if c == quote {
                return String(decoding: out, as: UTF8.self)
            }
            if c == 0x0a {
                throw error("Newline in string")
            }
            if c != UInt8(ascii: "\\") {
                out.append(c)
                continue
            }
            guard let e = peek else {
                throw error("Unterminated escape")
            }
            i += 1
            switch e {
            case UInt8(ascii: "n"): out.append(0x0a)
            case UInt8(ascii: "t"): out.append(0x09)
            case UInt8(ascii: "r"): out.append(0x0d)
            case UInt8(ascii: "a"): out.append(0x07)
            case UInt8(ascii: "b"): out.append(0x08)
            case UInt8(ascii: "f"): out.append(0x0c)
            case UInt8(ascii: "v"): out.append(0x0b)
            case 0x0a: out.append(0x0a)
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                // \ddd: up to three decimal digits.
                var code = Int(e - UInt8(ascii: "0"))
                var digits = 1
                while digits < 3, let d = peek, d >= UInt8(ascii: "0"), d <= UInt8(ascii: "9") {
                    code = code * 10 + Int(d - UInt8(ascii: "0"))
                    i += 1
                    digits += 1
                }
                guard code <= 255 else {
                    throw error("Escape out of range")
                }
                out.append(UInt8(code))
            default:
                // \\, \", \' and anything else stand for themselves.
                out.append(e)
            }
        }
    }

    private mutating func number() throws -> Double {
        let start = i
        if peek == UInt8(ascii: "-") {
            i += 1
        }
        if peek == UInt8(ascii: "0"), i + 1 < bytes.count, bytes[i + 1] | 0x20 == UInt8(ascii: "x") {
            i += 2
            let digitsStart = i
            while let c = peek, (c >= 0x30 && c <= 0x39) || (c | 0x20 >= 0x61 && c | 0x20 <= 0x66) {
                i += 1
            }
            let hex = String(decoding: bytes[digitsStart..<i], as: UTF8.self)
            guard let magnitude = UInt64(hex, radix: 16) else {
                throw error("Malformed hexadecimal number")
            }
            return bytes[start] == UInt8(ascii: "-") ? -Double(magnitude) : Double(magnitude)
        }
        while let c = peek,
              (c >= 0x30 && c <= 0x39) || c == UInt8(ascii: ".") || c | 0x20 == UInt8(ascii: "e") ||
                ((c == UInt8(ascii: "+") || c == UInt8(ascii: "-")) && bytes[i - 1] | 0x20 == UInt8(ascii: "e")) {
            i += 1
        }
        let text = String(decoding: bytes[start..<i], as: UTF8.self)
        guard let n = Double(text), n.isFinite else {
            throw LuaParseError(message: "Malformed number “\(text)”", offset: start)
        }
        return n
    }
}
