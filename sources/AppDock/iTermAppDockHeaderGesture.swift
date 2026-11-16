//
//  iTermAppDockHeaderGesture.swift
//  iTerm2SharedARC
//
//  Zach's fork. What a press on an app-docked panel's header means, and what its hint says.
//  The header has two parts: the size button (Mini <-> Tall) at its right end and the rest,
//  which is the handle:
//    - a click on the handle focuses the panel (as before the button existed);
//    - a press that moves more than `dragThreshold` points drags the panel instead, and never
//      focuses it;
//    - a double click on the handle puts a moved panel back in its slot;
//    - the button toggles the size on release inside it (a press that leaves the button does
//      nothing) and never changes which window has the keyboard.
//  Pure: points in, outcomes out (AppDockHeaderView feeds it the mouse events).
//

import CoreGraphics
import Foundation

enum AppDockHeaderRegion: Equatable {
    case handle
    case sizeButton
}

struct AppDockHeaderGesture {
    // Movement, in points, before a press on the handle becomes a drag.
    static let dragThreshold: CGFloat = 3

    enum Outcome: Equatable {
        case none
        // Plain click on the handle: give the panel the keyboard.
        case focus
        // Double click on the handle: back to the slot.
        case backToSlot
        // Released on the size button it was pressed on.
        case toggleSize
        // A drag of the handle ended.
        case dragEnded
    }

    enum Step: Equatable {
        // The press became a drag; the panel follows from here.
        case dragBegan
        // The pointer is now `delta` points from where the press began.
        case dragMoved(CGVector)
    }

    private(set) var pressedRegion: AppDockHeaderRegion?
    private(set) var isDragging = false
    private var start = CGPoint.zero
    private var clickCount = 0

    // `point` in screen coordinates: the panel moves under the pointer while it is dragged.
    mutating func mouseDown(at point: CGPoint, region: AppDockHeaderRegion, clickCount: Int) {
        pressedRegion = region
        isDragging = false
        start = point
        self.clickCount = clickCount
    }

    // The steps to act on, in order: a drag that just began reports .dragBegan, then where
    // the pointer is.
    mutating func mouseDragged(to point: CGPoint) -> [Step] {
        guard pressedRegion == .handle else {
            return []
        }
        let delta = CGVector(dx: point.x - start.x, dy: point.y - start.y)
        if isDragging {
            return [.dragMoved(delta)]
        }
        guard hypot(delta.dx, delta.dy) > Self.dragThreshold else {
            return []
        }
        isDragging = true
        return [.dragBegan, .dragMoved(delta)]
    }

    // `region` is where the pointer is at release, nil when outside the header.
    mutating func mouseUp(in region: AppDockHeaderRegion?) -> Outcome {
        defer {
            pressedRegion = nil
            isDragging = false
        }
        switch pressedRegion {
        case nil:
            return .none
        case .sizeButton:
            return region == .sizeButton ? .toggleSize : .none
        case .handle:
            if isDragging {
                return .dragEnded
            }
            return clickCount >= 2 ? .backToSlot : .focus
        }
    }

    // The button draws pressed while it is held and the pointer is still on it.
    func showsButtonPressed(pointerRegion: AppDockHeaderRegion?) -> Bool {
        return pressedRegion == .sizeButton && pointerRegion == .sizeButton
    }
}

// Where a dragged panel is, for the feedback while it moves.
enum AppDockDragFeedback: Equatable {
    // Not being dragged.
    case none
    // Dragged, away from its slot: the slot shows as an outline with its name.
    case away
    // Dragged close enough to its slot that letting go snaps it back.
    case nearSlot
}

// The words at the right end of the header, left of the size button.
enum AppDockHeaderHint: Equatable {
    // The focus hotkey, e.g. ⌃⌥⌘C.
    case hotKey
    // Hovering the size button of a Mini panel.
    case growTaller
    // Hovering the size button of a Tall panel.
    case backToMini
    // Hovering the handle of a panel that was dragged out of its slot.
    case doubleClickToSnapBack
    // Dragging, close enough to the slot that a drop snaps the panel into it.
    case releaseToSnapBack

    static func current(hover: AppDockHeaderRegion?,
                        size: AppDockPanelSize,
                        isMoved: Bool,
                        drag: AppDockDragFeedback) -> AppDockHeaderHint {
        switch drag {
        case .nearSlot:
            return .releaseToSnapBack
        case .away:
            return .hotKey
        case .none:
            break
        }
        switch hover {
        case .sizeButton:
            return size == .mini ? .growTaller : .backToMini
        case .handle:
            return isMoved ? .doubleClickToSnapBack : .hotKey
        case nil:
            return .hotKey
        }
    }
}
