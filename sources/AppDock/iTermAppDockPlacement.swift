//
//  iTermAppDockPlacement.swift
//  iTerm2SharedARC
//
//  Zach's fork. What the user chose for an app-docked panel on top of its slot: Mini (the
//  slot exactly) or Tall (the slot grown upward), and where he dragged it. Everything is in
//  the target's UI units, so a tall or moved panel follows the window's moves, resizes and UI
//  scale exactly as the slot does. Pure: rectangles and numbers only (AppDockPlacementStore
//  keeps the choice in the user defaults).
//

import CoreGraphics
import Foundation

enum AppDockPanelSize: String, CaseIterable {
    // The slot as the profile (or ElvUI) places it.
    case mini = "Mini"
    // The slot's anchor, width and bottom edge, grown upward to the profile's tall height.
    case tall = "Tall"

    var toggled: AppDockPanelSize {
        return self == .mini ? .tall : .mini
    }

    // "Mini" / "tall" / " TALL " as written in a profile or saved by an older build.
    init?(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let match = Self.allCases.first(where: { $0.rawValue.lowercased() == trimmed }) else {
            return nil
        }
        self = match
    }
}

struct AppDockPlacement: Equatable {
    var size: AppDockPanelSize
    // Added to the slot's offset, in UI units. Zero means the panel is in its slot.
    var offset: CGVector

    init(size: AppDockPanelSize, offset: CGVector = .zero) {
        self.size = size
        self.offset = offset
    }

    // Saved offsets are doubles; anything this close to zero is the slot.
    static let inSlotTolerance: CGFloat = 0.01
    // A saved offset beyond this many units is not a place on any window; it is ignored.
    static let maximumOffset: CGFloat = 10_000

    var isMoved: Bool {
        return abs(offset.dx) > Self.inSlotTolerance || abs(offset.dy) > Self.inSlotTolerance
    }

    // MARK: - Saved form

    static let sizeKey = "Size"
    static let xKey = "X"
    static let yKey = "Y"

    var plist: [String: Any] {
        return [Self.sizeKey: size.rawValue,
                Self.xKey: Double(offset.dx),
                Self.yKey: Double(offset.dy)]
    }

    // A placement read back from the user defaults. Each field that is missing or malformed
    // takes its value from `fallback`; an offset needs both coordinates to count.
    init(plist value: Any?, fallback: AppDockPlacement) {
        self = fallback
        guard let dict = value as? [String: Any] else {
            return
        }
        if let name = dict[Self.sizeKey] as? String, let size = AppDockPanelSize(name: name) {
            self.size = size
        }
        if let x = Self.coordinate(dict[Self.xKey]), let y = Self.coordinate(dict[Self.yKey]) {
            offset = CGVector(dx: x, dy: y)
        }
    }

    private static func coordinate(_ value: Any?) -> CGFloat? {
        guard let n = value as? NSNumber, !(value is Bool) else {
            return nil
        }
        let d = n.doubleValue
        guard d.isFinite, abs(d) <= Double(maximumOffset) else {
            return nil
        }
        return CGFloat(d)
    }
}

enum AppDockPlacementMath {
    // A drop this close to the slot, in points on screen, puts the panel back in it.
    static let snapDistance: CGFloat = 12

    // The slot at a size. Tall keeps the slot's anchor, width and bottom edge and grows upward
    // to `tallHeight` units; it is never shorter than the slot itself, so Tall only adds rows.
    static func sized(_ slot: AppDockLayout, size: AppDockPanelSize, tallHeight: CGFloat) -> AppDockLayout {
        guard size == .tall, tallHeight.isFinite, tallHeight > slot.size.height else {
            return slot
        }
        var result = slot
        // The anchored point sits at `fraction.y` of the panel's height: move it up by that
        // share of the growth and the bottom edge stays put.
        result.offset.dy += (tallHeight - slot.size.height) * slot.point.fraction.y
        result.size.height = tallHeight
        return result
    }

    static func moved(_ layout: AppDockLayout, by offset: CGVector) -> AppDockLayout {
        var result = layout
        result.offset.dx += offset.dx
        result.offset.dy += offset.dy
        return result
    }

    // `offset`, changed as little as possible so the panel stays inside the target's content
    // area: the whole panel when it fits, else its top edge (the header) inside and the panel
    // centered across. The header can never leave the window.
    static func clampedOffset(_ offset: CGVector, slot: AppDockLayout, contentRect: CGRect) -> CGVector {
        guard offset.dx.isFinite, offset.dy.isFinite else {
            return .zero
        }
        let unit = slot.pointsPerUnit(contentHeight: contentRect.height)
        guard unit > 0, unit.isFinite, let frame = moved(slot, by: offset).frame(in: contentRect) else {
            return offset
        }
        let x = fit(frame.minX, length: frame.width, low: contentRect.minX, high: contentRect.maxX, overflow: .center)
        let y = fit(frame.minY, length: frame.height, low: contentRect.minY, high: contentRect.maxY, overflow: .keepHigh)
        return CGVector(dx: offset.dx + (x - frame.minX) / unit,
                        dy: offset.dy + (y - frame.minY) / unit)
    }

    private enum Overflow {
        case center
        case keepHigh
    }

    // Where a span of `length` starting at `start` goes to lie within [low, high].
    private static func fit(_ start: CGFloat, length: CGFloat, low: CGFloat, high: CGFloat, overflow: Overflow) -> CGFloat {
        guard length <= high - low else {
            switch overflow {
            case .center:
                return low + (high - low - length) / 2
            case .keepHigh:
                return high - length
            }
        }
        return min(max(start, low), high - length)
    }

    // Dragging: the offset after the pointer moved `delta` points from where the drag began,
    // when the panel was at `start`.
    static func dragged(from start: CGVector, by delta: CGVector, pointsPerUnit: CGFloat) -> CGVector {
        guard pointsPerUnit > 0, pointsPerUnit.isFinite else {
            return start
        }
        return CGVector(dx: start.dx + delta.dx / pointsPerUnit,
                        dy: start.dy + delta.dy / pointsPerUnit)
    }

    // A panel at `offset` is close enough to its slot to snap into it when dropped.
    static func snapsToSlot(_ offset: CGVector, pointsPerUnit: CGFloat) -> Bool {
        guard pointsPerUnit > 0, pointsPerUnit.isFinite else {
            return false
        }
        return hypot(offset.dx, offset.dy) * pointsPerUnit <= snapDistance
    }
}
