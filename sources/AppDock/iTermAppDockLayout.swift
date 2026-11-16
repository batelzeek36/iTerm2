//
//  iTermAppDockLayout.swift
//  iTerm2SharedARC
//
//  Zach's fork. Where an app-docked panel sits on its target window, and how big its text
//  is, in the target's own UI units. WoW's UI is 768 units tall at UI scale 1, whatever the
//  window size, so one unit is contentHeight * uiScale / 768 points. A panel measured in
//  those units keeps its place and proportions on the game's UI at every window size.
//
//  Everything here is pure: rectangles in, rectangles out, in Cocoa screen coordinates
//  (origin bottom left, y up), the same orientation as WoW's UI coordinates.
//

import CoreGraphics
import Foundation

enum AppDockAnchorPoint: String, CaseIterable {
    case topLeft = "TOPLEFT"
    case top = "TOP"
    case topRight = "TOPRIGHT"
    case left = "LEFT"
    case center = "CENTER"
    case right = "RIGHT"
    case bottomLeft = "BOTTOMLEFT"
    case bottom = "BOTTOM"
    case bottomRight = "BOTTOMRIGHT"

    // 0 = left/bottom edge, 0.5 = middle, 1 = right/top edge.
    var fraction: (x: CGFloat, y: CGFloat) {
        switch self {
        case .topLeft: return (0, 1)
        case .top: return (0.5, 1)
        case .topRight: return (1, 1)
        case .left: return (0, 0.5)
        case .center: return (0.5, 0.5)
        case .right: return (1, 0.5)
        case .bottomLeft: return (0, 0)
        case .bottom: return (0.5, 0)
        case .bottomRight: return (1, 0)
        }
    }

    func position(in rect: CGRect) -> CGPoint {
        let f = fraction
        return CGPoint(x: rect.minX + rect.width * f.x, y: rect.minY + rect.height * f.y)
    }
}

// The panel's placement in UI units, as an addon would describe a frame: `point` of the
// panel is placed at `relativePoint` of the target's content area, moved by `offset`.
struct AppDockLayout: Equatable {
    var point: AppDockAnchorPoint
    var relativePoint: AppDockAnchorPoint
    var offset: CGVector
    var size: CGSize
    var uiScale: CGFloat
    // Height of the UI in units at UI scale 1. 768 for World of Warcraft.
    var referenceHeight: CGFloat = 768
    // Size of the terminal text, in UI units.
    var fontSize: CGFloat

    // ElvUI's right chat panel with its defaults, scaled to the density of the approved comp
    // (2026-11-14): 14.75 units = 8.6 pt at a 708 pt tall window and UI scale 0.63.
    static let defaultFontSize: CGFloat = 14.75

    static let elvUIRightChatDefault = AppDockLayout(point: .bottomRight,
                                                     relativePoint: .bottomRight,
                                                     offset: CGVector(dx: -4, dy: 4),
                                                     size: CGSize(width: 412, height: 180 + 23),
                                                     uiScale: 0.64,
                                                     fontSize: defaultFontSize)

    var isValid: Bool {
        return size.width > 0 && size.height > 0 && uiScale > 0 && referenceHeight > 0 &&
            fontSize > 0 && offset.dx.isFinite && offset.dy.isFinite
    }

    // Points per UI unit for a target whose content area is `contentHeight` points tall.
    func pointsPerUnit(contentHeight: CGFloat) -> CGFloat {
        return contentHeight * uiScale / referenceHeight
    }

    // The panel's outer frame on a target whose content area is `contentRect`, before it is
    // snapped to device pixels. nil when the layout or the area is unusable.
    func frame(in contentRect: CGRect) -> CGRect? {
        guard isValid,
              contentRect.width > 0, contentRect.height > 0,
              contentRect.minX.isFinite, contentRect.minY.isFinite else {
            return nil
        }
        let unit = pointsPerUnit(contentHeight: contentRect.height)
        let width = size.width * unit
        let height = size.height * unit
        let anchor = relativePoint.position(in: contentRect)
        let target = CGPoint(x: anchor.x + offset.dx * unit,
                             y: anchor.y + offset.dy * unit)
        let f = point.fraction
        return CGRect(x: target.x - width * f.x, y: target.y - height * f.y, width: width, height: height)
    }
}

// The chrome drawn around the terminal, measured from the comp: the header strip is
// 1.95em tall in a font 1.12x the terminal font, with 1 pt black edges. The size button
// (Mini <-> Tall, 2026-11-15) is a square at the right end, as far from the right edge as
// from the top and bottom, like ElvUI's buttons tucked into a panel corner.
struct AppDockHeaderMetrics: Equatable {
    var height: CGFloat
    var fontSize: CGFloat
    var horizontalPadding: CGFloat
    var gap: CGFloat
    var dotDiameter: CGFloat
    var buttonSide: CGFloat
    var buttonInset: CGFloat
    // Between the hint and the size button.
    var hintGap: CGFloat

    init(terminalFontSize: CGFloat, backingScale: CGFloat) {
        fontSize = terminalFontSize * 1.12
        height = AppDockGeometry.snap(fontSize * 1.95, scale: backingScale)
        horizontalPadding = fontSize * 0.7
        gap = fontSize * 1.1
        dotDiameter = fontSize * 0.55
        buttonSide = AppDockGeometry.snap(height * 0.68, scale: backingScale)
        buttonInset = AppDockGeometry.snap((height - buttonSide) / 2, scale: backingScale)
        hintGap = fontSize * 0.6
    }

    // The drawn button, in the header strip's own coordinates.
    func sizeButtonFrame(in bounds: CGRect) -> CGRect {
        return CGRect(x: bounds.maxX - buttonInset - buttonSide,
                      y: bounds.minY + buttonInset,
                      width: buttonSide,
                      height: buttonSide)
    }

    // Where a press counts as the button: the full height of the strip from the right edge
    // to as far left of the drawn square as the square is from the edge, so the corner is
    // easy to hit and the rest of the strip stays the handle.
    func sizeButtonHitFrame(in bounds: CGRect) -> CGRect {
        let drawn = sizeButtonFrame(in: bounds)
        let minX = drawn.minX - buttonInset
        return CGRect(x: minX, y: bounds.minY, width: bounds.maxX - minX, height: bounds.height)
    }
}

struct AppDockGeometry: Equatable {
    // Outer edge of the panel, including its border.
    var panelFrame: CGRect
    // The terminal window: inside the border, below the header.
    var terminalFrame: CGRect
    // The header strip: inside the border, above the line under it. The only part of the
    // panel that takes a click while the terminal does not have the keyboard.
    var headerFrame: CGRect
    var header: AppDockHeaderMetrics
    // Terminal font size in points, in half-point steps.
    var fontSize: CGFloat
    var pointsPerUnit: CGFloat

    static let borderWidth: CGFloat = 1
    static let minimumFontSize: CGFloat = 6
    static let maximumFontSize: CGFloat = 36

    static func snap(_ value: CGFloat, scale: CGFloat) -> CGFloat {
        let s = max(1, scale)
        return (value * s).rounded() / s
    }

    // Returns nil when the content area is too small to hold a panel.
    init?(layout: AppDockLayout, contentRect: CGRect, backingScale: CGFloat) {
        guard let frame = layout.frame(in: contentRect) else {
            return nil
        }
        let unit = layout.pointsPerUnit(contentHeight: contentRect.height)
        let minX = Self.snap(frame.minX, scale: backingScale)
        let minY = Self.snap(frame.minY, scale: backingScale)
        let maxX = Self.snap(frame.maxX, scale: backingScale)
        let maxY = Self.snap(frame.maxY, scale: backingScale)
        panelFrame = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)

        let rawFont = layout.fontSize * unit
        fontSize = min(Self.maximumFontSize, max(Self.minimumFontSize, (rawFont * 2).rounded() / 2))
        pointsPerUnit = unit
        header = AppDockHeaderMetrics(terminalFontSize: fontSize, backingScale: backingScale)

        let b = Self.borderWidth
        let top = b + header.height + b
        terminalFrame = CGRect(x: panelFrame.minX + b,
                               y: panelFrame.minY + b,
                               width: panelFrame.width - 2 * b,
                               height: panelFrame.height - b - top)
        headerFrame = CGRect(x: panelFrame.minX + b,
                             y: panelFrame.maxY - b - header.height,
                             width: panelFrame.width - 2 * b,
                             height: header.height)
        guard terminalFrame.width >= 40, terminalFrame.height >= 20 else {
            return nil
        }
    }
}
