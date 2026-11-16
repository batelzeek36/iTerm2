//
//  iTermAppDockHeaderView.swift
//  iTerm2SharedARC
//
//  Zach's fork. The header strip of an app-docked panel, drawn like an ElvUI chat tab: the
//  panel backdrop with the tab's tint over it, the accent dot and title, a muted subtitle,
//  the hint (the hotkey, or what the pointer is over) and, at the right end, the size button.
//
//  The button is a flat ElvUI-style square: 1 pt black edge, faint inner highlight, a drawn
//  chevron that points where the panel will go (up = grow taller, down = back to mini). It
//  is lit with the accent while the panel is Tall, and its edge turns accent on hover, as
//  ElvUI's skinned buttons do. Pressing it never moves the keyboard: the game keeps it, or
//  the panel keeps it if it had it.
//
//  Everything else on the strip is the handle (see AppDockHeaderGesture): click = focus,
//  drag = move the panel, double click = back to the slot.
//

import AppKit

enum AppDockHeaderDrag: Equatable {
    case began
    // The pointer is `delta` points from where the drag began.
    case moved(CGVector)
    case ended
}

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
                rebuildTrackingAreas()
            }
        }
    }
    // Set by the tracking areas; settable so a renderer can draw the hover states.
    var hover: AppDockHeaderRegion? {
        didSet {
            if hover != oldValue {
                needsDisplay = true
            }
        }
    }

    var onClick: (() -> Void)?
    var onToggleSize: (() -> Void)?
    var onBackToSlot: (() -> Void)?
    var onDrag: ((AppDockHeaderDrag) -> Void)?

    private var gesture = AppDockHeaderGesture()
    private var handleArea: NSTrackingArea?
    private var buttonArea: NSTrackingArea?

    override var isOpaque: Bool { false }
    override var isFlipped: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    // The pointer is somewhere else after the panel changed size under it; the next move
    // over the header shows the hover again.
    func clearHover() {
        hover = nil
    }

    // MARK: - Regions

    private func region(at point: NSPoint) -> AppDockHeaderRegion? {
        guard bounds.contains(point) else {
            return nil
        }
        if let header, header.sizeButtonHitFrame(in: bounds).contains(point) {
            return .sizeButton
        }
        return .handle
    }

    private func localPoint(_ event: NSEvent) -> NSPoint {
        return convert(event.locationInWindow, from: nil)
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        let point = localPoint(event)
        let pressed = region(at: point) ?? .handle
        // A press is also a hover, in case no tracking event came first.
        hover = pressed
        gesture.mouseDown(at: NSEvent.mouseLocation, region: pressed, clickCount: event.clickCount)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let pressedBefore = gesture.showsButtonPressed(pointerRegion: hover)
        for step in gesture.mouseDragged(to: NSEvent.mouseLocation) {
            switch step {
            case .dragBegan:
                needsDisplay = true
                onDrag?(.began)
            case .dragMoved(let delta):
                onDrag?(.moved(delta))
            }
        }
        if gesture.pressedRegion == .sizeButton {
            // Draw the button released while the pointer is off it, like any push button.
            hover = region(at: localPoint(event))
            if gesture.showsButtonPressed(pointerRegion: hover) != pressedBefore {
                needsDisplay = true
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        let outcome = gesture.mouseUp(in: region(at: localPoint(event)))
        needsDisplay = true
        switch outcome {
        case .none:
            break
        case .focus:
            onClick?()
        case .backToSlot:
            onBackToSlot?()
        case .toggleSize:
            onToggleSize?()
        case .dragEnded:
            onDrag?(.ended)
        }
    }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        rebuildTrackingAreas()
    }

    // activeAlways: the panel's app is never the active one while the game is played.
    private func rebuildTrackingAreas() {
        for area in [handleArea, buttonArea].compactMap({ $0 }) {
            removeTrackingArea(area)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        let handle = NSTrackingArea(rect: .zero, options: options.union(.inVisibleRect), owner: self, userInfo: nil)
        addTrackingArea(handle)
        handleArea = handle
        buttonArea = nil
        if let header {
            let button = NSTrackingArea(rect: header.sizeButtonHitFrame(in: bounds), options: options, owner: self, userInfo: nil)
            addTrackingArea(button)
            buttonArea = button
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        rebuildTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        if let buttonArea, event.trackingArea === buttonArea {
            hover = .sizeButton
        } else if hover == nil {
            hover = .handle
        }
    }

    override func mouseExited(with event: NSEvent) {
        if let buttonArea, event.trackingArea === buttonArea {
            hover = bounds.contains(localPoint(event)) ? .handle : nil
        } else {
            hover = nil
        }
    }

    // MARK: - Drawing

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
        let button = header.sizeButtonFrame(in: bounds)
        drawText(in: bounds, rightLimit: button.minX - header.hintGap, style: style, header: header)
        drawSizeButton(in: button, style: style)
    }

    static func headerFont(size: CGFloat) -> NSFont {
        if let narrow = NSFont(name: "PTSans-Narrow", size: size) {
            return narrow
        }
        let system = NSFont.systemFont(ofSize: size)
        let condensed = system.fontDescriptor.withSymbolicTraits(.condensed)
        return NSFont(descriptor: condensed, size: size) ?? system
    }

    private var currentHint: AppDockHeaderHint {
        guard let style else {
            return .hotKey
        }
        return AppDockHeaderHint.current(hover: hover,
                                         size: style.size,
                                         isMoved: style.isMoved,
                                         drag: style.drag)
    }

    private func hintText(_ hint: AppDockHeaderHint, style: AppDockChromeStyle) -> (String, AppDockRGBA) {
        switch hint {
        case .hotKey:
            return (style.hotKeyHint, style.colors.faint)
        case .growTaller:
            return (String(localized: "AppDock.Header.GrowTaller",
                           defaultValue: "Grow taller",
                           comment: "Shown in the header of a panel docked to another app’s window (Claude Dock) while the pointer is over the button that makes the panel taller."),
                    style.colors.accent)
        case .backToMini:
            return (String(localized: "AppDock.Header.BackToMini",
                           defaultValue: "Back to mini",
                           comment: "Shown in the header of a panel docked to another app’s window (Claude Dock) while the pointer is over the button that shrinks the tall panel back to its small size."),
                    style.colors.accent)
        case .doubleClickToSnapBack:
            return (String(localized: "AppDock.Header.DoubleClickToSnapBack",
                           defaultValue: "Double-click to snap back",
                           comment: "Shown in the header of a panel docked to another app’s window (Claude Dock) after the user dragged it away from its usual place, while the pointer is over the header: a double click puts it back."),
                    style.colors.text)
        case .releaseToSnapBack:
            return (String(localized: "AppDock.Header.ReleaseToSnapBack",
                           defaultValue: "Release to snap back",
                           comment: "Shown in the header of a panel docked to another app’s window (Claude Dock) while the user drags it close to its usual place: letting go of the mouse button puts it back there exactly."),
                    style.colors.accent)
        }
    }

    private func drawText(in rect: NSRect, rightLimit: CGFloat, style: AppDockChromeStyle, header: AppDockHeaderMetrics) {
        let font = Self.headerFont(size: header.fontSize)
        let hintFont = Self.headerFont(size: header.fontSize * 0.9)
        let baselineY = rect.midY - (font.ascender + font.descender) / 2
        var x = rect.minX + header.horizontalPadding

        // Accent dot, then the title in the accent.
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

        let (hintString, hintColor) = hintText(currentHint, style: style)
        let hint = NSAttributedString(string: hintString,
                                      attributes: [.font: hintFont, .foregroundColor: hintColor.nsColor])
        let hintWidth = hintString.isEmpty ? 0 : hint.size().width
        let hintX = rightLimit - hintWidth

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

    private func drawSizeButton(in rect: NSRect, style: AppDockChromeStyle) {
        let tall = style.size == .tall
        let hovered = hover == .sizeButton
        let pressed = gesture.showsButtonPressed(pointerRegion: hover)
        let accent = style.colors.accent.nsColor
        let b = AppDockGeometry.borderWidth

        // Face: a shade lighter than the strip; accent-tinted while Tall (on) or held down.
        NSColor(white: 1, alpha: 0.06).set()
        rect.fill(using: .sourceOver)
        if tall || pressed {
            accent.withAlphaComponent(pressed ? 0.34 : 0.16).set()
            rect.fill(using: .sourceOver)
        }
        // Edge: black like every ElvUI frame, accent on hover; then the faint inner highlight.
        AppDockDrawing.strokeInside(rect, width: b, color: hovered || pressed ? accent : .black)
        AppDockDrawing.strokeInside(rect.insetBy(dx: b, dy: b), width: b, color: NSColor(white: 1, alpha: hovered ? 0.12 : 0.07))

        // Chevron: points up to grow, down to shrink.
        let glyph = hovered || pressed || tall ? accent : style.colors.text.nsColor
        let inner = rect.insetBy(dx: 2 * b, dy: 2 * b)
        let w = (inner.width * 0.56).rounded()
        let h = (w * 0.5).rounded()
        let midX = inner.midX
        let midY = inner.midY
        let path = NSBezierPath()
        let tipY = tall ? midY - h / 2 : midY + h / 2
        let baseY = tall ? midY + h / 2 : midY - h / 2
        path.move(to: NSPoint(x: midX - w / 2, y: baseY))
        path.line(to: NSPoint(x: midX, y: tipY))
        path.line(to: NSPoint(x: midX + w / 2, y: baseY))
        path.lineWidth = max(1, inner.width * 0.12)
        path.lineCapStyle = .square
        path.lineJoinStyle = .miter
        glyph.set()
        path.stroke()
    }
}
