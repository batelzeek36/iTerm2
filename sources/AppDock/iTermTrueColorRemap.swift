//
//  iTermTrueColorRemap.swift
//  iTerm2SharedARC
//
//  Zach's fork. Profile key "True Color Remap": a dictionary of "#rrggbb" -> "#rrggbb". When a
//  program sets a 24-bit foreground color (SGR 38;2) that is a key, the session uses the
//  value instead. Programs that paint their own truecolor theme (Claude Code's orange) can
//  then match one profile's palette without changing the program's settings anywhere else.
//

import Foundation

@objc(iTermTrueColorRemap)
class TrueColorRemap: NSObject {
    static let profileKey = "True Color Remap"

    // Packed 0xRRGGBB -> 0xRRGGBB, or nil when the profile has no usable entries.
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
