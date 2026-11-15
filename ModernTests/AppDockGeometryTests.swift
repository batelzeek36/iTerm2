//
//  AppDockGeometryTests.swift
//  ModernTests
//
//  Where an app-docked panel lands (Zach's fork, sources/AppDock). The two window sizes
//  below are real: World of Warcraft windows captured on 2026-11-14 with ElvUI's right chat
//  panel measured from the pixels. The computed panel must cover that panel to within one
//  device pixel at both sizes.
//

import XCTest
@testable import iTerm2SharedARC

final class AppDockGeometryTests: XCTestCase {
    // The parts of a real ElvUI.lua that place the right chat panel.
    private let elvUI = """
    ElvDB = {
    ["profileKeys"] = {
    ["Verthy Bates"] = "Default",
    },
    ["profiles"] = {
    ["Default"] = {
    ["chat"] = {
    ["panelWidth"] = 472,
    ["panelHeight"] = 236,
    ["panelSnapRightID"] = 4,
    },
    ["movers"] = {
    ["RightChatMover"] = "BOTTOMRIGHT,ElvUIParent,BOTTOMRIGHT,-4,4",
    ["LeftChatMover"] = "BOTTOMLEFT,ElvUIParent,BOTTOMLEFT,4,4",
    },
    },
    },
    ["global"] = {
    ["general"] = {
    ["UIScale"] = 0.63,
    },
    },
    }
    ElvPrivateDB = {
    }
    """

    private let primaryScreenHeight: CGFloat = 1117

    private func layout(_ side: ElvUIChatPanelSide = .right) throws -> AppDockLayout {
        return try ElvUIChatPanelReader.layout(savedVariables: elvUI,
                                               side: side,
                                               character: nil,
                                               fontSize: AppDockLayout.defaultFontSize)
    }

    // A window given as AX reports it (top-left origin) with a 28 pt title bar.
    private func contentRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
        let frame = AppDockTargetGeometry.cocoaRect(fromTopLeft: CGRect(x: x, y: y, width: width, height: height),
                                                    primaryScreenHeight: primaryScreenHeight)
        return AppDockTargetGeometry.contentRect(windowFrame: frame, titleBarHeight: 28)
    }

    // Edges in top-left screen points: (left, top, right, bottom).
    private func edges(_ rect: CGRect) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        return (rect.minX, primaryScreenHeight - rect.maxY, rect.maxX, primaryScreenHeight - rect.minY)
    }

    private func assertEdges(_ rect: CGRect,
                             _ expected: (CGFloat, CGFloat, CGFloat, CGFloat),
                             accuracy: CGFloat = 0.5,
                             file: StaticString = #filePath,
                             line: UInt = #line) {
        let e = edges(rect)
        XCTAssertEqual(e.0, expected.0, accuracy: accuracy, "left", file: file, line: line)
        XCTAssertEqual(e.1, expected.1, accuracy: accuracy, "top", file: file, line: line)
        XCTAssertEqual(e.2, expected.2, accuracy: accuracy, "right", file: file, line: line)
        XCTAssertEqual(e.3, expected.3, accuracy: accuracy, "bottom", file: file, line: line)
    }

    func testElvUIRightChatLayout() throws {
        let l = try layout()
        XCTAssertEqual(l.point, .bottomRight)
        XCTAssertEqual(l.relativePoint, .bottomRight)
        XCTAssertEqual(l.offset, CGVector(dx: -4, dy: 4))
        // panelHeight 236 + the 23-unit datatext bar the mover includes.
        XCTAssertEqual(l.size, CGSize(width: 472, height: 259))
        XCTAssertEqual(l.uiScale, 0.63)
    }

    // Window at (430, 33), 1284 x 858 (content 830 tall). ElvUI's right chat measured at
    // pixels x 1920...2562, y 1359...1710 of the window capture, i.e. these screen points.
    func testMatchesMeasuredPanelAtFirstSize() throws {
        let g = try XCTUnwrap(AppDockGeometry(layout: try layout(),
                                              contentRect: contentRect(x: 430, y: 33, width: 1284, height: 858),
                                              backingScale: 2))
        assertEdges(g.panelFrame, (1390, 712.5, 1711.5, 888.5))
        XCTAssertEqual(g.fontSize, 10)
    }

    // The same window resized to 1403 x 935 at (311, 33). Measured x 2098...2799,
    // y 1479...1863 of the capture.
    func testMatchesMeasuredPanelAtSecondSize() throws {
        let g = try XCTUnwrap(AppDockGeometry(layout: try layout(),
                                              contentRect: contentRect(x: 311, y: 33, width: 1403, height: 935),
                                              backingScale: 2))
        assertEdges(g.panelFrame, (1360, 772.5, 1711, 965))
        XCTAssertEqual(g.fontSize, 11)
    }

    // Everything scales with the content height: double the window, double the panel and font.
    func testScalesWithWindowHeight() throws {
        let l = try layout()
        let small = try XCTUnwrap(AppDockGeometry(layout: l,
                                                  contentRect: CGRect(x: 0, y: 0, width: 1000, height: 600),
                                                  backingScale: 2))
        let big = try XCTUnwrap(AppDockGeometry(layout: l,
                                                contentRect: CGRect(x: 0, y: 0, width: 2000, height: 1200),
                                                backingScale: 2))
        XCTAssertEqual(big.panelFrame.width, small.panelFrame.width * 2, accuracy: 1)
        XCTAssertEqual(big.panelFrame.height, small.panelFrame.height * 2, accuracy: 1)
        XCTAssertEqual(big.fontSize, small.fontSize * 2, accuracy: 0.5)
        // Anchored bottom right with a 4-unit inset.
        XCTAssertEqual(big.panelFrame.maxX, 2000 - 4 * big.pointsPerUnit, accuracy: 0.5)
        XCTAssertEqual(big.panelFrame.minY, 4 * big.pointsPerUnit, accuracy: 0.5)
    }

    func testTerminalSitsInsideBorderBelowHeader() throws {
        let g = try XCTUnwrap(AppDockGeometry(layout: try layout(),
                                              contentRect: CGRect(x: 0, y: 0, width: 1284, height: 830),
                                              backingScale: 2))
        let b = AppDockGeometry.borderWidth
        XCTAssertEqual(g.terminalFrame.minX, g.panelFrame.minX + b)
        XCTAssertEqual(g.terminalFrame.maxX, g.panelFrame.maxX - b)
        XCTAssertEqual(g.terminalFrame.minY, g.panelFrame.minY + b)
        XCTAssertEqual(g.terminalFrame.maxY, g.panelFrame.maxY - b - g.header.height - b)
        // Header proportions from the comp: 1.95em of a font 1.12x the terminal's.
        XCTAssertEqual(g.header.fontSize, g.fontSize * 1.12, accuracy: 0.01)
        XCTAssertEqual(g.header.height, g.fontSize * 1.12 * 1.95, accuracy: 0.5)
    }

    func testEdgesSnapToDevicePixels() throws {
        let g = try XCTUnwrap(AppDockGeometry(layout: try layout(),
                                              contentRect: CGRect(x: 10.3, y: 7.7, width: 1111.1, height: 777.7),
                                              backingScale: 2))
        for v in [g.panelFrame.minX, g.panelFrame.minY, g.panelFrame.maxX, g.panelFrame.maxY] {
            XCTAssertEqual((v * 2).rounded(), v * 2, accuracy: 1e-9)
        }
    }

    func testTooSmallWindowHasNoPanel() throws {
        XCTAssertNil(AppDockGeometry(layout: try layout(),
                                     contentRect: CGRect(x: 0, y: 0, width: 80, height: 60),
                                     backingScale: 2))
        XCTAssertNil(AppDockGeometry(layout: try layout(), contentRect: .zero, backingScale: 2))
    }

    func testLeftChatAndDefaults() throws {
        let left = try layout(.left)
        XCTAssertEqual(left.point, .bottomLeft)
        XCTAssertEqual(left.offset, CGVector(dx: 4, dy: 4))
        // A profile with no chat settings falls back to ElvUI's defaults.
        let bare = try ElvUIChatPanelReader.layout(savedVariables: "ElvDB = { }",
                                                   side: .right,
                                                   character: nil,
                                                   fontSize: 10)
        XCTAssertEqual(bare.size, CGSize(width: 412, height: 180 + 23))
        XCTAssertEqual(bare.uiScale, 0.64)
        XCTAssertEqual(bare.offset, CGVector(dx: -4, dy: 4))
    }

    func testHiddenDataTextBarAndSeparateSizes() throws {
        let text = """
        ElvDB = { ["profiles"] = { ["Default"] = {
            ["chat"] = { ["separateSizes"] = true, ["panelWidthRight"] = 300, ["panelHeightRight"] = 150 },
            ["datatexts"] = { ["panels"] = { ["RightChatDataPanel"] = { ["enable"] = false } } },
            ["movers"] = { ["RightChatMover"] = "TOPRIGHT,UIParent,TOPRIGHT,-10,-20" },
        } } }
        """
        let l = try ElvUIChatPanelReader.layout(savedVariables: text, side: .right, character: nil, fontSize: 12)
        XCTAssertEqual(l.size, CGSize(width: 300, height: 150))
        XCTAssertEqual(l.point, .topRight)
        XCTAssertEqual(l.offset, CGVector(dx: -10, dy: -20))
    }

    func testProfileChoice() throws {
        let shared = try XCTUnwrap(LuaLiteralParser.parseAssignments(
            "ElvDB = { [\"profileKeys\"] = { [\"A\"] = \"Mine\", [\"B\"] = \"Mine\" } }")["ElvDB"])
        XCTAssertEqual(ElvUIChatPanelReader.profileName(db: shared, character: nil), "Mine")
        let mixed = try XCTUnwrap(LuaLiteralParser.parseAssignments(
            "ElvDB = { [\"profileKeys\"] = { [\"A\"] = \"One\", [\"B\"] = \"Default\" } }")["ElvDB"])
        XCTAssertEqual(ElvUIChatPanelReader.profileName(db: mixed, character: nil), "Default")
        XCTAssertEqual(ElvUIChatPanelReader.profileName(db: mixed, character: "A"), "One")
    }

    func testMoverParsing() {
        XCTAssertEqual(ElvUIChatPanelReader.parseMover("BOTTOMRIGHT,ElvUIParent,BOTTOMRIGHT,-4,4"),
                       .init(point: .bottomRight, relativePoint: .bottomRight, offset: CGVector(dx: -4, dy: 4)))
        // Relative to another frame: no place on the window.
        XCTAssertNil(ElvUIChatPanelReader.parseMover("BOTTOMRIGHT,RightChatPanel,BOTTOMRIGHT,0,26"))
        XCTAssertNil(ElvUIChatPanelReader.parseMover("NOWHERE,ElvUIParent,BOTTOMRIGHT,0,0"))
        XCTAssertNil(ElvUIChatPanelReader.parseMover("BOTTOMRIGHT,ElvUIParent,BOTTOMRIGHT,4"))
    }

    func testTitleBarFromCloseButton() {
        // Close button at (438, 40), 12 x 14 in a window at (430, 33): 2 * 7 + 14 = 28.
        let window = CGRect(x: 430, y: 33, width: 1284, height: 858)
        XCTAssertEqual(AppDockTargetGeometry.titleBarHeight(windowTopLeft: window,
                                                             closeButtonTopLeft: CGRect(x: 438, y: 40, width: 12, height: 14),
                                                             isFullScreen: false), 28)
        XCTAssertEqual(AppDockTargetGeometry.titleBarHeight(windowTopLeft: window,
                                                             closeButtonTopLeft: CGRect(x: 438, y: 40, width: 12, height: 14),
                                                             isFullScreen: true), 0)
        XCTAssertEqual(AppDockTargetGeometry.titleBarHeight(windowTopLeft: window,
                                                             closeButtonTopLeft: nil,
                                                             isFullScreen: false), 0)
    }
}
