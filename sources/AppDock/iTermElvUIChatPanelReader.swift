//
//  iTermElvUIChatPanelReader.swift
//  iTerm2SharedARC
//
//  Zach's fork. Turns ElvUI's SavedVariables (WTF/Account/<account>/SavedVariables/ElvUI.lua)
//  into the layout of one of its chat panels, so an app-docked panel takes exactly the slot
//  ElvUI keeps for that chat window. Mirrors ElvUI's own sizing (Layout.lua,
//  LO:RefreshChatMovers): the chat mover is panelWidth x panelHeight, plus the 22 + 1 unit
//  datatext bar when that bar is shown, placed by the saved mover string.
//

import CoreGraphics
import Foundation

enum ElvUIChatPanelSide: String {
    case left = "LeftChat"
    case right = "RightChat"
}

struct ElvUIChatPanelReader {
    struct Failure: Error, Equatable, CustomStringConvertible {
        let description: String
    }

    // ElvUI defaults (Defaults/Profile.lua and Defaults/Global.lua).
    static let defaultUIScale: CGFloat = 0.64
    static let defaultPanelWidth: CGFloat = 412
    static let defaultPanelHeight: CGFloat = 180
    // BAR_HEIGHT + 1 in Layout.lua.
    static let dataPanelHeight: CGFloat = 23

    static func defaultMover(_ side: ElvUIChatPanelSide) -> String {
        switch side {
        case .left: return "BOTTOMLEFT,ElvUIParent,BOTTOMLEFT,4,4"
        case .right: return "BOTTOMRIGHT,ElvUIParent,BOTTOMRIGHT,-4,4"
        }
    }

    // `character` is a profileKeys entry such as "Verthy Bates" or "Verthy - Realm". When it is
    // nil or unknown, the profile shared by every character is used, else "Default".
    static func layout(savedVariables text: String,
                       side: ElvUIChatPanelSide,
                       character: String?,
                       fontSize: CGFloat) throws -> AppDockLayout {
        let assignments: [String: LuaValue]
        do {
            assignments = try LuaLiteralParser.parseAssignments(text)
        } catch {
            throw Failure(description: "ElvUI.lua could not be read: \(error)")
        }
        guard let db = assignments["ElvDB"], db.tableValue != nil else {
            throw Failure(description: "ElvUI.lua has no ElvDB table")
        }
        let profileName = Self.profileName(db: db, character: character)
        let profile = db["profiles", profileName]
        let chat = profile?["chat"]

        let uiScale = CGFloat(db["global", "general", "UIScale"]?.numberValue ?? Double(defaultUIScale))
        guard uiScale > 0.1, uiScale < 4 else {
            throw Failure(description: "ElvUI UIScale \(uiScale) is out of range")
        }

        let separate = chat?["separateSizes"]?.boolValue ?? false
        let useRightSizes = side == .right && separate
        let width = number(chat?[useRightSizes ? "panelWidthRight" : "panelWidth"], defaultPanelWidth)
        let height = number(chat?[useRightSizes ? "panelHeightRight" : "panelHeight"], defaultPanelHeight)
        let dataPanel = side == .left ? "LeftChatDataPanel" : "RightChatDataPanel"
        let dataPanelShown = profile?["datatexts", "panels", dataPanel, "enable"]?.boolValue ?? true
        let totalHeight = height + (dataPanelShown ? dataPanelHeight : 0)

        let moverString = profile?["movers", side.rawValue + "Mover"]?.stringValue ?? defaultMover(side)
        guard let mover = parseMover(moverString) ?? parseMover(defaultMover(side)) else {
            throw Failure(description: "No usable mover for \(side.rawValue)")
        }
        guard width > 0, totalHeight > 0 else {
            throw Failure(description: "ElvUI chat panel size \(width)x\(height) is not usable")
        }
        return AppDockLayout(point: mover.point,
                             relativePoint: mover.relativePoint,
                             offset: mover.offset,
                             size: CGSize(width: width, height: totalHeight),
                             uiScale: uiScale,
                             fontSize: fontSize)
    }

    static func profileName(db: LuaValue, character: String?) -> String {
        guard let keys = db["profileKeys"]?.tableValue else {
            return "Default"
        }
        if let character, let name = keys.entries[.string(character)]?.stringValue {
            return name
        }
        let names = Set(keys.entries.values.compactMap { $0.stringValue })
        if names.count == 1, let only = names.first {
            return only
        }
        if names.contains("Default") || names.isEmpty {
            return "Default"
        }
        return names.sorted().first ?? "Default"
    }

    struct Mover: Equatable {
        var point: AppDockAnchorPoint
        var relativePoint: AppDockAnchorPoint
        var offset: CGVector
    }

    // "BOTTOMRIGHT,ElvUIParent,BOTTOMRIGHT,-4,4". Only movers relative to the whole UI
    // (ElvUIParent or UIParent) describe a place on the window; others return nil.
    static func parseMover(_ string: String) -> Mover? {
        let parts = string.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 5,
              let point = AppDockAnchorPoint(rawValue: parts[0].uppercased()),
              parts[1] == "ElvUIParent" || parts[1] == "UIParent",
              let relativePoint = AppDockAnchorPoint(rawValue: parts[2].uppercased()),
              let x = Double(parts[3]), let y = Double(parts[4]),
              x.isFinite, y.isFinite else {
            return nil
        }
        return Mover(point: point, relativePoint: relativePoint, offset: CGVector(dx: x, dy: y))
    }

    private static func number(_ value: LuaValue?, _ fallback: CGFloat) -> CGFloat {
        guard let n = value?.numberValue, n.isFinite else {
            return fallback
        }
        return CGFloat(n)
    }
}
