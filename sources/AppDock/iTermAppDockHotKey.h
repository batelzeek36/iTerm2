//
//  iTermAppDockHotKey.h
//  iTerm2SharedARC
//
//  Zach's fork. A global hotkey that runs a block, registered with iTermHotKeyController like
//  the app and profile hotkeys, for app-docked panels.
//

#import <Foundation/Foundation.h>

#import "iTermBaseHotKey.h"

NS_ASSUME_NONNULL_BEGIN

@class iTermShortcut;

@interface iTermAppDockHotKey : iTermBaseHotKey

// Registers the shortcut at once; it stays registered until -unregisterFromController.
+ (instancetype)registeredHotKeyWithShortcut:(iTermShortcut *)shortcut
                                     handler:(void (^)(void))handler;

- (void)unregisterFromController;

@end

NS_ASSUME_NONNULL_END
