//
//  TrueColorRemapTests.swift
//  ModernTests
//
//  The profile's "True Color Remap" (Zach's fork): 24-bit text and background colors an app
//  sets are swapped for the profile's own.
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

    }

    func testTerminalRemapsTrueColorBackground() {
        let terminal = VT100Terminal()
        // Claude Code's dark theme: user message background, diff added/removed lines.
        terminal.trueColorRemap = [NSNumber(value: 0x373737): NSNumber(value: 0x2a2340),
                                   NSNumber(value: 0x225c2b): NSNumber(value: 0x4a3f1a),
                                   NSNumber(value: 0xffffff): NSNumber(value: 0xcdb8ff)]
        execute(terminal, "\u{1b}[48;2;55;55;55m")
        var r = terminal.graphicRendition
        XCTAssertEqual(r.bgColorMode, ColorMode24bit)
        XCTAssertEqual([r.bgColorCode, r.bgGreen, r.bgBlue], [0x2a, 0x23, 0x40])

        // Text and background in one sequence are each remapped; colon form too.
        execute(terminal, "\u{1b}[0;38;2;255;255;255;48:2:34:92:43m")
        r = terminal.graphicRendition
        XCTAssertEqual([r.fgColorCode, r.fgGreen, r.fgBlue], [0xcd, 0xb8, 0xff])
        XCTAssertEqual([r.bgColorCode, r.bgGreen, r.bgBlue], [0x4a, 0x3f, 0x1a])

        // A background not in the map, and a palette background, are left alone.
        execute(terminal, "\u{1b}[0;48;2;1;2;3m")
        r = terminal.graphicRendition
        XCTAssertEqual([r.bgColorCode, r.bgGreen, r.bgBlue], [1, 2, 3])
        execute(terminal, "\u{1b}[0;44m")
        r = terminal.graphicRendition
        XCTAssertEqual(r.bgColorMode, ColorModeNormal)
        XCTAssertEqual(r.bgColorCode, 4)
    }

    func testToleranceParsing() {
        let profile: [AnyHashable: Any] = ["True Color Remap": ["#d77757": "#f3cd5a"],
                                           "True Color Remap Tolerance": 32]
        XCTAssertEqual(TrueColorRemap.remap(forProfile: profile)?[TrueColorRemap.toleranceKey], 32)
        XCTAssertNil(TrueColorRemap.remap(forProfile: ["True Color Remap": ["#d77757": "#f3cd5a"]])?[TrueColorRemap.toleranceKey])
        XCTAssertEqual(TrueColorRemap.tolerance(500), TrueColorRemap.maximumTolerance)
        XCTAssertEqual(TrueColorRemap.tolerance(-3), 0)
        XCTAssertEqual(TrueColorRemap.tolerance(true), 0)
    }

    // Claude Code's spinner shimmer and stall colors (recorded from 2.1.325) are not theme
    // colors; within the tolerance they follow the theme color they were made from.
    func testNearestKeyFallbackKeepsTheOffset() {
        let map: [NSNumber: NSNumber] = [NSNumber(value: 0xd77757): NSNumber(value: 0xf3cd5a),   // claude -> gold
                                         NSNumber(value: 0xeb9f7f): NSNumber(value: 0xf8dd8c),   // claudeShimmer
                                         NSNumber(value: 0xdc5a5a): NSNumber(value: 0xf08ca0),   // diff "-" marker
                                         TrueColorRemap.toleranceKey: 32]
        // rgb(210,110,84): 11 from claude -> gold moved by (-5,-9,-3).
        XCTAssertEqual(TrueColorRemap.replacement(for: 0xd26e54, in: map), NSNumber(value: 0xeec457))
        // rgb(233,154,122): nearest is claudeShimmer -> light gold moved by (-2,-5,-5).
        XCTAssertEqual(TrueColorRemap.replacement(for: 0xe99a7a, in: map), NSNumber(value: 0xf6d887))
        // Exact keys win even when another key is nearer to... themselves.
        XCTAssertEqual(TrueColorRemap.replacement(for: 0xdc5a5a, in: map), NSNumber(value: 0xf08ca0))
        // Far from every key: unchanged. Offsets clamp at 255.
        XCTAssertNil(TrueColorRemap.replacement(for: 0x2040ff, in: map))
        XCTAssertEqual(TrueColorRemap.replacement(for: 0xf7a989, in: map), NSNumber(value: 0xffe796))
        // Without a tolerance only exact keys count.
        var exactOnly = map
        exactOnly[TrueColorRemap.toleranceKey] = nil
        XCTAssertNil(TrueColorRemap.replacement(for: 0xd26e54, in: exactOnly))
    }

    func testTerminalUsesTheFallback() {
        let terminal = VT100Terminal()
        terminal.trueColorRemap = [NSNumber(value: 0xd77757): NSNumber(value: 0xf3cd5a), TrueColorRemap.toleranceKey: 32]
        execute(terminal, "\u{1b}[38;2;210;110;84m")
        let r = terminal.graphicRendition
        XCTAssertEqual([r.fgColorCode, r.fgGreen, r.fgBlue], [0xee, 0xc4, 0x57])
        // A new map drops what the old one answered.
        terminal.trueColorRemap = [NSNumber(value: 0xd77757): NSNumber(value: 0x000000)]
        execute(terminal, "\u{1b}[38;2;210;110;84m")
        let r2 = terminal.graphicRendition
        XCTAssertEqual([r2.fgColorCode, r2.fgGreen, r2.fgBlue], [210, 110, 84])
    }

    func testTerminalWithoutRemapKeepsColors() {
        let terminal = VT100Terminal()
        execute(terminal, "\u{1b}[38;2;215;119;87m")
        let r = terminal.graphicRendition
        XCTAssertEqual([r.fgColorCode, r.fgGreen, r.fgBlue], [215, 119, 87])
    }
}
