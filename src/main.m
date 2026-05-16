#import <Cocoa/Cocoa.h>
#import "TouchManager.h"
#import <Carbon/Carbon.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>
{
    EventHotKeyRef hotKeyRef;
    EventHandlerRef hotKeyHandlerRef;
}
- (void)toggleTouchManager:(id)sender;
@end

@implementation AppDelegate

static OSStatus HotKeyHandler(EventHandlerCallRef nextHandler, EventRef theEvent, void *userData) {
    AppDelegate *self = (__bridge AppDelegate *)userData;
    [self toggleTouchManager:nil];
    return noErr;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [[TouchManager sharedManager] start];
    NSLog(@"TouchManager started — grant Accessibility in System Settings!");

    // Register global hotkey Cmd+Shift+T to toggle touch features
    EventTypeSpec eventType;
    eventType.eventClass = kEventClassKeyboard;
    eventType.eventKind = kEventHotKeyPressed;
    InstallApplicationEventHandler(&HotKeyHandler, 1, &eventType, (__bridge void *)self, &hotKeyHandlerRef);

    EventHotKeyID hkID;
    hkID.signature = 'MMHT';
    hkID.id = 1;
    UInt32 modifiers = cmdKey | shiftKey;
    OSStatus status = RegisterEventHotKey(kVK_ANSI_T, modifiers, hkID, GetApplicationEventTarget(), 0, &hotKeyRef);
    if (status != noErr) {
        NSLog(@"Failed to register hotkey: %d", status);
    } else {
        NSLog(@"Registered global hotkey Cmd+Shift+T to toggle touchpad features");
    }
}

- (void)toggleTouchManager:(id)sender {
    TouchManager *mgr = [TouchManager sharedManager];
    if ([mgr isRunning]) {
        [mgr stop];
        NSLog(@"TouchManager paused via hotkey");
    } else {
        [mgr start];
        NSLog(@"TouchManager started via hotkey");
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    if (hotKeyRef) {
        UnregisterEventHotKey(hotKeyRef);
        hotKeyRef = NULL;
    }
    if (hotKeyHandlerRef) {
        RemoveEventHandler(hotKeyHandlerRef);
        hotKeyHandlerRef = NULL;
    }
    [[TouchManager sharedManager] stop];
}

@end

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [AppDelegate new];
        [app setDelegate:delegate];
        return NSApplicationMain(argc, argv);
    }
}
