//
//  iTermAppDockTargetTracker.swift
//  iTerm2SharedARC
//
//  Zach's fork. Follows another app's window for an app-docked panel: where its content area
//  is, and whether it is on screen. With the Accessibility permission it listens to the
//  window's move/resize notifications (and samples at display rate while it is changing);
//  without it, it polls the window list.
//
//  Every call into the other app happens on a private queue with a short messaging timeout,
//  so a busy game (a loading screen) can never stall iTerm2's main thread.
//

import AppKit
import ApplicationServices

struct AppDockTarget: Equatable {
    var pid: pid_t
    // Whole window, Cocoa screen coordinates.
    var windowFrame: CGRect
    // The window minus its title bar.
    var contentRect: CGRect
    var isFullScreen: Bool
}

// Pure helpers, separated for tests.
enum AppDockTargetGeometry {
    // AX and CGWindowList use a top-left origin at the top of the primary screen.
    static func cocoaRect(fromTopLeft rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        return CGRect(x: rect.minX,
                      y: primaryScreenHeight - rect.maxY,
                      width: rect.width,
                      height: rect.height)
    }

    // The title bar's height from the close button, which macOS centers in it:
    // 2 * (button top - window top) + button height. 0 for windows without one.
    static func titleBarHeight(windowTopLeft: CGRect, closeButtonTopLeft: CGRect?, isFullScreen: Bool) -> CGFloat {
        guard !isFullScreen, let button = closeButtonTopLeft, button.height > 0 else {
            return 0
        }
        let inset = button.minY - windowTopLeft.minY
        let height = 2 * inset + button.height
        guard inset >= 0, height > 0, height < 80 else {
            return defaultTitleBarHeight
        }
        return height
    }

    static let defaultTitleBarHeight: CGFloat = 28

    static func contentRect(windowFrame: CGRect, titleBarHeight: CGFloat) -> CGRect {
        var rect = windowFrame
        rect.size.height = max(0, rect.height - titleBarHeight)
        return rect
    }
}

final class AppDockTargetTracker {
    struct Criteria: Equatable {
        var bundleID: String
        var appPath: String?
        var windowTitle: String?
    }

    // Called on the main queue whenever the target changes; nil = no usable window.
    var onChange: ((AppDockTarget?) -> Void)?
    private(set) var target: AppDockTarget?
    private(set) var runningApp: NSRunningApplication?

    private let criteria: Criteria
    private let queue = DispatchQueue(label: "com.googlecode.iterm2.app-dock-tracker")
    private var workspaceObservers = [NSObjectProtocol]()

    // Accessed on `queue` only.
    private var axApp: AXUIElement?
    private var axWindow: AXUIElement?
    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var burstTimer: DispatchSourceTimer?
    private var burstDeadline = DispatchTime.now()
    private var safetyTimer: DispatchSourceTimer?
    private var lastPublished: AppDockTarget?
    private var refreshPending = false
    private var appHidden = false
    // Main queue only.
    private var stopped = false

    private static let messagingTimeout: Float = 0.2
    private static let burstInterval = DispatchTimeInterval.milliseconds(16)
    private static let burstLength = DispatchTimeInterval.milliseconds(500)

    init(criteria: Criteria) {
        self.criteria = criteria
    }

    deinit {
        stop()
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [NSWorkspace.didLaunchApplicationNotification,
                                          NSWorkspace.didTerminateApplicationNotification,
                                          NSWorkspace.didHideApplicationNotification,
                                          NSWorkspace.didUnhideApplicationNotification,
                                          NSWorkspace.activeSpaceDidChangeNotification]
        for name in names {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                self?.workspaceDidChange(note)
            })
        }
        attachToRunningApp()
    }

    // Main queue. Nothing on `queue` ever waits for the main queue, so this cannot deadlock;
    // it waits at most for one in-flight call into the other app (messagingTimeout).
    func stop() {
        stopped = true
        for o in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
        }
        workspaceObservers.removeAll()
        queue.sync {
            self.detachLocked()
        }
    }

    // Re-read the window now (e.g. after the panel was asked to show).
    func refresh() {
        scheduleRefresh()
    }

    private func workspaceDidChange(_ note: Notification) {
        if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
            if note.name == NSWorkspace.didTerminateApplicationNotification,
               app.processIdentifier == runningApp?.processIdentifier {
                runningApp = nil
                queue.async {
                    self.detachLocked()
                    self.publishLocked(nil)
                }
                return
            }
            if note.name == NSWorkspace.didLaunchApplicationNotification, runningApp == nil, matches(app) {
                attachToRunningApp()
                return
            }
        }
        let hidden = runningApp?.isHidden ?? false
        queue.async {
            self.appHidden = hidden
        }
        scheduleRefresh()
    }

    private func matches(_ app: NSRunningApplication) -> Bool {
        guard app.bundleIdentifier == criteria.bundleID, !app.isTerminated else {
            return false
        }
        if let path = criteria.appPath {
            return app.bundleURL?.standardizedFileURL.path == URL(fileURLWithPath: path).standardizedFileURL.path
        }
        return true
    }

    private func attachToRunningApp() {
        runningApp = NSWorkspace.shared.runningApplications.first(where: matches)
        guard let app = runningApp else {
            queue.async { self.publishLocked(nil) }
            return
        }
        let pid = app.processIdentifier
        let hidden = app.isHidden
        let trusted = AXIsProcessTrusted()
        DLog("App dock: following pid \(pid) (\(criteria.bundleID)); accessibility \(trusted ? "granted" : "not granted, polling")")
        queue.async {
            self.detachLocked()
            self.observedPID = pid
            self.appHidden = hidden
            if trusted {
                self.attachObserverLocked(pid: pid)
            }
            self.startSafetyTimerLocked(interval: trusted ? .seconds(1) : .milliseconds(100))
            self.refreshLocked()
        }
    }

    // MARK: - Queue-confined work

    private func detachLocked() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        axApp = nil
        axWindow = nil
        observedPID = 0
        burstTimer?.cancel()
        burstTimer = nil
        safetyTimer?.cancel()
        safetyTimer = nil
    }

    private func attachObserverLocked(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
        axApp = app
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else {
                return
            }
            let tracker = Unmanaged<AppDockTargetTracker>.fromOpaque(refcon).takeUnretainedValue()
            tracker.axNotificationReceived()
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else {
            DLog("App dock: AXObserverCreate failed; polling instead")
            return
        }
        observer = created
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXMainWindowChangedNotification] {
            AXObserverAddNotification(created, app, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
    }

    private func observeWindowLocked(_ window: AXUIElement) {
        guard let observer else {
            return
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXMovedNotification, kAXResizedNotification, kAXWindowMiniaturizedNotification,
                     kAXWindowDeminiaturizedNotification, kAXUIElementDestroyedNotification] {
            AXObserverAddNotification(observer, window, name as CFString, refcon)
        }
    }

    // Main queue (the observer's run loop source is on the main run loop).
    private func axNotificationReceived() {
        queue.async {
            self.startBurstLocked()
            self.refreshLocked()
        }
    }

    private func scheduleRefresh() {
        queue.async {
            guard !self.refreshPending else {
                return
            }
            self.refreshPending = true
            self.queue.async {
                self.refreshPending = false
                self.refreshLocked()
            }
        }
    }

    // While the window is changing, sample it at display rate so the panel moves with it
    // even if the app only reports the end of a drag.
    private func startBurstLocked() {
        burstDeadline = .now() + Self.burstLength
        guard burstTimer == nil else {
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.burstInterval, repeating: Self.burstInterval)
        timer.setEventHandler { [weak self] in
            guard let self else {
                return
            }
            if DispatchTime.now() > self.burstDeadline {
                self.burstTimer?.cancel()
                self.burstTimer = nil
                return
            }
            self.refreshLocked()
        }
        burstTimer = timer
        timer.resume()
    }

    private func startSafetyTimerLocked(interval: DispatchTimeInterval) {
        safetyTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.refreshLocked()
        }
        safetyTimer = timer
        timer.resume()
    }

    private func refreshLocked() {
        guard observedPID != 0 else {
            publishLocked(nil)
            return
        }
        if axApp == nil, AXIsProcessTrusted() {
            // Accessibility was granted while running: switch from polling to notifications.
            attachObserverLocked(pid: observedPID)
            startSafetyTimerLocked(interval: .seconds(1))
        }
        let primaryHeight = Self.primaryScreenHeight()
        let found: AppDockTarget?
        if let axApp {
            found = readAXLocked(app: axApp, primaryHeight: primaryHeight)
        } else {
            found = readWindowListLocked(primaryHeight: primaryHeight)
        }
        publishLocked(found)
    }

    private func publishLocked(_ value: AppDockTarget?) {
        guard value != lastPublished else {
            return
        }
        lastPublished = value
        DispatchQueue.main.async {
            guard !self.stopped else {
                return
            }
            self.target = value
            self.onChange?(value)
        }
    }

    private static func primaryScreenHeight() -> CGFloat {
        // NSScreen is documented as main-thread only; CGDisplayBounds is not.
        return CGDisplayBounds(CGMainDisplayID()).height
    }

    // MARK: - Accessibility

    private func readAXLocked(app: AXUIElement, primaryHeight: CGFloat) -> AppDockTarget? {
        if appHidden {
            return nil
        }
        if axWindow == nil || !Self.isAlive(axWindow!) {
            axWindow = chooseWindowLocked(app: app)
            if let w = axWindow {
                AXUIElementSetMessagingTimeout(w, Self.messagingTimeout)
                observeWindowLocked(w)
            }
        }
        guard let window = axWindow else {
            return nil
        }
        if Self.bool(window, kAXMinimizedAttribute) == true {
            return nil
        }
        guard let frameTL = Self.frame(of: window), frameTL.width > 0, frameTL.height > 0 else {
            return nil
        }
        let fullScreen = Self.bool(window, "AXFullScreen") == true
        let closeButton = Self.element(window, kAXCloseButtonAttribute).flatMap { Self.frame(of: $0) }
        let titleBar = AppDockTargetGeometry.titleBarHeight(windowTopLeft: frameTL,
                                                             closeButtonTopLeft: closeButton,
                                                             isFullScreen: fullScreen)
        let windowFrame = AppDockTargetGeometry.cocoaRect(fromTopLeft: frameTL, primaryScreenHeight: primaryHeight)
        return AppDockTarget(pid: observedPID,
                             windowFrame: windowFrame,
                             contentRect: AppDockTargetGeometry.contentRect(windowFrame: windowFrame,
                                                                            titleBarHeight: titleBar),
                             isFullScreen: fullScreen)
    }

    private func chooseWindowLocked(app: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else {
            return nil
        }
        let standard = windows.filter {
            let subrole = Self.string($0, kAXSubroleAttribute)
            return subrole == nil || subrole == (kAXStandardWindowSubrole as String)
        }
        if let title = criteria.windowTitle,
           let match = standard.first(where: { Self.string($0, kAXTitleAttribute) == title }) {
            return match
        }
        if criteria.windowTitle != nil {
            // A title was asked for and no window has it (yet).
            return nil
        }
        return standard.max { a, b in
            let fa = Self.frame(of: a) ?? .zero
            let fb = Self.frame(of: b) ?? .zero
            return fa.width * fa.height < fb.width * fb.height
        }
    }

    private static func isAlive(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        return error != .invalidUIElement
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return (value as? NSNumber)?.boolValue
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &extent) else {
            return nil
        }
        return CGRect(origin: point, size: extent)
    }

    // MARK: - Window list (no Accessibility permission)

    private func readWindowListLocked(primaryHeight: CGFloat) -> AppDockTarget? {
        if appHidden {
            return nil
        }
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let mine = list.filter {
            ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == observedPID &&
                ($0[kCGWindowLayer as String] as? NSNumber)?.intValue == 0
        }
        func bounds(_ info: [String: Any]) -> CGRect? {
            guard let dict = info[kCGWindowBounds as String] as? NSDictionary else {
                return nil
            }
            return CGRect(dictionaryRepresentation: dict as CFDictionary)
        }
        let titled = criteria.windowTitle.flatMap { title in
            mine.first { ($0[kCGWindowName as String] as? String) == title }
        }
        // Window names need Screen Recording; without it fall back to the largest window.
        let chosen = titled ?? mine.max { a, b in
            let fa = bounds(a) ?? .zero
            let fb = bounds(b) ?? .zero
            return fa.width * fa.height < fb.width * fb.height
        }
        guard let chosen, let frameTL = bounds(chosen), frameTL.width > 100, frameTL.height > 100 else {
            return nil
        }
        let displayBounds = Self.displayBounds(containing: frameTL)
        let fullScreen = displayBounds.map { frameTL.equalTo($0) } ?? false
        let windowFrame = AppDockTargetGeometry.cocoaRect(fromTopLeft: frameTL, primaryScreenHeight: primaryHeight)
        let titleBar = fullScreen ? 0 : AppDockTargetGeometry.defaultTitleBarHeight
        return AppDockTarget(pid: observedPID,
                             windowFrame: windowFrame,
                             contentRect: AppDockTargetGeometry.contentRect(windowFrame: windowFrame,
                                                                            titleBarHeight: titleBar),
                             isFullScreen: fullScreen)
    }

    private static func displayBounds(containing rect: CGRect) -> CGRect? {
        var count: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        guard CGGetDisplaysWithRect(rect, 16, &displays, &count) == .success, count > 0 else {
            return nil
        }
        return CGDisplayBounds(displays[0])
    }
}
