//
//  iTermAppDockPlacementStore.swift
//  iTerm2SharedARC
//
//  Zach's fork. Keeps each app-docked panel's Mini/Tall choice and dragged offset (see
//  iTermAppDockPlacement.swift) across launches, per profile GUID, in this app's own user
//  defaults (Claude Dock's suite when it runs there). NoSync: where a panel was left is
//  local state, not a setting to carry to another Mac.
//

import Foundation

enum AppDockPlacementStore {
    static let userDefaultsKey = "NoSyncAppDockPanelPlacements"

    // The saved placement for the profile, or the profile's default size in its slot.
    static func placement(forGuid guid: String,
                          defaultSize: AppDockPanelSize,
                          defaults: UserDefaults = iTermUserDefaults.userDefaults()) -> AppDockPlacement {
        let saved = defaults.dictionary(forKey: userDefaultsKey)?[guid]
        return AppDockPlacement(plist: saved, fallback: AppDockPlacement(size: defaultSize))
    }

    static func save(_ placement: AppDockPlacement,
                     forGuid guid: String,
                     defaults: UserDefaults = iTermUserDefaults.userDefaults()) {
        var all = defaults.dictionary(forKey: userDefaultsKey) ?? [:]
        all[guid] = placement.plist
        defaults.set(all, forKey: userDefaultsKey)
    }
}
