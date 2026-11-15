//
//  iTermAppDockHotKey.m
//  iTerm2SharedARC
//

#import "iTermAppDockHotKey.h"

#import "DebugLogging.h"
#import "iTermHotKeyController.h"
#import "iTermShortcut.h"

@implementation iTermAppDockHotKey {
    void (^_handler)(void);
    BOOL _registered;
}

+ (instancetype)registeredHotKeyWithShortcut:(iTermShortcut *)shortcut
                                     handler:(void (^)(void))handler {
    iTermAppDockHotKey *hotKey = [[self alloc] initWithShortcuts:@[ shortcut ]
                                           hasModifierActivation:NO
                                              modifierActivation:iTermHotKeyModifierActivationShift];
    hotKey->_handler = [handler copy];
    hotKey->_registered = YES;
    [[iTermHotKeyController sharedInstance] addHotKey:hotKey];
    return hotKey;
}

- (void)unregisterFromController {
    if (!_registered) {
        return;
    }
    _registered = NO;
    [[iTermHotKeyController sharedInstance] removeHotKey:self];
}

// Overrides the abstract method in iTermBaseHotKey.
- (NSArray<iTermBaseHotKey *> *)hotKeyPressedWithSiblings:(NSArray<iTermBaseHotKey *> *)siblings {
    DLog(@"App dock hotkey pressed: %@", self);
    if (_handler) {
        _handler();
    }
    return @[ self ];
}

@end
