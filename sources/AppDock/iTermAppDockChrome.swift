//
//  iTermAppDockChrome.swift
//  iTerm2SharedARC
//
//  Zach's fork. The frame around an app-docked terminal, drawn like an ElvUI panel (approved
//  comp 2026-11-14): a 1 pt black edge with a faint inner highlight, and a header strip like
//  an ElvUI chat tab (AppDockHeaderView). No title bar, no shadow, no rounded corners.
//
//  Borderless panels laid over the terminal window:
//    - the edge panel covers the whole panel and draws the edges; it never takes a click, so
//      a click anywhere outside the header reaches whatever is under it (the game, unless the
//      terminal has the keyboard and takes the click itself);
//    - the header panel covers only the header strip: click = focus, drag = move, and the
//      size button at its right end;
//    - while the panel is dragged, the slot panel outlines where it lives, like an ElvUI mover
//      (not a child window: it stays put while the panel moves). It sits under the panel and
//      never draws where the panel is, so nothing of it crosses the panel's text; within snap
//      range the panel's own edge turns the accent instead.
//

import AppKit

struct AppDockChromeStyle: Equatable {
    var title: String
    var subtitle: String
    var hotKeyHint: String
    var colors: AppDockSettings.Colors
    // The terminal's own backdrop (background color at its transparency), repeated under the
    // header, which the terminal window does not cover.
    var backdrop: AppDockRGBA
    var size: AppDockPanelSize = .mini
    // Dragged out of its slot (and not put back).
    var isMoved = false
    var drag: AppDockDragFeedback = .none

    // The panel's outer edge: the accent while a drop would snap it back into its slot (the
    // panel itself says so; the slot outline stays under it), else nil for the black edge.
    var edgeAccent: AppDockRGBA? {
        return drag == .nearSlot ? colors.accent : nil
    }
}

enum AppDockDrawing {
    // A frame `width` thick just inside `rect`.
    static func strokeInside(_ rect: NSRect, width: CGFloat, color: NSColor) {
        color.set()
        NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: width).fill(using: .sourceOver)
        NSRect(x: rect.minX, y: rect.maxY - width, width: rect.width, height: width).fill(using: .sourceOver)
        NSRect(x: rect.minX, y: rect.minY + width, width: width, height: rect.height - 2 * width).fill(using: .sourceOver)
        NSRect(x: rect.maxX - width, y: rect.minY + width, width: width, height: rect.height - 2 * width).fill(using: .sourceOver)
    }
}

// A borderless, non-activating, shadowless child panel that is never key or main.
final class AppDockChromePanel: NSPanel {
    init(contentView view: NSView, takesClicks: Bool) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isMovable = false
        isExcludedFromWindowsMenu = true
        animationBehavior = .none
        ignoresMouseEvents = !takesClicks
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// The outer edge, the faint inner highlight and the line under the header.
final class AppDockEdgeView: NSView {
    var header: AppDockHeaderMetrics? {
        didSet {
            if header != oldValue {
                needsDisplay = true
            }
        }
    }
    // Set: the outer edge in this color instead of black (AppDockChromeStyle.edgeAccent).
    var accent: AppDockRGBA? {
        didSet {
            if accent != oldValue {
                needsDisplay = true
            }
        }
    }

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        bounds.fill(using: .copy)
        guard let header else {
            return
        }
        let b = AppDockGeometry.borderWidth
        let headerBottom = bounds.maxY - b - header.height
        NSColor.black.set()
        NSRect(x: bounds.minX + b, y: headerBottom - b, width: bounds.width - 2 * b, height: b).fill()
        // Lit like ElvUI's skinned frames on hover: the 1 pt edge itself turns the class
        // color, the inner highlight brightens a touch with it.
        AppDockDrawing.strokeInside(bounds, width: b, color: accent?.nsColor ?? .black)
        AppDockDrawing.strokeInside(bounds.insetBy(dx: b, dy: b), width: b,
                                    color: NSColor(white: 1, alpha: accent == nil ? 0.07 : 0.12))
    }
}

// How the slot outline looks while the panel is dragged.
struct AppDockSlotOutlineStyle: Equatable {
    var colors: AppDockSettings.Colors
    // The header's font size, for the label.
    var fontSize: CGFloat
    // Close enough that a drop snaps the panel back.
    var nearSlot: Bool
    // The dragged panel, in the outline's own coordinates: nothing is drawn there.
    var cover: CGRect?
}

// The panel's home while it is dragged, drawn like an ElvUI mover in /moveui: a dim box with
// a black edge and its name in the middle. It lies under the panel and is drawn only where
// the panel does not cover it (the panel is see-through), so it never crosses the panel's
// text. Close enough to snap, its edge goes full accent: with the panel's own accent edge
// (AppDockEdgeView) the strip still showing between them is the landing spot.
final class AppDockSlotOutlineView: NSView {
    var outline: AppDockSlotOutlineStyle? {
        didSet {
            if outline != oldValue {
                needsDisplay = true
            }
        }
    }

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        bounds.fill(using: .copy)
        guard let outline else {
            return
        }
        let b = AppDockGeometry.borderWidth
        let accent = outline.colors.accent.nsColor
        let visible = outline.cover.map { AppDockPlacementMath.uncovered(bounds, by: $0) } ?? [bounds]
        guard !visible.isEmpty else {
            return
        }
        NSGraphicsContext.saveGraphicsState()
        defer {
            NSGraphicsContext.restoreGraphicsState()
        }
        let clip = NSBezierPath()
        visible.forEach { clip.appendRect($0) }
        clip.addClip()

        NSColor(white: 0, alpha: 0.46).set()
        bounds.fill(using: .sourceOver)
        accent.withAlphaComponent(0.05).set()
        bounds.fill(using: .sourceOver)
        AppDockDrawing.strokeInside(bounds, width: b, color: .black)
        AppDockDrawing.strokeInside(bounds.insetBy(dx: b, dy: b), width: b,
                                    color: outline.nearSlot ? accent : accent.withAlphaComponent(0.6))
        if outline.nearSlot {
            return
        }

        let label = String(localized: "AppDock.SlotOutline.SnapBackHere",
                           defaultValue: "Snap back here",
                           comment: "Label in the middle of the outline that shows where a panel docked to another app’s window (Claude Dock) usually lives, while the user drags the panel elsewhere. Dropping the panel on it puts it back.")
        let font = AppDockHeaderView.headerFont(size: outline.fontSize)
        let text = NSAttributedString(string: label,
                                      attributes: [.font: font, .foregroundColor: outline.colors.text.nsColor])
        let size = text.size()
        let origin = NSPoint(x: bounds.midX - size.width / 2,
                             y: bounds.midY - (font.ascender + font.descender) / 2 + font.descender)
        // Whole or not at all: a name half under the panel reads as a glitch.
        let textRect = NSRect(origin: origin, size: size)
        guard size.width < bounds.width - 4 * b, !(outline.cover?.intersects(textRect) ?? false) else {
            return
        }
        text.draw(at: origin)
    }
}

// The chrome panels of one docked terminal, moved and shown together.
final class AppDockChrome {
    let edgeView = AppDockEdgeView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    let headerView = AppDockHeaderView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    let slotOutlineView = AppDockSlotOutlineView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    private let edgePanel: AppDockChromePanel
    private let headerPanel: AppDockChromePanel
    private let slotOutlinePanel: AppDockChromePanel

    init() {
        edgePanel = AppDockChromePanel(contentView: edgeView, takesClicks: false)
        headerPanel = AppDockChromePanel(contentView: headerView, takesClicks: true)
        slotOutlinePanel = AppDockChromePanel(contentView: slotOutlineView, takesClicks: false)
    }

    var level: NSWindow.Level {
        get { edgePanel.level }
        set {
            edgePanel.level = newValue
            headerPanel.level = newValue
            slotOutlinePanel.level = newValue
        }
    }

    var isVisible: Bool {
        return edgePanel.isVisible || headerPanel.isVisible
    }

    func apply(geometry g: AppDockGeometry, style: AppDockChromeStyle) {
        if edgePanel.frame != g.panelFrame {
            edgePanel.setFrame(g.panelFrame, display: true)
        }
        if headerPanel.frame != g.headerFrame {
            headerPanel.setFrame(g.headerFrame, display: true)
        }
        edgeView.header = g.header
        edgeView.accent = style.edgeAccent
        headerView.header = g.header
        headerView.style = style
    }

    // Header first, then the edges above it, so the inner highlight runs over the header too.
    func attach(to window: NSWindow) {
        for panel in [headerPanel, edgePanel] {
            if panel.parent !== window {
                panel.parent?.removeChildWindow(panel)
                window.addChildWindow(panel, ordered: .above)
            }
            if !panel.isVisible {
                panel.orderFrontRegardless()
            }
        }
    }

    func detach() {
        hideSlotOutline()
        for panel in [edgePanel, headerPanel] {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }

    // While the panel in `window` is dragged: its slot at `frame`. The outline always sits
    // under the panel, near the slot or not, and its style leaves out the panel's own frame
    // (AppDockSlotOutlineStyle.cover), so nothing of it is ever drawn across the panel.
    func showSlotOutline(frame: CGRect, style: AppDockSlotOutlineStyle, panelWindow window: NSWindow) {
        if slotOutlinePanel.frame != frame {
            slotOutlinePanel.setFrame(frame, display: true)
        }
        slotOutlineView.outline = style
        guard !slotOutlinePanel.isVisible else {
            return
        }
        slotOutlinePanel.level = level
        slotOutlinePanel.order(.below, relativeTo: window.windowNumber)
    }

    func hideSlotOutline() {
        slotOutlinePanel.orderOut(nil)
        slotOutlineView.outline = nil
    }
}

enum AppDockHotKeyHint {
    // "⌃⌥⌘C": modifiers in the order macOS menus use, then the key.
    static func string(modifiers: NSEvent.ModifierFlags, key: String) -> String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + key.uppercased()
    }
}
