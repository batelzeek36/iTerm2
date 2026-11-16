//
//  AppDockPlacementTests.swift
//  ModernTests
//
//  The Mini/Tall size button and dragging of app-docked panels (Zach's fork, sources/AppDock,
//  2026-11-15): the tall layout, the dragged offset in UI units, keeping the panel inside the
//  window, snapping back, the saved form, what a press on the header means and what its hint
//  says. The slot is ElvUI's right chat as Zach has it (472 x 259 units, BOTTOMRIGHT -4,4 at
//  UI scale 0.63). Also the feedback while dragging: the slot outline never draws on the
//  panel and the panel's own edge lights in snap range, and header text cut with an ellipsis.
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

    // MARK: - Snap range: nothing crosses the panel

    // Rectangles that each lie in `rect`, overlap neither `cover` nor each other, and add up
    // to all of `rect` that `cover` leaves showing.
    private func assertUncovered(_ rect: CGRect, by cover: CGRect,
                                 file: StaticString = #filePath, line: UInt = #line) {
        let pieces = AppDockPlacementMath.uncovered(rect, by: cover)
        let area = { (r: CGRect) -> CGFloat in r.isNull ? 0 : r.width * r.height }
        for (i, piece) in pieces.enumerated() {
            XCTAssertGreaterThan(area(piece), 0, "no empty pieces", file: file, line: line)
            XCTAssertEqual(area(piece.intersection(rect)), area(piece), accuracy: 1e-9, "inside the rect", file: file, line: line)
            XCTAssertEqual(area(piece.intersection(cover)), 0, accuracy: 1e-9, "never on the cover: \(piece)", file: file, line: line)
            for other in pieces[(i + 1)...] {
                XCTAssertEqual(area(piece.intersection(other)), 0, accuracy: 1e-9, "pieces apart", file: file, line: line)
            }
        }
        let shown = area(rect) - area(rect.intersection(cover))
        XCTAssertEqual(pieces.map(area).reduce(0, +), shown, accuracy: 1e-6, "all that shows", file: file, line: line)
    }

    func testUncoveredPartsNeverTouchThePanel() {
        let rect = CGRect(x: 0, y: 0, width: 351, height: 416.5)
        let offsets: [CGVector] = [
            CGVector(dx: 0, dy: 9.5),     // 9.7 pt up, as the evaluator saw it (snapped)
            CGVector(dx: -3, dy: 9),      // the Mini near-up case
            CGVector(dx: -0.5, dy: 1.5),  // nearly home
            CGVector(dx: 9.5, dy: 0),
            CGVector(dx: -6.5, dy: -5),
            CGVector(dx: 0, dy: 0),       // home: nothing shows
            CGVector(dx: -60, dy: 40),    // away, overlapping
            CGVector(dx: -500, dy: 300),  // away, clear of it
        ]
        for d in offsets {
            assertUncovered(rect, by: rect.offsetBy(dx: d.dx, dy: d.dy))
        }
        assertUncovered(rect, by: rect.insetBy(dx: 40, dy: 40))
        assertUncovered(rect, by: rect.insetBy(dx: -40, dy: -40))
        assertUncovered(rect, by: CGRect(x: 100, y: -50, width: 20, height: 600))
        XCTAssertEqual(AppDockPlacementMath.uncovered(rect, by: rect), [])
        XCTAssertEqual(AppDockPlacementMath.uncovered(rect, by: rect.insetBy(dx: -1, dy: -1)), [])
        XCTAssertEqual(AppDockPlacementMath.uncovered(rect, by: rect.offsetBy(dx: 400, dy: 0)), [rect])
        XCTAssertEqual(AppDockPlacementMath.uncovered(rect, by: .null), [rect])
        XCTAssertEqual(AppDockPlacementMath.uncovered(rect, by: rect.offsetBy(dx: 0, dy: 9.5)),
                       [CGRect(x: 0, y: 0, width: 351, height: 9.5)],
                       "panel lifted straight up: only the band under it shows")
    }

    private let accent = AppDockRGBA(red: 0x3f, green: 0xc7, blue: 0xeb, alpha: 255)

    private var dockColors: AppDockSettings.Colors {
        var colors = AppDockSettings.Colors()
        colors.accent = accent
        return colors
    }

    // `view` drawn into a fresh 2x bitmap, the way a Retina screen shows it.
    private func draw(_ view: NSView) throws -> NSBitmapImageRep {
        let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
                                                 pixelsWide: Int((view.bounds.width * 2).rounded()),
                                                 pixelsHigh: Int((view.bounds.height * 2).rounded()),
                                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)?
            .retagging(with: .sRGB))
        rep.size = view.bounds.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    // Pixels of `rep` whose center lies in `rect` (view points, origin bottom left) and whose
    // alpha passes `test`.
    private func count(_ rep: NSBitmapImageRep, in rect: CGRect, where test: (UInt8) -> Bool) -> Int {
        guard let data = rep.bitmapData else {
            return -1
        }
        var n = 0
        let height = rep.size.height
        for py in 0..<rep.pixelsHigh {
            let y = height - (CGFloat(py) + 0.5) / 2
            guard y > rect.minY, y < rect.maxY else {
                continue
            }
            for px in 0..<rep.pixelsWide {
                let x = (CGFloat(px) + 0.5) / 2
                guard x > rect.minX, x < rect.maxX else {
                    continue
                }
                if test(data[py * rep.bytesPerRow + px * 4 + 3]) {
                    n += 1
                }
            }
        }
        return n
    }

    // The slot and the dragged panel as the controller computes them: frames snapped to
    // device pixels, the cover in the outline's own coordinates.
    private func slotAndCover(_ size: AppDockPanelSize, offset: CGVector) throws -> (bounds: CGRect, cover: CGRect, header: AppDockHeaderMetrics) {
        let sized = AppDockPlacementMath.sized(slot, size: size, tallHeight: 560)
        let home = try XCTUnwrap(AppDockGeometry(layout: sized, contentRect: content, backingScale: 2))
        let shown = AppDockPlacementMath.clampedOffset(offset, slot: sized, contentRect: content)
        let panel = try XCTUnwrap(AppDockGeometry(layout: AppDockPlacementMath.moved(sized, by: shown),
                                                  contentRect: content, backingScale: 2))
        let cover = panel.panelFrame.offsetBy(dx: -home.panelFrame.minX, dy: -home.panelFrame.minY)
        return (CGRect(origin: .zero, size: home.panelFrame.size), cover, home.header)
    }

    private func outline(_ bounds: CGRect, near: Bool, cover: CGRect?, fontSize: CGFloat) -> AppDockSlotOutlineView {
        let view = AppDockSlotOutlineView(frame: bounds)
        view.outline = AppDockSlotOutlineStyle(colors: dockColors, fontSize: fontSize, nearSlot: near, cover: cover)
        return view
    }

    func testSlotOutlineNeverDrawsOnThePanel() throws {
        // Offsets in UI units (0.744 pt each here): the evaluator's 9.7 pt up, the Mini near-up
        // case, 1-2 pt from home, sideways, exactly home, and away while still overlapping.
        let cases: [(AppDockPanelSize, CGVector, Bool)] = [
            (.tall, CGVector(dx: 0, dy: 13), true),
            (.mini, CGVector(dx: -4, dy: 12), true),
            (.tall, CGVector(dx: -1, dy: 2), true),
            (.mini, CGVector(dx: -13, dy: 0), true),
            (.tall, CGVector(dx: -9, dy: 7), true),
            (.mini, .zero, true),
            (.tall, CGVector(dx: -60, dy: 40), false),
            (.mini, CGVector(dx: -200, dy: 100), false),
        ]
        for (size, offset, near) in cases {
            let (bounds, cover, header) = try slotAndCover(size, offset: offset)
            XCTAssertEqual(AppDockPlacementMath.snapsToSlot(offset, pointsPerUnit: slot.pointsPerUnit(contentHeight: content.height)),
                           near, "\(offset) is \(near ? "in" : "out of") snap range")
            let rep = try draw(outline(bounds, near: near, cover: cover, fontSize: header.fontSize))
            XCTAssertEqual(count(rep, in: cover, where: { $0 > 0 }), 0, "\(size) \(offset): a pixel on the panel")
            let showing = AppDockPlacementMath.uncovered(bounds, by: cover)
            let drawn = count(rep, in: bounds, where: { $0 > 0 })
            if showing.isEmpty {
                XCTAssertEqual(drawn, 0, "home: the panel hides the slot entirely")
            } else {
                XCTAssertGreaterThan(drawn, 0, "\(size) \(offset): the slot still shows beside the panel")
            }
        }
    }

    func testSlotOutlineAwayFromThePanelLooksAsBefore() throws {
        let (bounds, cover, header) = try slotAndCover(.tall, offset: CGVector(dx: -560, dy: 130))
        XCTAssertFalse(cover.intersects(bounds))
        let withCover = try draw(outline(bounds, near: false, cover: cover, fontSize: header.fontSize))
        let without = try draw(outline(bounds, near: false, cover: nil, fontSize: header.fontSize))
        XCTAssertEqual(withCover.tiffRepresentation, without.tiffRepresentation)
    }

    func testSnapBackLabelIsWholeOrHidden() throws {
        let (bounds, _, header) = try slotAndCover(.mini, offset: .zero)
        // Opaque pixels well inside the edges are the label's (the box itself is dim).
        let middle = bounds.insetBy(dx: 8, dy: 8)
        let opaque = { (a: UInt8) -> Bool in a > 230 }
        let clear = try draw(outline(bounds, near: false, cover: nil, fontSize: header.fontSize))
        XCTAssertGreaterThan(count(clear, in: middle, where: opaque), 20, "label drawn when nothing covers it")
        // The panel over the label's left half: none of it may stick out on the right.
        let halfCover = CGRect(x: -400, y: -400, width: 400 + bounds.midX, height: 800)
        let half = try draw(outline(bounds, near: false, cover: halfCover, fontSize: header.fontSize))
        XCTAssertEqual(count(half, in: middle, where: opaque), 0)
        // Near the slot there is no label at all.
        let near = try draw(outline(bounds, near: true, cover: nil, fontSize: header.fontSize))
        XCTAssertEqual(count(near, in: middle, where: opaque), 0)
    }

    func testPanelEdgeLightsOnlyInSnapRange() throws {
        var style = AppDockChromeStyle(title: "Claude", subtitle: "wow-forever", hotKeyHint: "⌃⌥⌘C",
                                       colors: dockColors, backdrop: AppDockRGBA(red: 6, green: 6, blue: 7, alpha: 153))
        XCTAssertNil(style.edgeAccent)
        style.drag = .away
        XCTAssertNil(style.edgeAccent, "away from the slot the edge stays black")
        style.drag = .nearSlot
        XCTAssertEqual(style.edgeAccent, accent)

        let edge = AppDockEdgeView(frame: CGRect(x: 0, y: 0, width: 120, height: 80))
        edge.header = AppDockHeaderMetrics(terminalFontSize: 8.5, backingScale: 2)
        // The left edge, halfway up, against a plain fill of the color through the same bitmap.
        func outerPixel(_ view: NSView) throws -> [CGFloat] {
            let rep = try draw(view)
            let c = try XCTUnwrap(rep.colorAt(x: 0, y: rep.pixelsHigh / 2))
            return [c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent]
        }
        func assertPixel(_ actual: [CGFloat], _ color: NSColor, _ message: String,
                         file: StaticString = #filePath, line: UInt = #line) throws {
            let swatch = AppDockSwatchView(frame: edge.frame, color: color)
            for (a, e) in zip(actual, try outerPixel(swatch)) {
                XCTAssertEqual(a, e, accuracy: 0.01, message, file: file, line: line)
            }
        }
        try assertPixel(try outerPixel(edge), .black, "black edge at rest")
        edge.accent = style.edgeAccent
        try assertPixel(try outerPixel(edge), accent.nsColor, "accent edge in snap range")
        edge.accent = nil
        try assertPixel(try outerPixel(edge), .black, "black again once out of range")
    }

    // MARK: - Header text fit

    func testTextFitCutsWithAnEllipsis() {
        // One point per character, the ellipsis included.
        let measure = { (s: String) -> CGFloat in CGFloat(s.count) }
        func fit(_ text: String, _ width: CGFloat) -> String {
            return AppDockTextFit.fitted(text, width: width, measure: measure)
        }
        XCTAssertEqual(fit("wow-forever", 20), "wow-forever")
        XCTAssertEqual(fit("wow-forever", 11), "wow-forever", "an exact fit is whole")
        XCTAssertEqual(fit("wow-forever-addons", 8), "wow-for…")
        XCTAssertEqual(fit("ab cd", 4), "ab…", "no space before the ellipsis")
        XCTAssertEqual(fit("abc", 2), "a…")
        XCTAssertEqual(fit("abc", 1), "", "a lone ellipsis is not shown")
        XCTAssertEqual(fit("abc", 0), "")
        XCTAssertEqual(fit("abc", -5), "")
        XCTAssertEqual(fit("abc", .nan), "")
        XCTAssertEqual(fit("", 10), "")
        for width in stride(from: CGFloat(0), through: 20, by: 0.5) {
            let s = fit("wow-forever-addons", width)
            XCTAssertLessThanOrEqual(measure(s), width)
            XCTAssertTrue(s.isEmpty || s == "wow-forever-addons" ||
                          ("wow-forever-addons".hasPrefix(String(s.dropLast())) && s.hasSuffix("…")), s)
        }
    }

    func testTextFitWithTheHeaderFont() {
        let font = AppDockHeaderView.headerFont(size: 9.5)
        let width = { (s: String) -> CGFloat in NSAttributedString(string: s, attributes: [.font: font]).size().width }
        let long = "wow-forever-addons-buffcard-rework"
        let room = width(long) * 0.6
        let shown = AppDockTextFit.fitted(long, width: room, measure: width)
        XCTAssertTrue(shown.hasSuffix("…"), shown)
        XCTAssertLessThanOrEqual(width(shown), room)
        let next = String(long.prefix(shown.count)) + "…"
        XCTAssertGreaterThan(width(next), room, "as long as fits: one more letter would not")
    }
}

// A plain fill, for comparing a drawn pixel with its color through the same bitmap.
private final class AppDockSwatchView: NSView {
    private let color: NSColor

    init(frame: NSRect, color: NSColor) {
        self.color = color
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        it_fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        color.set()
        bounds.fill()
    }
}
