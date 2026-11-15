//
//  AppDockSettingsTests.swift
//  ModernTests
//
//  Profile keys, visibility and focus rules, and the truecolor remap behind app-docked
//  panels (Zach's fork, sources/AppDock).
//

import XCTest
@testable import iTerm2SharedARC

final class AppDockSettingsTests: XCTestCase {
    private let base: [AnyHashable: Any] = [
        KEY_GUID: "dock-guid",
        KEY_NAME: "Claude over WoW",
        "Dock To App Bundle ID": "com.blizzard.worldofwarcraft",
    ]

    private func profile(_ extra: [AnyHashable: Any]) -> [AnyHashable: Any] {
        return base.merging(extra) { _, new in new }
    }

    func testNotDockedWithoutBundleID() {
        XCTAssertNil(AppDockSettings(profile: [KEY_GUID: "g", KEY_NAME: "n"]))
        XCTAssertNil(AppDockSettings(profile: profile(["Dock To App Bundle ID": "   "])))
        XCTAssertFalse(AppDockWindowMarker.isDocked([KEY_GUID: "g"]))
        XCTAssertTrue(AppDockWindowMarker.isDocked(base))
    }

    func testDefaults() throws {
        let s = try XCTUnwrap(AppDockSettings(profile: base))
        XCTAssertEqual(s.headerTitle, "Claude over WoW")
        XCTAssertEqual(s.headerSubtitle, "")
        XCTAssertEqual(s.elvUIPanel, .right)
        XCTAssertEqual(s.fallbackLayout.fontSize, AppDockLayout.defaultFontSize)
        XCTAssertEqual(s.colors.accent, AppDockRGBA(red: 0xf3, green: 0xcd, blue: 0x5a, alpha: 255))
        XCTAssertEqual(s.currentLayout(), s.fallbackLayout)
    }

    func testOverridesAndValidation() throws {
        let s = try XCTUnwrap(AppDockSettings(profile: profile([
            "Dock Header Title": "Claude",
            "Dock Header Subtitle": "wow-forever",
            "Dock Font Size": 12,
            "Dock Accent Color": "#112233",
            "Dock Header Text Color": "not a color",
            "Dock ElvUI Panel": "LeftChat",
            "Dock Layout": ["Point": "topLeft", "Relative Point": "TOPLEFT", "X": 10, "Y": -10,
                            "Width": 300, "Height": -5, "UI Scale": 9],
        ])))
        XCTAssertEqual(s.headerTitle, "Claude")
        XCTAssertEqual(s.headerSubtitle, "wow-forever")
        XCTAssertEqual(s.fallbackLayout.fontSize, 12)
        XCTAssertEqual(s.colors.accent, AppDockRGBA(red: 0x11, green: 0x22, blue: 0x33, alpha: 255))
        // Invalid values keep their defaults.
        XCTAssertEqual(s.colors.text, AppDockSettings.Colors().text)
        XCTAssertEqual(s.elvUIPanel, .left)
        XCTAssertEqual(s.fallbackLayout.point, .topLeft)
        XCTAssertEqual(s.fallbackLayout.offset, CGVector(dx: 10, dy: -10))
        XCTAssertEqual(s.fallbackLayout.size.width, 300)
        XCTAssertEqual(s.fallbackLayout.size.height, AppDockLayout.elvUIRightChatDefault.size.height)
        XCTAssertEqual(s.fallbackLayout.uiScale, AppDockLayout.elvUIRightChatDefault.uiScale)
    }

    func testElvUIFileWinsAndUnreadableFileFallsBack() throws {
        let s = try XCTUnwrap(AppDockSettings(profile: profile(["Dock ElvUI SavedVariables": "/x/ElvUI.lua"])))
        let fromFile = s.currentLayout { _ in
            "ElvDB = { [\"global\"] = { [\"general\"] = { [\"UIScale\"] = 0.5 } } }"
        }
        XCTAssertEqual(fromFile.uiScale, 0.5)
        XCTAssertEqual(s.currentLayout { _ in nil }, s.fallbackLayout)
        XCTAssertEqual(s.currentLayout { _ in "ElvDB = {" }, s.fallbackLayout)
    }

    func testHexColors() {
        XCTAssertEqual(AppDockRGBA(hex: "#f3cd5a")?.packedRGB, 0xf3cd5a)
        XCTAssertEqual(AppDockRGBA(hex: "060607")?.packedRGB, 0x060607)
        XCTAssertEqual(AppDockRGBA(hex: "#0e0e109e")?.alpha, 0x9e)
        XCTAssertNil(AppDockRGBA(hex: "#fff"))
        XCTAssertNil(AppDockRGBA(hex: "#gggggg"))
    }

    // MARK: - Visibility and focus

    private func show(present: Bool = true, front: Bool = false, key: Bool = false, hidden: Bool = false) -> Bool {
        return AppDockVisibility.shouldShow(.init(targetWindowPresent: present,
                                                  targetIsFrontmost: front,
                                                  panelIsKey: key,
                                                  hiddenByUser: hidden))
    }

    func testVisibility() {
        XCTAssertTrue(show(front: true), "over the game while the game is frontmost")
        XCTAssertTrue(show(key: true), "while the panel has the keyboard")
        XCTAssertFalse(show(), "another app is frontmost: out of the way")
        XCTAssertFalse(show(present: false, front: true, key: true), "no game window: no panel")
        XCTAssertFalse(show(front: true, key: true, hidden: true), "hidden with the hotkey")
    }

    func testFocusHotKey() {
        XCTAssertEqual(AppDockFocusPolicy.focusAction(targetWindowPresent: true, panelIsKey: false), .focusPanel)
        XCTAssertEqual(AppDockFocusPolicy.focusAction(targetWindowPresent: true, panelIsKey: true), .returnFocusToTarget)
        XCTAssertEqual(AppDockFocusPolicy.focusAction(targetWindowPresent: false, panelIsKey: false), .nothing)
        // Click-through unless it has the keyboard (a click on a bag item under it reaches the game).
        XCTAssertFalse(AppDockFocusPolicy.terminalTakesClicks(panelIsKey: false))
        XCTAssertTrue(AppDockFocusPolicy.terminalTakesClicks(panelIsKey: true))
    }

    func testHotKeyHint() {
        XCTAssertEqual(AppDockHotKeyHint.string(modifiers: [.control, .option, .command], key: "c"), "⌃⌥⌘C")
        XCTAssertEqual(AppDockHotKeyHint.string(modifiers: [.command, .shift], key: "k"), "⇧⌘K")
    }
}
