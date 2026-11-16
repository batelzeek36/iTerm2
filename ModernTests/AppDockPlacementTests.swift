//
//  AppDockPlacementTests.swift
//  ModernTests
//
//  The Mini/Tall size button and dragging of app-docked panels (Zach's fork, sources/AppDock,
//  2026-11-15): the tall layout, the dragged offset in UI units, keeping the panel inside the
//  window, snapping back, the saved form, what a press on the header means and what its hint
//  says. The slot is ElvUI's right chat as Zach has it (472 x 259 units, BOTTOMRIGHT -4,4 at
//  UI scale 0.63).
//

import XCTest
@testable import iTerm2SharedARC

final class AppDockPlacementTests: XCTestCase {
    private let slot = AppDockLayout(point: .bottomRight,
                                     relativePoint: .bottomRight,
                                     offset: CGVector(dx: -4, dy: 4),
                                     size: CGSize(width: 472, height: 259),
                                     uiScale: 0.63,
                                     fontSize: AppDockLayout.defaultFontSize)
    // A 1403 x 907 pt content area (WoW windowed, 2026-11-14 capture) at an arbitrary origin.
    private let content = CGRect(x: 100, y: 50, width: 1403, height: 907)

    private func frame(_ layout: AppDockLayout, in rect: CGRect? = nil) throws -> CGRect {
        return try XCTUnwrap(layout.frame(in: rect ?? content))
    }

    private func assertEqual(_ a: CGRect, _ b: CGRect, accuracy: CGFloat = 1e-6,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.minX, b.minX, accuracy: accuracy, "minX", file: file, line: line)
        XCTAssertEqual(a.minY, b.minY, accuracy: accuracy, "minY", file: file, line: line)
        XCTAssertEqual(a.width, b.width, accuracy: accuracy, "width", file: file, line: line)
        XCTAssertEqual(a.height, b.height, accuracy: accuracy, "height", file: file, line: line)
    }

    // MARK: - Mini and Tall

    func testMiniIsTheSlotExactly() {
        XCTAssertEqual(AppDockPlacementMath.sized(slot, size: .mini, tallHeight: 560), slot)
    }

    func testTallGrowsUpwardFromTheSlot() throws {
        let tall = AppDockPlacementMath.sized(slot, size: .tall, tallHeight: 560)
        let mini = try frame(slot)
        let grown = try frame(tall)
        let unit = slot.pointsPerUnit(contentHeight: content.height)
        XCTAssertEqual(grown.minY, mini.minY, accuracy: 1e-9, "bottom edge stays")
        XCTAssertEqual(grown.minX, mini.minX, accuracy: 1e-9, "left edge stays")
        XCTAssertEqual(grown.maxX, mini.maxX, accuracy: 1e-9, "same width")
        XCTAssertEqual(grown.height, 560 * unit, accuracy: 1e-9)
        XCTAssertEqual(tall.uiScale, slot.uiScale)
        XCTAssertEqual(tall.fontSize, slot.fontSize, "Tall only adds rows")
    }

    func testTallKeepsTheBottomEdgeForEveryAnchor() throws {
        for point in AppDockAnchorPoint.allCases {
            var anchored = slot
            anchored.point = point
            anchored.relativePoint = .center
            let mini = try frame(anchored)
            let grown = try frame(AppDockPlacementMath.sized(anchored, size: .tall, tallHeight: 600))
            XCTAssertEqual(grown.minY, mini.minY, accuracy: 1e-9, "\(point)")
            XCTAssertEqual(grown.minX, mini.minX, accuracy: 1e-9, "\(point)")
            XCTAssertGreaterThan(grown.height, mini.height, "\(point)")
        }
    }

    func testTallIsNeverShorterThanTheSlot() {
        XCTAssertEqual(AppDockPlacementMath.sized(slot, size: .tall, tallHeight: 200), slot)
        XCTAssertEqual(AppDockPlacementMath.sized(slot, size: .tall, tallHeight: 259), slot)
        XCTAssertEqual(AppDockPlacementMath.sized(slot, size: .tall, tallHeight: .nan), slot)
        XCTAssertEqual(AppDockPlacementMath.sized(slot, size: .tall, tallHeight: .infinity), slot)
    }

    func testSizeToggleAndNames() {
        XCTAssertEqual(AppDockPanelSize.mini.toggled, .tall)
        XCTAssertEqual(AppDockPanelSize.tall.toggled, .mini)
        XCTAssertEqual(AppDockPanelSize(name: " tall "), .tall)
        XCTAssertEqual(AppDockPanelSize(name: "MINI"), .mini)
        XCTAssertNil(AppDockPanelSize(name: "huge"))
        XCTAssertNil(AppDockPanelSize(name: ""))
    }

    // MARK: - Dragged offset

    func testOffsetIsInUnitsSoItFollowsTheWindow() throws {
        let offset = CGVector(dx: -300, dy: 200)
        let moved = AppDockPlacementMath.moved(slot, by: offset)
        XCTAssertEqual(moved.offset, CGVector(dx: -304, dy: 204))
        // The same offset on a window twice as big lands at the same place relative to the
        // window, as the slot does.
        let big = CGRect(x: 0, y: 0, width: content.width * 2, height: content.height * 2)
        let small = CGRect(x: 0, y: 0, width: content.width, height: content.height)
        let a = try frame(moved, in: small)
        let b = try frame(moved, in: big)
        XCTAssertEqual(b.minX / big.width, a.minX / small.width, accuracy: 1e-9)
        XCTAssertEqual(b.minY / big.height, a.minY / small.height, accuracy: 1e-9)
        XCTAssertEqual(b.width, a.width * 2, accuracy: 1e-9)
    }

    func testDragMovesByPointsOverScale() {
        let start = CGVector(dx: -10, dy: 5)
        let unit: CGFloat = 0.744
        let end = AppDockPlacementMath.dragged(from: start, by: CGVector(dx: -74.4, dy: 37.2), pointsPerUnit: unit)
        XCTAssertEqual(end.dx, -110, accuracy: 1e-9)
        XCTAssertEqual(end.dy, 55, accuracy: 1e-9)
        XCTAssertEqual(AppDockPlacementMath.dragged(from: start, by: CGVector(dx: 9, dy: 9), pointsPerUnit: 0), start)
        XCTAssertEqual(AppDockPlacementMath.dragged(from: start, by: CGVector(dx: 9, dy: 9), pointsPerUnit: .nan), start)
    }

    // MARK: - Kept inside the window

    func testClampLeavesAPanelInsideAlone() {
        XCTAssertEqual(AppDockPlacementMath.clampedOffset(.zero, slot: slot, contentRect: content), .zero)
        let inside = CGVector(dx: -400, dy: 300)
        let clamped = AppDockPlacementMath.clampedOffset(inside, slot: slot, contentRect: content)
        XCTAssertEqual(clamped.dx, inside.dx, accuracy: 1e-9)
        XCTAssertEqual(clamped.dy, inside.dy, accuracy: 1e-9)
    }

    func testClampStopsAtEveryEdge() throws {
        let far: CGFloat = 5_000
        for (offset, edge) in [(CGVector(dx: far, dy: 0), "right"),
                               (CGVector(dx: -far, dy: 0), "left"),
                               (CGVector(dx: 0, dy: far), "top"),
                               (CGVector(dx: 0, dy: -far), "bottom")] {
            let clamped = AppDockPlacementMath.clampedOffset(offset, slot: slot, contentRect: content)
            let f = try frame(AppDockPlacementMath.moved(slot, by: clamped))
            XCTAssertGreaterThanOrEqual(f.minX, content.minX - 1e-6, edge)
            XCTAssertLessThanOrEqual(f.maxX, content.maxX + 1e-6, edge)
            XCTAssertGreaterThanOrEqual(f.minY, content.minY - 1e-6, edge)
            XCTAssertLessThanOrEqual(f.maxY, content.maxY + 1e-6, edge)
            switch edge {
            case "right": XCTAssertEqual(f.maxX, content.maxX, accuracy: 1e-6)
            case "left": XCTAssertEqual(f.minX, content.minX, accuracy: 1e-6)
            case "top": XCTAssertEqual(f.maxY, content.maxY, accuracy: 1e-6)
            default: XCTAssertEqual(f.minY, content.minY, accuracy: 1e-6)
            }
        }
    }

    func testClampOnlyMovesTheAxisThatIsOut() {
        let clamped = AppDockPlacementMath.clampedOffset(CGVector(dx: 5_000, dy: 123), slot: slot, contentRect: content)
        XCTAssertEqual(clamped.dy, 123, accuracy: 1e-9)
        XCTAssertLessThan(clamped.dx, 5_000)
    }

    func testTallPanelMovedHighIsPushedDownToFit() throws {
        let tall = AppDockPlacementMath.sized(slot, size: .tall, tallHeight: 560)
        // An offset that fit the mini panel near the top does not fit the tall one.
        let nearTop = CGVector(dx: -200, dy: 900)
        let miniClamped = AppDockPlacementMath.clampedOffset(nearTop, slot: slot, contentRect: content)
        XCTAssertEqual(miniClamped.dy, 900, accuracy: 1e-9)
        let tallClamped = AppDockPlacementMath.clampedOffset(nearTop, slot: tall, contentRect: content)
        let f = try frame(AppDockPlacementMath.moved(tall, by: tallClamped))
        XCTAssertEqual(f.maxY, content.maxY, accuracy: 1e-6, "header at the top edge, not past it")
    }

    func testTooTallKeepsTheHeaderInside() throws {
        let huge = AppDockPlacementMath.sized(slot, size: .tall, tallHeight: 5_000)
        let clamped = AppDockPlacementMath.clampedOffset(.zero, slot: huge, contentRect: content)
        let f = try frame(AppDockPlacementMath.moved(huge, by: clamped))
        XCTAssertEqual(f.maxY, content.maxY, accuracy: 1e-6, "the top (header) stays in the window")
    }

    func testTooWideIsCentered() throws {
        let narrow = CGRect(x: 0, y: 0, width: 200, height: 907)
        let clamped = AppDockPlacementMath.clampedOffset(CGVector(dx: 50, dy: 0), slot: slot, contentRect: narrow)
        let f = try frame(AppDockPlacementMath.moved(slot, by: clamped), in: narrow)
        XCTAssertEqual(f.midX, narrow.midX, accuracy: 1e-6)
    }

    func testClampRejectsGarbage() {
        XCTAssertEqual(AppDockPlacementMath.clampedOffset(CGVector(dx: CGFloat.nan, dy: 1), slot: slot, contentRect: content), .zero)
        XCTAssertEqual(AppDockPlacementMath.clampedOffset(CGVector(dx: 1, dy: CGFloat.infinity), slot: slot, contentRect: content), .zero)
        let offset = CGVector(dx: 3, dy: 4)
        XCTAssertEqual(AppDockPlacementMath.clampedOffset(offset, slot: slot, contentRect: .zero), offset)
    }

    // MARK: - Snap back

    func testSnapDistanceIsInScreenPoints() {
        // 12 pt on screen: 20 units at 0.6 pt per unit, 10 units at 1.2.
        XCTAssertTrue(AppDockPlacementMath.snapsToSlot(CGVector(dx: 12, dy: 16), pointsPerUnit: 0.6))
        XCTAssertFalse(AppDockPlacementMath.snapsToSlot(CGVector(dx: 12, dy: 16.5), pointsPerUnit: 0.6))
        XCTAssertFalse(AppDockPlacementMath.snapsToSlot(CGVector(dx: 12, dy: 16), pointsPerUnit: 1.2))
        XCTAssertTrue(AppDockPlacementMath.snapsToSlot(.zero, pointsPerUnit: 0.6))
        XCTAssertFalse(AppDockPlacementMath.snapsToSlot(.zero, pointsPerUnit: 0))
    }

    func testIsMoved() {
        XCTAssertFalse(AppDockPlacement(size: .mini).isMoved)
        XCTAssertFalse(AppDockPlacement(size: .tall, offset: CGVector(dx: 0.004, dy: -0.004)).isMoved)
        XCTAssertTrue(AppDockPlacement(size: .mini, offset: CGVector(dx: 0, dy: -1)).isMoved)
    }

    // MARK: - Saved form

    func testPlistRoundTrip() {
        let p = AppDockPlacement(size: .tall, offset: CGVector(dx: -250.5, dy: 120))
        XCTAssertEqual(AppDockPlacement(plist: p.plist, fallback: AppDockPlacement(size: .mini)), p)
        // The defaults hand back NSNumbers in an NSDictionary.
        let bridged = NSDictionary(dictionary: p.plist) as? [String: Any]
        XCTAssertEqual(AppDockPlacement(plist: bridged, fallback: AppDockPlacement(size: .mini)), p)
    }

    func testMalformedSavedValuesFallBackFieldByField() {
        let fallback = AppDockPlacement(size: .tall)
        XCTAssertEqual(AppDockPlacement(plist: nil, fallback: fallback), fallback)
        XCTAssertEqual(AppDockPlacement(plist: "Tall", fallback: fallback), fallback)
        XCTAssertEqual(AppDockPlacement(plist: ["Size": "Giant", "X": 1, "Y": 2], fallback: fallback),
                       AppDockPlacement(size: .tall, offset: CGVector(dx: 1, dy: 2)))
        XCTAssertEqual(AppDockPlacement(plist: ["Size": "mini", "X": "1", "Y": 2], fallback: fallback),
                       AppDockPlacement(size: .mini), "an offset needs both numbers")
        XCTAssertEqual(AppDockPlacement(plist: ["Size": "Mini", "X": true, "Y": 2], fallback: fallback),
                       AppDockPlacement(size: .mini), "a Bool is not a coordinate")
        XCTAssertEqual(AppDockPlacement(plist: ["X": Double.nan, "Y": 2], fallback: fallback), fallback)
        XCTAssertEqual(AppDockPlacement(plist: ["X": 20_000, "Y": 2], fallback: fallback), fallback)
    }

    func testStoreKeepsEachProfileApart() throws {
        let suite = "AppDockPlacementTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
        }
        XCTAssertTrue(AppDockPlacementStore.userDefaultsKey.hasPrefix("NoSync"))
        XCTAssertEqual(AppDockPlacementStore.placement(forGuid: "a", defaultSize: .tall, defaults: defaults),
                       AppDockPlacement(size: .tall))
        let moved = AppDockPlacement(size: .mini, offset: CGVector(dx: -30, dy: 44))
        AppDockPlacementStore.save(moved, forGuid: "a", defaults: defaults)
        AppDockPlacementStore.save(AppDockPlacement(size: .tall), forGuid: "b", defaults: defaults)
        XCTAssertEqual(AppDockPlacementStore.placement(forGuid: "a", defaultSize: .tall, defaults: defaults), moved,
                       "a saved choice beats the profile's default size")
        XCTAssertEqual(AppDockPlacementStore.placement(forGuid: "b", defaultSize: .mini, defaults: defaults),
                       AppDockPlacement(size: .tall))
        XCTAssertEqual(AppDockPlacementStore.placement(forGuid: "c", defaultSize: .mini, defaults: defaults),
                       AppDockPlacement(size: .mini))
    }

    // MARK: - Profile keys

    func testTallHeightAndDefaultSizeKeys() throws {
        let base: [AnyHashable: Any] = [KEY_GUID: "g", KEY_NAME: "n", "Dock To App Bundle ID": "com.example.game"]
        let plain = try XCTUnwrap(AppDockSettings(profile: base))
        XCTAssertEqual(plain.tallHeight, AppDockSettings.defaultTallHeight)
        XCTAssertEqual(plain.tallHeight, 560)
        XCTAssertEqual(plain.defaultSize, .mini)

        let set = try XCTUnwrap(AppDockSettings(profile: base.merging(["Dock Tall Height": 480,
                                                                        "Dock Default Size": "Tall"]) { _, new in new }))
        XCTAssertEqual(set.tallHeight, 480)
        XCTAssertEqual(set.defaultSize, .tall)

        for bad: Any in [0, -10, 50_000, "tall", true] {
            let s = try XCTUnwrap(AppDockSettings(profile: base.merging(["Dock Tall Height": bad,
                                                                          "Dock Default Size": "huge"]) { _, new in new }))
            XCTAssertEqual(s.tallHeight, 560, "\(bad)")
            XCTAssertEqual(s.defaultSize, .mini)
        }
    }

    // MARK: - Header button geometry

    func testSizeButtonSitsInTheCorner() {
        let metrics = AppDockHeaderMetrics(terminalFontSize: 8.5, backingScale: 2)
        let bounds = CGRect(x: 0, y: 0, width: 281, height: metrics.height)
        let button = metrics.sizeButtonFrame(in: bounds)
        XCTAssertEqual(button.width, button.height, "square")
        XCTAssertEqual(bounds.maxX - button.maxX, button.minY - bounds.minY, accuracy: 1e-9, "as far from the right as from the bottom")
        XCTAssertEqual(bounds.maxY - button.maxY, button.minY - bounds.minY, accuracy: 0.5, "centered vertically")
        XCTAssertGreaterThanOrEqual(button.height, 10, "big enough to hit")
        for edge in [button.minX, button.minY, button.width] {
            XCTAssertEqual(edge * 2, (edge * 2).rounded(), "on device pixels")
        }
        let hit = metrics.sizeButtonHitFrame(in: bounds)
        XCTAssertTrue(hit.contains(button))
        XCTAssertEqual(hit.maxX, bounds.maxX)
        XCTAssertEqual(hit.height, bounds.height)
        XCTAssertLessThan(hit.width, bounds.width / 6, "the rest of the strip stays the handle")
    }

    // MARK: - Header gesture

    private func press(_ region: AppDockHeaderRegion, clicks: Int = 1,
                       path: [CGPoint] = [], releaseIn: AppDockHeaderRegion? = nil) -> (steps: [AppDockHeaderGesture.Step], outcome: AppDockHeaderGesture.Outcome) {
        var g = AppDockHeaderGesture()
        g.mouseDown(at: CGPoint(x: 100, y: 100), region: region, clickCount: clicks)
        var steps = [AppDockHeaderGesture.Step]()
        for p in path {
            steps += g.mouseDragged(to: p)
        }
        return (steps, g.mouseUp(in: releaseIn ?? region))
    }

    func testClickFocuses() {
        XCTAssertEqual(press(.handle).outcome, .focus)
        // A hand that wobbles less than the threshold is still a click.
        let wobble = press(.handle, path: [CGPoint(x: 101, y: 102), CGPoint(x: 102, y: 101)])
        XCTAssertEqual(wobble.steps, [])
        XCTAssertEqual(wobble.outcome, .focus)
    }

    func testDragNeverFocuses() {
        let r = press(.handle, path: [CGPoint(x: 102, y: 100), CGPoint(x: 104, y: 100), CGPoint(x: 140, y: 80)])
        XCTAssertEqual(r.steps, [.dragBegan, .dragMoved(CGVector(dx: 4, dy: 0)), .dragMoved(CGVector(dx: 40, dy: -20))])
        XCTAssertEqual(r.outcome, .dragEnded)
        // Released outside the header (the pointer outran the panel): still just the drag's end.
        XCTAssertEqual(press(.handle, path: [CGPoint(x: 300, y: 300)], releaseIn: nil).outcome, .dragEnded)
    }

    func testDragThresholdIsDistanceNotAxis() {
        // 2.5 + 2.5 diagonally is 3.54 pt: past the 3 pt threshold.
        let r = press(.handle, path: [CGPoint(x: 102.5, y: 102.5)])
        XCTAssertEqual(r.steps.first, .dragBegan)
        let exact = press(.handle, path: [CGPoint(x: 103, y: 100)])
        XCTAssertEqual(exact.steps, [], "exactly the threshold is still a click")
    }

    func testDoubleClickGoesBackToTheSlot() {
        XCTAssertEqual(press(.handle, clicks: 2).outcome, .backToSlot)
        XCTAssertEqual(press(.handle, clicks: 3).outcome, .backToSlot)
        XCTAssertEqual(press(.handle, clicks: 2, path: [CGPoint(x: 150, y: 100)]).outcome, .dragEnded,
                       "a double press that drags is a drag")
    }

    func testSizeButton() {
        XCTAssertEqual(press(.sizeButton).outcome, .toggleSize)
        XCTAssertEqual(press(.sizeButton, clicks: 2).outcome, .toggleSize, "each click toggles")
        XCTAssertEqual(press(.sizeButton, releaseIn: .handle).outcome, .none, "slid off the button: nothing")
        let dragged = press(.sizeButton, path: [CGPoint(x: 160, y: 140)])
        XCTAssertEqual(dragged.steps, [], "the button never moves the panel")
    }

    func testButtonDrawsPressedOnlyWhileHeldOverIt() {
        var g = AppDockHeaderGesture()
        XCTAssertFalse(g.showsButtonPressed(pointerRegion: .sizeButton))
        g.mouseDown(at: .zero, region: .sizeButton, clickCount: 1)
        XCTAssertTrue(g.showsButtonPressed(pointerRegion: .sizeButton))
        XCTAssertFalse(g.showsButtonPressed(pointerRegion: .handle))
        _ = g.mouseUp(in: .sizeButton)
        XCTAssertFalse(g.showsButtonPressed(pointerRegion: .sizeButton))
        g.mouseDown(at: .zero, region: .handle, clickCount: 1)
        XCTAssertFalse(g.showsButtonPressed(pointerRegion: .sizeButton))
    }

    func testReleaseWithoutPressDoesNothing() {
        var g = AppDockHeaderGesture()
        XCTAssertEqual(g.mouseDragged(to: CGPoint(x: 500, y: 500)), [])
        XCTAssertEqual(g.mouseUp(in: .handle), .none)
    }

    // MARK: - Header hint

    func testHint() {
        func hint(_ hover: AppDockHeaderRegion?, _ size: AppDockPanelSize = .mini,
                  moved: Bool = false, drag: AppDockDragFeedback = .none) -> AppDockHeaderHint {
            return AppDockHeaderHint.current(hover: hover, size: size, isMoved: moved, drag: drag)
        }
        XCTAssertEqual(hint(nil), .hotKey)
        XCTAssertEqual(hint(.handle), .hotKey, "in the slot the header keeps showing the hotkey")
        XCTAssertEqual(hint(.handle, moved: true), .doubleClickToSnapBack)
        XCTAssertEqual(hint(nil, moved: true), .hotKey)
        XCTAssertEqual(hint(.sizeButton, .mini), .growTaller)
        XCTAssertEqual(hint(.sizeButton, .tall, moved: true), .backToMini)
        XCTAssertEqual(hint(.handle, moved: true, drag: .away), .hotKey)
        XCTAssertEqual(hint(.handle, moved: true, drag: .nearSlot), .releaseToSnapBack)
        XCTAssertEqual(hint(.sizeButton, drag: .nearSlot), .releaseToSnapBack)
    }
}
