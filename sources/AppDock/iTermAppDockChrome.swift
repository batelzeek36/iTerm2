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
//      (not a child window: it stays put while the panel moves).
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
        AppDockDrawing.strokeInside(bounds, width: b, color: .black)
        AppDockDrawing.strokeInside(bounds.insetBy(dx: b, dy: b), width: b, color: NSColor(white: 1, alpha: 0.07))
    }
}

// How the slot outline looks while the panel is dragged.
struct AppDockSlotOutlineStyle: Equatable {
    var colors: AppDockSettings.Colors
    // The header's font size, for the label.
    var fontSize: CGFloat
    // Close enough that a drop snaps the panel back.
    var nearSlot: Bool
}

// The panel's home while it is dragged, drawn like an ElvUI mover in /moveui: a dim box with
// a black edge and its name in the middle. When the panel comes close enough to snap, the
// outline moves above the panel and turns into a bare accent frame, so the exact landing spot
// shows over the panel's own text.
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
        if outline.nearSlot {
            AppDockDrawing.strokeInside(bounds, width: b, color: .black)
            AppDockDrawing.strokeInside(bounds.insetBy(dx: b, dy: b), width: 2 * b, color: accent)
            return
        }
        NSColor(white: 0, alpha: 0.46).set()
        bounds.fill(using: .sourceOver)
        accent.withAlphaComponent(0.05).set()
        bounds.fill(using: .sourceOver)
        AppDockDrawing.strokeInside(bounds, width: b, color: .black)
        AppDockDrawing.strokeInside(bounds.insetBy(dx: b, dy: b), width: b, color: accent.withAlphaComponent(0.6))

        let label = String(localized: "AppDock.SlotOutline.SnapBackHere",
                           defaultValue: "Snap back here",
                           comment: "Label in the middle of the outline that shows where a panel docked to another app’s window (Claude Dock) usually lives, while the user drags the panel elsewhere. Dropping the panel on it puts it back.")
        let font = AppDockHeaderView.headerFont(size: outline.fontSize)
        let text = NSAttributedString(string: label,
                                      attributes: [.font: font, .foregroundColor: outline.colors.text.nsColor])
        let size = text.size()
        guard size.width < bounds.width - 4 * b else {
            return
        }
        text.draw(at: NSPoint(x: bounds.midX - size.width / 2,
                              y: bounds.midY - (font.ascender + font.descender) / 2 + font.descender))
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

    // While the panel in `window` is dragged: its slot at `frame`. Away from the slot the
    // outline sits under the panel (the panel passes over it); near enough to snap it goes
    // above the panel and its edges, so the landing frame stays visible.
    func showSlotOutline(frame: CGRect, style: AppDockSlotOutlineStyle, panelWindow window: NSWindow) {
        if slotOutlinePanel.frame != frame {
            slotOutlinePanel.setFrame(frame, display: true)
        }
        let wasNear = slotOutlineView.outline?.nearSlot
        slotOutlineView.outline = style
        guard !slotOutlinePanel.isVisible || wasNear != style.nearSlot else {
            return
        }
        if style.nearSlot {
            // One level up: above the panel and its child windows whatever their order.
            slotOutlinePanel.level = NSWindow.Level(rawValue: level.rawValue + 1)
            slotOutlinePanel.orderFrontRegardless()
        } else {
            slotOutlinePanel.level = level
            slotOutlinePanel.order(.below, relativeTo: window.windowNumber)
        }
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
