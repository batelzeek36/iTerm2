//
//  iTermAppDockSettings.swift
//  iTerm2SharedARC
//
//  Zach's fork. The profile keys that turn a profile into a panel docked to another app's
//  window (set them in a dynamic profile; there is no Settings UI):
//
//    "Dock To App Bundle ID"     required, e.g. "com.blizzard.worldofwarcraft"
//    "Dock To App Path"          optional bundle path, to pick one of several installs
//    "Dock Window Title"         optional title of the window to follow
//    "Dock ElvUI SavedVariables" optional path to ElvUI.lua; the panel takes ElvUI's chat slot
//    "Dock ElvUI Panel"          "RightChat" (default) or "LeftChat"
//    "Dock ElvUI Character"      optional profileKeys entry, e.g. "Verthy Bates"
//    "Dock Layout"               fallback placement in UI units: Point, Relative Point, X, Y,
//                                Width, Height, UI Scale, Reference Height
//    "Dock Font Size"            terminal font size in UI units (default 14.75)
//    "Dock Tall Height"          height in UI units of the Tall size (default 560): the slot's
//                                anchor, width and bottom edge, grown upward. The header button
//                                switches Mini (the slot) <-> Tall; never shorter than the slot
//    "Dock Default Size"         "Mini" (default) or "Tall": the size until the button is used;
//                                after that the user's choice and his dragged offset are kept
//                                per profile in the NoSync user defaults (AppDockPlacementStore)
//    "Dock Header Title"         gold label in the header (default: the profile name)
//    "Dock Header Subtitle"      muted label after it
//    "Dock Accent Color", "Dock Header Text Color", "Dock Header Faint Color",
//    "Dock Header Background Color"   "#rrggbb" or "#rrggbbaa"
//
//  The profile's hotkey (HotKey Key Code / Modifier Flags) focuses the panel instead of
//  opening a hotkey window; the same key with Shift added hides or shows it.
//

import AppKit

struct AppDockSettings: Equatable {
    static let bundleIDKey = "Dock To App Bundle ID"
    static let appPathKey = "Dock To App Path"
    static let windowTitleKey = "Dock Window Title"
    static let elvUISavedVariablesKey = "Dock ElvUI SavedVariables"
    static let elvUIPanelKey = "Dock ElvUI Panel"
    static let elvUICharacterKey = "Dock ElvUI Character"
    static let layoutKey = "Dock Layout"
    static let fontSizeKey = "Dock Font Size"
    static let tallHeightKey = "Dock Tall Height"
    static let defaultSizeKey = "Dock Default Size"
    static let headerTitleKey = "Dock Header Title"
    static let headerSubtitleKey = "Dock Header Subtitle"
    static let accentColorKey = "Dock Accent Color"
    static let headerTextColorKey = "Dock Header Text Color"
    static let headerFaintColorKey = "Dock Header Faint Color"
    static let headerBackgroundColorKey = "Dock Header Background Color"

    // Tall reaches from ElvUI's right-chat slot (4 units up) to just under the quest tracker on
    // a 0.63 UI scale (Zach, 2026-11-15: "it needs to cover the rest of the blank area").
    static let defaultTallHeight: CGFloat = 560

    struct Colors: Equatable {
        // Approved comp, 2026-11-14: gold accents, violet-grey muted text.
        var accent = AppDockRGBA(red: 0xf3, green: 0xcd, blue: 0x5a, alpha: 255)
        var text = AppDockRGBA(red: 0x9a, green: 0x88, blue: 0xd0, alpha: 255)
        var faint = AppDockRGBA(red: 0x6c, green: 0x5f, blue: 0x9a, alpha: 255)
        // rgba(14, 14, 16, .62), drawn over the panel's own backdrop.
        var headerBackground = AppDockRGBA(red: 14, green: 14, blue: 16, alpha: 158)
    }

    var guid: String
    var bundleID: String
    var appPath: String?
    var windowTitle: String?
    var elvUISavedVariablesPath: String?
    var elvUIPanel: ElvUIChatPanelSide
    var elvUICharacter: String?
    var fallbackLayout: AppDockLayout
    // Height of the Tall size, in UI units.
    var tallHeight: CGFloat
    var defaultSize: AppDockPanelSize
    var headerTitle: String
    var headerSubtitle: String
    var colors: Colors

    // nil when the profile is not docked to an app.
    init?(profile: [AnyHashable: Any]) {
        guard let bundleID = Self.string(profile[Self.bundleIDKey]),
              let guid = Self.string(profile[KEY_GUID]) else {
            return nil
        }
        self.guid = guid
        self.bundleID = bundleID
        appPath = Self.string(profile[Self.appPathKey]).map { ($0 as NSString).expandingTildeInPath }
        windowTitle = Self.string(profile[Self.windowTitleKey])
        elvUISavedVariablesPath = Self.string(profile[Self.elvUISavedVariablesKey]).map {
            ($0 as NSString).expandingTildeInPath
        }
        elvUIPanel = Self.string(profile[Self.elvUIPanelKey]).flatMap(ElvUIChatPanelSide.init(rawValue:)) ?? .right
        elvUICharacter = Self.string(profile[Self.elvUICharacterKey])

        var fontSize = AppDockLayout.defaultFontSize
        if let n = Self.number(profile[Self.fontSizeKey]), n > 0, n < 200 {
            fontSize = n
        }
        fallbackLayout = Self.layout(profile[Self.layoutKey] as? [String: Any], fontSize: fontSize)
        tallHeight = Self.defaultTallHeight
        if let h = Self.number(profile[Self.tallHeightKey]), h > 0, h < 10_000 {
            tallHeight = h
        }
        defaultSize = Self.string(profile[Self.defaultSizeKey]).flatMap(AppDockPanelSize.init(name:)) ?? .mini
        headerTitle = Self.string(profile[Self.headerTitleKey]) ?? Self.string(profile[KEY_NAME]) ?? "Claude"
        headerSubtitle = Self.string(profile[Self.headerSubtitleKey]) ?? ""
        var colors = Colors()
        if let c = Self.color(profile[Self.accentColorKey]) { colors.accent = c }
        if let c = Self.color(profile[Self.headerTextColorKey]) { colors.text = c }
        if let c = Self.color(profile[Self.headerFaintColorKey]) { colors.faint = c }
        if let c = Self.color(profile[Self.headerBackgroundColorKey]) { colors.headerBackground = c }
        self.colors = colors
    }

    // The placement to use now: ElvUI's slot when its SavedVariables can be read, else the
    // profile's "Dock Layout". `read` is injected for tests.
    func currentLayout(read: (String) -> String? = { try? String(contentsOfFile: $0, encoding: .utf8) }) -> AppDockLayout {
        guard let path = elvUISavedVariablesPath, let text = read(path) else {
            return fallbackLayout
        }
        do {
            return try ElvUIChatPanelReader.layout(savedVariables: text,
                                                   side: elvUIPanel,
                                                   character: elvUICharacter,
                                                   fontSize: fallbackLayout.fontSize)
        } catch {
            DLog("ElvUI layout unavailable, using the profile's Dock Layout: \(error)")
            return fallbackLayout
        }
    }

    private static func string(_ value: Any?) -> String? {
        guard let s = value as? String else {
            return nil
        }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func number(_ value: Any?) -> CGFloat? {
        guard let n = value as? NSNumber, !(value is Bool) else {
            return nil
        }
        let d = n.doubleValue
        return d.isFinite ? CGFloat(d) : nil
    }

    private static func layout(_ dict: [String: Any]?, fontSize: CGFloat) -> AppDockLayout {
        var result = AppDockLayout.elvUIRightChatDefault
        result.fontSize = fontSize
        guard let dict else {
            return result
        }
        if let p = string(dict["Point"]).flatMap({ AppDockAnchorPoint(rawValue: $0.uppercased()) }) {
            result.point = p
        }
        if let p = string(dict["Relative Point"]).flatMap({ AppDockAnchorPoint(rawValue: $0.uppercased()) }) {
            result.relativePoint = p
        }
        if let x = number(dict["X"]) { result.offset.dx = x }
        if let y = number(dict["Y"]) { result.offset.dy = y }
        if let w = number(dict["Width"]), w > 0 { result.size.width = w }
        if let h = number(dict["Height"]), h > 0 { result.size.height = h }
        if let s = number(dict["UI Scale"]), s > 0.1, s < 4 { result.uiScale = s }
        if let r = number(dict["Reference Height"]), r > 0 { result.referenceHeight = r }
        return result
    }

    private static func color(_ value: Any?) -> AppDockRGBA? {
        return string(value).flatMap(AppDockRGBA.init(hex:))
    }
}

// An sRGB color with 8-bit components, parsed from "#rrggbb" or "#rrggbbaa".
struct AppDockRGBA: Equatable, Hashable {
    var red: UInt8
    var green: UInt8
    var blue: UInt8
    var alpha: UInt8

    init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init?(hex: String) {
        guard let c = HexRGBA.parse(hex) else {
            return nil
        }
        self.init(red: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }

    // 0xRRGGBB, ignoring alpha.
    var packedRGB: Int {
        return (Int(red) << 16) | (Int(green) << 8) | Int(blue)
    }

    var nsColor: NSColor {
        return NSColor(srgbRed: CGFloat(red) / 255,
                       green: CGFloat(green) / 255,
                       blue: CGFloat(blue) / 255,
                       alpha: CGFloat(alpha) / 255)
    }
}
