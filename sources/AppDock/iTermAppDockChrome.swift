//
//  iTermAppDockChrome.swift
//  iTerm2SharedARC
//
//  Zach's fork. The frame around an app-docked terminal, drawn like an ElvUI panel (approved
//  comp 2026-11-14): a 1 pt black edge with a faint inner highlight, and a header strip like
//  an ElvUI chat tab ("Claude" in gold, a muted subtitle, the hotkey on the right). No title
//  bar, no shadow, no rounded corners.
//
//  Two borderless panels laid over the terminal window:
//    - the edge panel covers the whole panel and draws the edges; it never takes a click, so
//      a click anywhere outside the header reaches whatever is under it (the game, unless the
//      terminal has the keyboard and takes the click itself);
//    - the header panel covers only the header strip; a click there focuses the terminal.
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
        Self.strokeInside(bounds, width: b, color: .black)
        Self.strokeInside(bounds.insetBy(dx: b, dy: b), width: b, color: NSColor(white: 1, alpha: 0.07))
    }

    private static func strokeInside(_ rect: NSRect, width: CGFloat, color: NSColor) {
        color.set()
        NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: width).fill(using: .sourceOver)
        NSRect(x: rect.minX, y: rect.maxY - width, width: rect.width, height: width).fill(using: .sourceOver)
        NSRect(x: rect.minX, y: rect.minY + width, width: width, height: rect.height - 2 * width).fill(using: .sourceOver)
        NSRect(x: rect.maxX - width, y: rect.minY + width, width: width, height: rect.height - 2 * width).fill(using: .sourceOver)
    }
}

// The header strip: the panel backdrop with the tab's tint over it, a gold dot and title, a
// muted subtitle and the hotkey hint. Clicking it focuses the terminal.
final class AppDockHeaderView: NSView {
    var style: AppDockChromeStyle? {
        didSet {
            if style != oldValue {
                needsDisplay = true
            }
        }
    }
    var header: AppDockHeaderMetrics? {
        didSet {
            if header != oldValue {
                needsDisplay = true
            }
        }
    }
    var onClick: (() -> Void)?

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        bounds.fill(using: .copy)
        guard let style, let header else {
            return
        }
        style.backdrop.nsColor.set()
        bounds.fill(using: .sourceOver)
        style.colors.headerBackground.nsColor.set()
        bounds.fill(using: .sourceOver)
        drawText(in: bounds, style: style, header: header)
    }

    private static func headerFont(size: CGFloat) -> NSFont {
        if let narrow = NSFont(name: "PTSans-Narrow", size: size) {
            return narrow
        }
        let system = NSFont.systemFont(ofSize: size)
        let condensed = system.fontDescriptor.withSymbolicTraits(.condensed)
        return NSFont(descriptor: condensed, size: size) ?? system
    }

    private func drawText(in rect: NSRect, style: AppDockChromeStyle, header: AppDockHeaderMetrics) {
        let font = Self.headerFont(size: header.fontSize)
        let hintFont = Self.headerFont(size: header.fontSize * 0.9)
        let baselineY = rect.midY - (font.ascender + font.descender) / 2
        var x = rect.minX + header.horizontalPadding

        // Gold dot, then the title in gold.
        let dot = header.dotDiameter
        let dotRect = NSRect(x: x,
                             y: baselineY + font.xHeight / 2 - dot / 2,
                             width: dot,
                             height: dot)
        style.colors.accent.nsColor.set()
        NSBezierPath(ovalIn: dotRect).fill()
        x += dot + header.fontSize * 0.35

        let title = NSAttributedString(string: style.title,
                                       attributes: [.font: font, .foregroundColor: style.colors.accent.nsColor])
        title.draw(at: NSPoint(x: x, y: baselineY + font.descender))
        x += title.size().width + header.gap

        let hint = NSAttributedString(string: style.hotKeyHint,
                                      attributes: [.font: hintFont, .foregroundColor: style.colors.faint.nsColor])
        let hintWidth = style.hotKeyHint.isEmpty ? 0 : hint.size().width
        let hintX = rect.maxX - header.horizontalPadding - hintWidth

        if !style.subtitle.isEmpty, x < hintX - header.gap {
            let subtitle = NSAttributedString(string: style.subtitle,
                                              attributes: [.font: font, .foregroundColor: style.colors.text.nsColor])
            let available = hintX - header.gap - x
            NSGraphicsContext.saveGraphicsState()
            NSRect(x: x, y: rect.minY, width: available, height: rect.height).clip()
            subtitle.draw(at: NSPoint(x: x, y: baselineY + font.descender))
            NSGraphicsContext.restoreGraphicsState()
        }
        if hintWidth > 0, hintX > x {
            hint.draw(at: NSPoint(x: hintX, y: baselineY + hintFont.descender))
        }
    }
}

// The two chrome panels of one docked terminal, moved and shown together.
final class AppDockChrome {
    let edgeView = AppDockEdgeView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    let headerView = AppDockHeaderView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    private let edgePanel: AppDockChromePanel
    private let headerPanel: AppDockChromePanel

    init() {
        edgePanel = AppDockChromePanel(contentView: edgeView, takesClicks: false)
        headerPanel = AppDockChromePanel(contentView: headerView, takesClicks: true)
    }

    var level: NSWindow.Level {
        get { edgePanel.level }
        set {
            edgePanel.level = newValue
            headerPanel.level = newValue
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
        for panel in [edgePanel, headerPanel] {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
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
