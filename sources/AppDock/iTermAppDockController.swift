//
//  iTermAppDockController.swift
//  iTerm2SharedARC
//
//  Zach's fork. One panel docked to another app's window (see iTermAppDockSettings.swift for
//  the profile keys). The panel is a borderless, non-activating terminal window that sits
//  in a slot on the target window, scales its frame and text with that window, and shows
//  only while the target is frontmost or the panel has the keyboard.
//
//  Focus model, with the profile's hotkey H (Ctrl-Opt-Cmd-C for the WoW panel):
//    H              panel not focused: show it and give it the keyboard (the game stays the
//                   active app, so its window keeps its place and the panel stays on top).
//                   Panel focused: hand the keyboard back to the target app.
//    Shift-H        hide the panel / show it again. The session keeps running while hidden.
//    Click          clicking the panel focuses it; clicking the game focuses the game.
//

import AppKit

final class AppDockController: NSObject {
    private(set) var settings: AppDockSettings
    private var layout: AppDockLayout
    private var layoutFileDate: Date?
    private var tracker: AppDockTargetTracker
    private weak var term: PseudoTerminal?
    private let chrome = AppDockChromePanel()
    private var focusHotKey: iTermAppDockHotKey?
    private var visibilityHotKey: iTermAppDockHotKey?
    private var hotKeyHint = ""
    private var hiddenByUser = false
    private var creatingWindow = false
    private var focusWhenCreated = false
    private var applyingFrame = false
    private var reassertScheduled = false
    private var recentReasserts = [TimeInterval]()
    private var visibilityUpdateScheduled = false
    private var geometry: AppDockGeometry?
    private var appliedFontSize: CGFloat?
    private var appObservers = [NSObjectProtocol]()
    private var windowObservers = [NSObjectProtocol]()

    init(settings: AppDockSettings) {
        self.settings = settings
        layout = settings.fallbackLayout
        tracker = AppDockTargetTracker(criteria: Self.criteria(settings))
        super.init()
        chrome.chromeView.onClick = { [weak self] in
            self?.focusPanel()
        }
    }

    private static func criteria(_ settings: AppDockSettings) -> AppDockTargetTracker.Criteria {
        return AppDockTargetTracker.Criteria(bundleID: settings.bundleID,
                                             appPath: settings.appPath,
                                             windowTitle: settings.windowTitle)
    }

    func start() {
        reloadLayout(force: true)
        registerHotKeys()
        let workspace = NSWorkspace.shared.notificationCenter
        appObservers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                  object: nil,
                                                  queue: .main) { [weak self] _ in
            self?.scheduleVisibilityUpdate()
        })
        appObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                   object: nil,
                                                                   queue: .main) { [weak self] _ in
            self?.tracker.refresh()
            self?.applyGeometry()
        })
        startTracker()
    }

    private func startTracker() {
        tracker.onChange = { [weak self] target in
            self?.targetDidChange(target)
        }
        tracker.start()
    }

    // The profile changed. Anything cheap is updated in place; a new target means a new tracker.
    func update(settings newSettings: AppDockSettings) {
        guard newSettings != settings else {
            return
        }
        let oldCriteria = Self.criteria(settings)
        settings = newSettings
        reloadLayout(force: true)
        registerHotKeys()
        if Self.criteria(newSettings) != oldCriteria {
            tracker.stop()
            tracker = AppDockTargetTracker(criteria: Self.criteria(newSettings))
            startTracker()
        }
        appliedFontSize = nil
        applyGeometry()
        scheduleVisibilityUpdate()
    }

    // The profile is gone or no longer docked.
    func tearDown() {
        tracker.stop()
        focusHotKey?.unregisterFromController()
        visibilityHotKey?.unregisterFromController()
        focusHotKey = nil
        visibilityHotKey = nil
        for o in appObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
            NotificationCenter.default.removeObserver(o)
        }
        appObservers.removeAll()
        stopObservingWindow()
        detachChrome()
        if let window = term?.window {
            window.orderOut(nil)
            window.close()
        }
        term = nil
    }

    // MARK: - Hotkeys

    private func registerHotKeys() {
        focusHotKey?.unregisterFromController()
        visibilityHotKey?.unregisterFromController()
        focusHotKey = nil
        visibilityHotKey = nil
        hotKeyHint = ""
        guard let profile = ProfileModel.sharedInstance()?.bookmark(withGuid: settings.guid),
              let shortcut = iTermShortcut.shortcuts(forProfile: profile).first else {
            DLog("App dock \(settings.guid): no hotkey in the profile")
            return
        }
        focusHotKey = iTermAppDockHotKey.registeredHotKey(with: shortcut) { [weak self] in
            self?.focusHotKeyPressed()
        }
        let modifiers = shortcut.modifiers
        if let hideShortcut = iTermShortcut(keyCode: shortcut.keyCode,
                                            hasKeyCode: shortcut.hasKeyCode,
                                            modifiers: modifiers.union(.shift),
                                            characters: shortcut.characters?.uppercased(),
                                            charactersIgnoringModifiers: shortcut.charactersIgnoringModifiers) {
            visibilityHotKey = iTermAppDockHotKey.registeredHotKey(with: hideShortcut) { [weak self] in
                self?.visibilityHotKeyPressed()
            }
        }
        hotKeyHint = AppDockHotKeyHint.string(modifiers: modifiers,
                                              key: shortcut.charactersIgnoringModifiers ?? "")
    }

    private func focusHotKeyPressed() {
        let panelIsKey = term?.window?.isKeyWindow ?? false
        switch AppDockFocusPolicy.focusAction(targetWindowPresent: tracker.target != nil,
                                              panelIsKey: panelIsKey) {
        case .nothing:
            DLog("App dock: hotkey pressed but \(settings.bundleID) has no window")
        case .focusPanel:
            hiddenByUser = false
            if term == nil {
                focusWhenCreated = true
                createWindowIfNeeded()
            } else {
                focusPanel()
            }
        case .returnFocusToTarget:
            returnFocusToTarget()
        }
    }

    private func visibilityHotKeyPressed() {
        hiddenByUser.toggle()
        DLog("App dock: hidden by user = \(hiddenByUser)")
        if hiddenByUser {
            if term?.window?.isKeyWindow == true {
                returnFocusToTarget()
            }
        } else if tracker.target != nil {
            createWindowIfNeeded()
        }
        updateVisibility()
    }

    // MARK: - Focus

    private func focusPanel() {
        guard let term, let window = term.window, tracker.target != nil else {
            return
        }
        hiddenByUser = false
        applyGeometry()
        guard geometry != nil else {
            return
        }
        // A non-activating panel takes the keyboard without activating iTerm2, so the target
        // app stays frontmost and nothing else of iTerm2's comes forward.
        window.makeKeyAndOrderFront(nil)
        if let responder = term.currentSession()?.mainResponder {
            window.makeFirstResponder(responder)
        }
        attachChrome(to: window)
    }

    private func returnFocusToTarget() {
        guard let window = term?.window else {
            return
        }
        if NSApp.isActive, let app = tracker.runningApp {
            // iTerm2 became active (the user switched to it); give activation back.
            app.activate(options: [])
            return
        }
        // The target app is still the active app; ordering the key panel out returns the
        // keyboard to its window (re-activating it makes sure its window is key again). The
        // panel then comes back without focus.
        detachChrome()
        window.orderOut(nil)
        tracker.runningApp?.activate(options: [])
        scheduleVisibilityUpdate()
    }

    // MARK: - Window

    private func createWindowIfNeeded() {
        guard term == nil, !creatingWindow, !hiddenByUser || focusWhenCreated,
              let profile = ProfileModel.sharedInstance()?.bookmark(withGuid: settings.guid) else {
            return
        }
        creatingWindow = true
        var windowProfile = profile
        windowProfile[AppDockWindowMarker.key] = true
        windowProfile[KEY_WINDOW_TYPE] = NSNumber(value: iTermWindowType.WINDOW_TYPE_NO_TITLE_BAR.rawValue)
        guard let newTerm = PseudoTerminal(smartLayout: false,
                                           windowType: .WINDOW_TYPE_NO_TITLE_BAR,
                                           savedWindowType: .WINDOW_TYPE_NO_TITLE_BAR,
                                           percentage: iTermPercentage(width: -1, height: -1),
                                           screen: -1,
                                           hotkeyWindowType: .none,
                                           profile: windowProfile),
              let window = newTerm.window else {
            creatingWindow = false
            return
        }
        configure(window)
        iTermController.sharedInstance()?.addTerminalWindow(newTerm)
        term = newTerm
        observeWindow(window)
        // Put the window in its slot before the session starts, so the program's first grid is
        // the panel's (only the font change follows, once the session exists).
        applyGeometry()
        DLog("App dock: created window \(window) for \(settings.guid)")
        iTermSessionLauncher.launchBookmark(profile,
                                            in: newTerm,
                                            style: .tab,
                                            withURL: nil,
                                            hotkeyWindowType: .none,
                                            makeKey: false,
                                            canActivate: false,
                                            respectTabbingMode: false,
                                            index: nil,
                                            command: nil,
                                            makeSession: nil,
                                            didMakeSession: { [weak self] session in
            self?.sessionCreated(session)
        },
                                            completion: nil)
    }

    private func configure(_ window: NSWindow) {
        window.level = .floating
        window.isMovable = false
        window.isMovableByWindowBackground = false
        window.isExcludedFromWindowsMenu = true
        window.hidesOnDeactivate = false
        window.hasShadow = false
        window.animationBehavior = .none
        window.isRestorable = false
        if let panel = window as? NSPanel {
            panel.becomesKeyOnlyIfNeeded = false
            panel.worksWhenModal = false
        }
        chrome.level = window.level
    }

    private func sessionCreated(_ session: PTYSession?) {
        creatingWindow = false
        guard let session, term != nil else {
            DLog("App dock: the session did not start")
            return
        }
        appliedFontSize = nil
        applyGeometry()
        updateVisibility()
        if focusWhenCreated {
            focusWhenCreated = false
            focusPanel()
        }
        DLog("App dock: session \(session) started")
    }

    private func observeWindow(_ window: NSWindow) {
        stopObservingWindow()
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            windowObservers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.scheduleVisibilityUpdate()
            })
        }
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            windowObservers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.windowFrameDidChange()
            })
        }
        windowObservers.append(center.addObserver(forName: NSWindow.willCloseNotification,
                                                  object: window,
                                                  queue: .main) { [weak self] _ in
            self?.windowWillClose()
        })
    }

    private func stopObservingWindow() {
        for o in windowObservers {
            NotificationCenter.default.removeObserver(o)
        }
        windowObservers.removeAll()
    }

    // Anything but the anchor that moves the panel (a tiling script, the API, a system
    // shortcut) is undone.
    private func windowFrameDidChange() {
        guard !applyingFrame, !reassertScheduled else {
            return
        }
        guard let geometry, let window = term?.window, window.frame != geometry.terminalFrame else {
            return
        }
        // Something that keeps fighting the anchor must not turn this into a busy loop.
        let now = Date.timeIntervalSinceReferenceDate
        recentReasserts = recentReasserts.filter { now - $0 < 1 } + [now]
        guard recentReasserts.count <= 10 else {
            DLog("App dock: frame keeps changing; not putting it back again this second")
            return
        }
        reassertScheduled = true
        DispatchQueue.main.async {
            self.reassertScheduled = false
            DLog("App dock: frame changed to \(String(describing: self.term?.window?.frame)); putting it back")
            self.applyGeometry()
        }
    }

    // The session ended (the user quit claude). The next hotkey press or the next time the
    // target window appears makes a new one.
    private func windowWillClose() {
        DLog("App dock: window closed")
        stopObservingWindow()
        detachChrome()
        term = nil
        creatingWindow = false
        geometry = nil
        appliedFontSize = nil
    }

    // MARK: - Geometry

    private func targetDidChange(_ target: AppDockTarget?) {
        if target != nil {
            if term == nil, !hiddenByUser {
                reloadLayout(force: false)
                createWindowIfNeeded()
            }
            applyGeometry()
        }
        updateVisibility()
    }

    private func reloadLayout(force: Bool) {
        guard let path = settings.elvUISavedVariablesPath else {
            layout = settings.fallbackLayout
            layoutFileDate = nil
            return
        }
        let date = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
        guard force || date != layoutFileDate else {
            return
        }
        layoutFileDate = date
        let newLayout = settings.currentLayout()
        if newLayout != layout {
            DLog("App dock: layout is now \(newLayout)")
        }
        layout = newLayout
    }

    private func applyGeometry() {
        guard let target = tracker.target, let window = term?.window else {
            geometry = nil
            return
        }
        // WoW rewrites ElvUI.lua on /reload and logout; pick up a moved or resized chat panel.
        reloadLayout(force: false)
        guard let g = AppDockGeometry(layout: layout,
                                      contentRect: target.contentRect,
                                      backingScale: Self.backingScale(for: target.contentRect)) else {
            geometry = nil
            return
        }
        geometry = g
        applyFont(g.fontSize)
        if window.frame != g.terminalFrame {
            applyingFrame = true
            window.setFrame(g.terminalFrame, display: true)
            applyingFrame = false
        }
        if chrome.frame != g.panelFrame {
            chrome.setFrame(g.panelFrame, display: true)
        }
        chrome.chromeView.header = g.header
        chrome.chromeView.style = style()
    }

    private func applyFont(_ size: CGFloat) {
        guard appliedFontSize != size, let term else {
            return
        }
        appliedFontSize = size
        for session in term.allSessions() {
            guard let textview = session.textview, let profile = session.profile else {
                continue
            }
            let base = FontTable.fontTable(forProfile: profile)
            let table = base.fontTable(grownBy: size - base.asciiFont.font.pointSize)
            session.setFontTable(table,
                                 horizontalSpacing: textview.horizontalSpacing,
                                 verticalSpacing: textview.verticalSpacing)
        }
    }

    private static func backingScale(for rect: CGRect) -> CGFloat {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
        return screen?.backingScaleFactor ?? 2
    }

    private func style() -> AppDockChromeStyle {
        return AppDockChromeStyle(title: settings.headerTitle,
                                  subtitle: settings.headerSubtitle,
                                  hotKeyHint: hotKeyHint,
                                  colors: settings.colors,
                                  backdrop: backdrop())
    }

    // The terminal's background at its transparency, so the header matches the panel body.
    private func backdrop() -> AppDockRGBA {
        let fallback = AppDockRGBA(red: 6, green: 6, blue: 7, alpha: 153)
        guard let profile = term?.currentSession()?.profile else {
            return fallback
        }
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        var key = KEY_BACKGROUND_COLOR
        if (profile[KEY_USE_SEPARATE_COLORS_FOR_LIGHT_AND_DARK_MODE] as? NSNumber)?.boolValue == true {
            key += dark ? COLORS_DARK_MODE_SUFFIX : COLORS_LIGHT_MODE_SUFFIX
        }
        guard let dict = profile[key] as? NSDictionary,
              let color = dict.colorValue()?.usingColorSpace(.sRGB) else {
            return fallback
        }
        let transparency = iTermProfilePreferences.double(forKey: KEY_TRANSPARENCY, inProfile: profile)
        let alpha = max(0, min(1, 1 - transparency))
        return AppDockRGBA(red: UInt8(max(0, min(255, (color.redComponent * 255).rounded()))),
                           green: UInt8(max(0, min(255, (color.greenComponent * 255).rounded()))),
                           blue: UInt8(max(0, min(255, (color.blueComponent * 255).rounded()))),
                           alpha: UInt8((alpha * 255).rounded()))
    }

    // MARK: - Visibility

    private func scheduleVisibilityUpdate() {
        guard !visibilityUpdateScheduled else {
            return
        }
        visibilityUpdateScheduled = true
        DispatchQueue.main.async {
            self.visibilityUpdateScheduled = false
            self.updateVisibility()
        }
    }

    private func updateVisibility() {
        guard let window = term?.window else {
            detachChrome()
            return
        }
        let target = tracker.target
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let inputs = AppDockVisibilityInputs(targetWindowPresent: target != nil && geometry != nil,
                                             targetIsFrontmost: target != nil && frontmost == target?.pid,
                                             panelIsKey: window.isKeyWindow,
                                             hiddenByUser: hiddenByUser)
        if AppDockVisibility.shouldShow(inputs) {
            applyGeometry()
            if !window.isVisible {
                window.orderFrontRegardless()
            }
            attachChrome(to: window)
        } else if window.isVisible || chrome.isVisible {
            detachChrome()
            window.orderOut(nil)
        }
    }

    private func attachChrome(to window: NSWindow) {
        if chrome.parent !== window {
            chrome.parent?.removeChildWindow(chrome)
            window.addChildWindow(chrome, ordered: .above)
        }
        if !chrome.isVisible {
            chrome.orderFrontRegardless()
        }
    }

    private func detachChrome() {
        chrome.parent?.removeChildWindow(chrome)
        chrome.orderOut(nil)
    }
}

// Lets PseudoTerminal (Objective-C) recognize app-docked profiles and windows.
@objc(iTermAppDockWindowMarker)
class AppDockWindowMarker: NSObject {
    // Added by the dock controller to the profile a docked window is created with.
    @objc static let key = "Zach Fork: App-Docked Window"

    @objc(isMarkedProfile:)
    static func isMarked(_ profile: [AnyHashable: Any]?) -> Bool {
        return (profile?[key] as? NSNumber)?.boolValue ?? false
    }

    @objc(isDockedProfile:)
    static func isDocked(_ profile: [AnyHashable: Any]?) -> Bool {
        guard let profile else {
            return false
        }
        return AppDockSettings(profile: profile) != nil
    }

    // Square corners, no title bar, and it takes the keyboard without activating iTerm2.
    @objc static var styleMask: NSWindow.StyleMask {
        return [.borderless, .nonactivatingPanel]
    }
}
