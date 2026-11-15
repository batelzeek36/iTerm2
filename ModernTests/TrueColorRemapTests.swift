//
//  TrueColorRemapTests.swift
//  ModernTests
//
//  The profile's "True Color Remap" (Zach's fork): 24-bit foreground colors an app sets are
//  swapped for the profile's own.
//

import XCTest
@testable import iTerm2SharedARC

final class TrueColorRemapTests: XCTestCase {
    func testRemapParsing() {
        let remap = TrueColorRemap.remap(forProfile: ["True Color Remap": ["#d77757": "#f3cd5a",
                                                                          "#ffffff": "#cdb8ff",
                                                                          "bogus": "#000000",
                                                                          "#000000": 7]])
        XCTAssertEqual(remap, [NSNumber(value: 0xd77757): NSNumber(value: 0xf3cd5a),
                               NSNumber(value: 0xffffff): NSNumber(value: 0xcdb8ff)])
        XCTAssertNil(TrueColorRemap.remap(forProfile: [:]))
        XCTAssertNil(TrueColorRemap.remap(forProfile: ["True Color Remap": ["x": "y"]]))
    }

    private func execute(_ terminal: VT100Terminal, _ string: String) {
        let parser = VT100Parser()
        parser.encoding = String.Encoding.utf8.rawValue
        let bytes = Array(string.utf8)
        bytes.withUnsafeBufferPointer { buf in
            parser.putStreamData(buf.baseAddress, length: Int32(buf.count))
        }
        var vector = CVector()
        CVectorCreate(&vector, 100)
        _ = parser.addParsedTokens(to: &vector)
        for i in 0..<CVectorCount(&vector) {
            terminal.execute(CVectorGetObject(&vector, i) as! VT100Token)
        }
        CVectorDestroy(&vector)
    }

    func testTerminalRemapsTrueColorForeground() {
        let terminal = VT100Terminal()
        terminal.trueColorRemap = [NSNumber(value: 0xd77757): NSNumber(value: 0xf3cd5a)]
        execute(terminal, "\u{1b}[38;2;215;119;87m")
        var r = terminal.graphicRendition
        XCTAssertEqual(r.fgColorMode, ColorMode24bit)
        XCTAssertEqual([r.fgColorCode, r.fgGreen, r.fgBlue], [0xf3, 0xcd, 0x5a])

        // Colon form, and a color that is not in the map, are left alone.
        execute(terminal, "\u{1b}[38:2:1:2:3m")
        r = terminal.graphicRendition
        XCTAssertEqual([r.fgColorCode, r.fgGreen, r.fgBlue], [1, 2, 3])
        execute(terminal, "\u{1b}[38:2:215:119:87m")
        r = terminal.graphicRendition
        XCTAssertEqual([r.fgColorCode, r.fgGreen, r.fgBlue], [0xf3, 0xcd, 0x5a])

        // Backgrounds are not remapped.
        execute(terminal, "\u{1b}[0;48;2;215;119;87m")
        r = terminal.graphicRendition
        XCTAssertEqual([r.bgColorCode, r.bgGreen, r.bgBlue], [215, 119, 87])
    }

    func testTerminalWithoutRemapKeepsColors() {
        let terminal = VT100Terminal()
        execute(terminal, "\u{1b}[38;2;215;119;87m")
        let r = terminal.graphicRendition
        XCTAssertEqual([r.fgColorCode, r.fgGreen, r.fgBlue], [215, 119, 87])
    }
}
