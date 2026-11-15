//
//  iTermAppDockChrome.swift
//  iTerm2SharedARC
//
//  Zach's fork. The frame around an app-docked terminal, drawn like an ElvUI panel (approved
//  comp 2026-11-14): a 1 pt black edge with a faint inner highlight, and a header strip like
//  an ElvUI chat tab ("Claude" in gold, a muted subtitle, the hotkey on the right). No title
//  bar, no shadow, no rounded corners.
//
//  It is a separate borderless panel laid over the terminal window. Its middle is fully
//  transparent, so clicks there fall through to the terminal; a click on the header focuses
//  the terminal.
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

final class AppDockChromePanel: NSPanel {
    let chromeView: AppDockChromeView

    init() {
        chromeView = AppDockChromeView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
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
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        contentView = chromeView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class AppDockChromeView: NSView {
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

    // Only the header and the edges take clicks; the transparent middle never does.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let header else {
            return nil
        }
        let local = convert(point, from: superview)
        let b = AppDockGeometry.borderWidth
        let headerBottom = bounds.maxY - b - header.height - b
        let inMiddle = local.x > bounds.minX + 2 * b && local.x < bounds.maxX - 2 * b &&
            local.y > bounds.minY + 2 * b && local.y < headerBottom
        return inMiddle ? nil : super.hitTest(point)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.set()
        bounds.fill(using: .copy)
        guard let style, let header else {
            return
        }
        let b = AppDockGeometry.borderWidth
        let headerRect = NSRect(x: bounds.minX + b,
                                y: bounds.maxY - b - header.height,
                                width: bounds.width - 2 * b,
                                height: header.height)
        // Header strip: the panel backdrop, then the tab's own tint over it (as in the comp,
        // where the tab sits inside the panel).
        style.backdrop.nsColor.set()
        headerRect.fill(using: .sourceOver)
        style.colors.headerBackground.nsColor.set()
        headerRect.fill(using: .sourceOver)

        // Black line under the header, then the outer black edge.
        NSColor.black.set()
        NSRect(x: bounds.minX + b, y: headerRect.minY - b, width: bounds.width - 2 * b, height: b).fill()
        strokeInside(bounds, width: b, color: .black)
        // The faint inner highlight, 1 pt inside the edge.
        strokeInside(bounds.insetBy(dx: b, dy: b), width: b, color: NSColor(white: 1, alpha: 0.07))

        drawHeaderText(in: headerRect, style: style, header: header)
    }

    private func strokeInside(_ rect: NSRect, width: CGFloat, color: NSColor) {
        color.set()
        NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: width).fill(using: .sourceOver)
        NSRect(x: rect.minX, y: rect.maxY - width, width: rect.width, height: width).fill(using: .sourceOver)
        NSRect(x: rect.minX, y: rect.minY + width, width: width, height: rect.height - 2 * width).fill(using: .sourceOver)
        NSRect(x: rect.maxX - width, y: rect.minY + width, width: width, height: rect.height - 2 * width).fill(using: .sourceOver)
    }

    private static func headerFont(size: CGFloat) -> NSFont {
        if let narrow = NSFont(name: "PTSans-Narrow", size: size) {
            return narrow
        }
        let system = NSFont.systemFont(ofSize: size)
        let condensed = system.fontDescriptor.withSymbolicTraits(.condensed)
        return NSFont(descriptor: condensed, size: size) ?? system
    }

    private func drawHeaderText(in rect: NSRect, style: AppDockChromeStyle, header: AppDockHeaderMetrics) {
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
