//
//  iTermAppDockManager.swift
//  iTerm2SharedARC
//
//  Zach's fork. Keeps one AppDockController per profile that has "Dock To App Bundle ID",
//  following profile edits (dynamic profiles reload live).
//

import AppKit

@objc(iTermAppDockManager)
final class AppDockManager: NSObject {
    private static let shared = AppDockManager()
    private var controllers = [String: AppDockController]()
    private var started = false

    @objc static func start() {
        shared.start()
    }

    private func start() {
        guard !started else {
            return
        }
        started = true
        for name in [NSNotification.Name(kReloadAllProfiles), NSNotification.Name.reloadAddressBook] {
            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(profilesDidChange(_:)),
                                                   name: name,
                                                   object: nil)
        }
        refresh()
    }

    @objc private func profilesDidChange(_ notification: Notification) {
        // Coalesce: dynamic profile reloads post several notifications in a row.
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(refresh), object: nil)
        perform(#selector(refresh), with: nil, afterDelay: 0)
    }

    @objc private func refresh() {
        let profiles = ProfileModel.sharedInstance()?.bookmarks() ?? []
        var docked = [String: AppDockSettings]()
        for profile in profiles {
            if let settings = AppDockSettings(profile: profile) {
                docked[settings.guid] = settings
            }
        }
        for (guid, controller) in controllers where docked[guid] == nil {
            DLog("App dock: profile \(guid) is no longer docked")
            controller.tearDown()
            controllers[guid] = nil
        }
        for (guid, settings) in docked {
            if let existing = controllers[guid] {
                existing.update(settings: settings)
            } else {
                DLog("App dock: docking profile \(guid) to \(settings.bundleID)")
                let controller = AppDockController(settings: settings)
                controllers[guid] = controller
                controller.start()
            }
        }
    }
}
