//
//  AppDockLuaParserTests.swift
//  ModernTests
//
//  The SavedVariables reader behind app-docked panels (Zach's fork, sources/AppDock).
//

import XCTest
@testable import iTerm2SharedARC

final class AppDockLuaParserTests: XCTestCase {
    func testTopLevelAssignmentsAndNestedTables() throws {
        let text = """
        ElvDB = {
        ["profileKeys"] = {
        ["Verthy Bates"] = "Default",
        },
        ["global"] = {
        ["general"] = {
        ["UIScale"] = 0.63,
        },
        },
        }
        ElvPrivateDB = {
        ["flag"] = true,
        }
        """
        let result = try LuaLiteralParser.parseAssignments(text)
        XCTAssertEqual(Set(result.keys), ["ElvDB", "ElvPrivateDB"])
        XCTAssertEqual(result["ElvDB"]?["profileKeys", "Verthy Bates"]?.stringValue, "Default")
        XCTAssertEqual(result["ElvDB"]?["global", "general", "UIScale"]?.numberValue, 0.63)
        XCTAssertEqual(result["ElvPrivateDB"]?["flag"]?.boolValue, true)
        XCTAssertNil(result["ElvDB"]?["global", "missing", "UIScale"])
    }

    func testValueKinds() throws {
        let text = """
        V = {
            name = "x",
            [1] = -4,
            [2] = 1e3,
            [3] = 0x1F,
            nothing = nil,
            ["escaped"] = "a\\"b\\\\c\\n\\65",
        }
        P = { 'single', 42; true }
        """
        let all = try LuaLiteralParser.parseAssignments(text)
        let v = try XCTUnwrap(all["V"]?.tableValue)
        XCTAssertEqual(v.entries[.string("name")], .string("x"))
        XCTAssertEqual(v.entries[.number(1)], .number(-4))
        XCTAssertEqual(v.entries[.number(2)], .number(1000))
        XCTAssertEqual(v.entries[.number(3)], .number(31))
        XCTAssertEqual(v.entries[.string("nothing")], .nilValue)
        XCTAssertEqual(v.entries[.string("escaped")], .string("a\"b\\c\nA"))

        let p = try XCTUnwrap(all["P"]?.tableValue)
        XCTAssertEqual(p.entries[.number(1)], .string("single"))
        XCTAssertEqual(p.entries[.number(2)], .number(42))
        XCTAssertEqual(p.entries[.number(3)], .bool(true))
    }

    func testCommentsAreSkipped() throws {
        let text = """
        -- written by the game
        A = { ["x"] = 1, } -- trailing
        """
        XCTAssertEqual(try LuaLiteralParser.parseAssignments(text)["A"]?["x"]?.numberValue, 1)
    }

    func testMalformedInputThrows() {
        XCTAssertThrowsError(try LuaLiteralParser.parseAssignments("A = { [\"x\"] = 1"))
        XCTAssertThrowsError(try LuaLiteralParser.parseAssignments("A = \"unterminated"))
        XCTAssertThrowsError(try LuaLiteralParser.parseAssignments("A = function() end"))
        XCTAssertThrowsError(try LuaLiteralParser.parseAssignments("= 3"))
    }

    func testDeepNestingIsRefused() {
        let text = "A = " + String(repeating: "{", count: 500) + String(repeating: "}", count: 500)
        XCTAssertThrowsError(try LuaLiteralParser.parseAssignments(text))
    }
}
