//
//  iTermAppDockVisibility.swift
//  iTerm2SharedARC
//
//  Zach's fork. When an app-docked panel is on screen. It shows only while its target app is
//  frontmost or while the panel itself has keyboard focus, so it never covers other apps,
//  and it disappears with the target's window.
//

import Foundation

struct AppDockVisibilityInputs: Equatable {
    // The target window exists, is on screen and not minimized.
    var targetWindowPresent: Bool
    // The target app is the active (frontmost) app.
    var targetIsFrontmost: Bool
    // The panel is the key window: it receives the keyboard.
    var panelIsKey: Bool
    // The user hid the panel with the hide/show hotkey.
    var hiddenByUser: Bool
}

enum AppDockVisibility {
    static func shouldShow(_ inputs: AppDockVisibilityInputs) -> Bool {
        guard inputs.targetWindowPresent, !inputs.hiddenByUser else {
            return false
        }
        return inputs.targetIsFrontmost || inputs.panelIsKey
    }
}

// What the focus hotkey does in the current state.
enum AppDockFocusAction: Equatable {
    // Show the panel if needed and give it the keyboard.
    case focusPanel
    // Give the keyboard back to the target app; the panel stays on screen.
    case returnFocusToTarget
    // The target app has no window to dock to.
    case nothing
}

enum AppDockFocusPolicy {
    static func focusAction(targetWindowPresent: Bool, panelIsKey: Bool) -> AppDockFocusAction {
        guard targetWindowPresent else {
            return .nothing
        }
        return panelIsKey ? .returnFocusToTarget : .focusPanel
    }

    // The terminal takes mouse events only while it has the keyboard. Otherwise a click (or a
    // scroll) in its slot goes to the game under it - a bag opened there, say - and can never
    // hand the keyboard to the terminal. Only the header focuses it.
    static func terminalTakesClicks(panelIsKey: Bool) -> Bool {
        return panelIsKey
    }
}
