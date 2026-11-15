//
//  iTermTrueColorRemap.swift
//  iTerm2SharedARC
//
//  Zach's fork. Profile key "True Color Remap": a dictionary of "#rrggbb" -> "#rrggbb". When a
//  program sets a 24-bit text or background color (SGR 38;2 or 48;2) that is a key, the
//  session uses the value instead. Programs that paint their own truecolor theme (Claude
//  Code's orange text, its grey message and red/green diff backgrounds) can then match one
//  profile's palette without changing the program's settings anywhere else.
//
//  Profile key "True Color Remap Tolerance" (0-64, default 0): a color that is not a key but
//  lies within this RGB distance of one is moved by the same amount as that key, keeping its
//  offset. Animated gradients built around a theme color (Claude Code's spinner shimmer
//  between its orange and a lighter orange, reddening while a request stalls) then follow
//  the remapped color instead of flickering back to the original. Exact keys always win.
//

import Foundation

@objc(iTermTrueColorRemap)
class TrueColorRemap: NSObject {
    static let profileKey = "True Color Remap"
    static let toleranceProfileKey = "True Color Remap Tolerance"
    static let maximumTolerance = 64

    // The tolerance travels in the same dictionary as the colors, under a key no packed
    // 0xRRGGBB color can have.
    @objc static let toleranceKey = NSNumber(value: -1)

    // Packed 0xRRGGBB -> 0xRRGGBB (plus toleranceKey -> tolerance when it is above 0), or nil
    // when the profile has no usable entries.
    @objc(remapForProfile:)
    static func remap(forProfile profile: [AnyHashable: Any]?) -> [NSNumber: NSNumber]? {
        guard let dict = profile?[profileKey] as? [String: Any] else {
            return nil
        }
        let parsed = parse(dict)
        guard !parsed.isEmpty else {
            return nil
        }
        var result = [NSNumber: NSNumber]()
        for (from, to) in parsed {
            result[NSNumber(value: from)] = NSNumber(value: to)
        }
        let tolerance = Self.tolerance(profile?[toleranceProfileKey])
        if tolerance > 0 {
            result[toleranceKey] = NSNumber(value: tolerance)
        }
        return result
    }

    // Entries whose key or value is not a "#rrggbb" color are skipped.
    static func parse(_ dict: [String: Any]) -> [Int: Int] {
        var result = [Int: Int]()
        for (key, value) in dict {
            guard let to = value as? String,
                  let fromColor = HexRGBA.parse(key),
                  let toColor = HexRGBA.parse(to) else {
                DLog("Ignoring \(profileKey) entry \(key) -> \(value)")
                continue
            }
            result[fromColor.packedRGB] = toColor.packedRGB
        }
        return result
    }

    static func tolerance(_ value: Any?) -> Int {
        guard let n = value as? NSNumber, !(value is Bool), n.doubleValue.isFinite else {
            return 0
        }
        return max(0, min(maximumTolerance, Int(n.doubleValue.rounded())))
    }

    // What `packed` becomes under `map`: its exact entry, else (with a tolerance in the map)
    // the nearest key's replacement moved by packed's offset from that key, else nil. Ties go
    // to the smaller key so the answer never depends on dictionary order.
    @objc(replacementFor:in:)
    static func replacement(for packed: Int, in map: [NSNumber: NSNumber]) -> NSNumber? {
        if let exact = map[NSNumber(value: packed)] {
            return exact
        }
        guard let tolerance = map[toleranceKey]?.intValue, tolerance > 0 else {
            return nil
        }
        let c = rgb(packed)
        var best: (distance: Int, key: Int, value: Int)?
        for (key, value) in map where key != toleranceKey {
            let k = rgb(key.intValue)
            let d = (c.r - k.r) * (c.r - k.r) + (c.g - k.g) * (c.g - k.g) + (c.b - k.b) * (c.b - k.b)
            guard d <= tolerance * tolerance else {
                continue
            }
            if best == nil || d < best!.distance || (d == best!.distance && key.intValue < best!.key) {
                best = (d, key.intValue, value.intValue)
            }
        }
        guard let best else {
            return nil
        }
        let k = rgb(best.key)
        let v = rgb(best.value)
        func clamp(_ x: Int) -> Int { max(0, min(255, x)) }
        let r = clamp(v.r + c.r - k.r), g = clamp(v.g + c.g - k.g), b = clamp(v.b + c.b - k.b)
        return NSNumber(value: (r << 16) | (g << 8) | b)
    }

    private static func rgb(_ packed: Int) -> (r: Int, g: Int, b: Int) {
        return ((packed >> 16) & 0xff, (packed >> 8) & 0xff, packed & 0xff)
    }
}

// "#rrggbb" or "#rrggbbaa" (the # is optional) as 8-bit sRGB components.
enum HexRGBA {
    struct Components: Equatable {
        var red: UInt8
        var green: UInt8
        var blue: UInt8
        var alpha: UInt8

        var packedRGB: Int {
            return (Int(red) << 16) | (Int(green) << 8) | Int(blue)
        }
    }

    static func parse(_ hex: String) -> Components? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") {
            s.removeFirst()
        }
        guard s.count == 6 || s.count == 8,
              s.allSatisfy({ $0.isHexDigit }),
              let value = UInt64(s, radix: 16) else {
            return nil
        }
        if s.count == 6 {
            return Components(red: UInt8((value >> 16) & 0xff),
                              green: UInt8((value >> 8) & 0xff),
                              blue: UInt8(value & 0xff),
                              alpha: 255)
        }
        return Components(red: UInt8((value >> 24) & 0xff),
                          green: UInt8((value >> 16) & 0xff),
                          blue: UInt8((value >> 8) & 0xff),
                          alpha: UInt8(value & 0xff))
    }
}
