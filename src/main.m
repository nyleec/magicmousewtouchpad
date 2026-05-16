#import <Cocoa/Cocoa.h>
#import "TouchManager.h"
#import <Carbon/Carbon.h>

@interface AppDelegate : NSObject <NSApplicationDelegate>
{
    EventHotKeyRef hotKeyRef;
    EventHandlerRef hotKeyHandlerRef;
    NSStatusItem *statusItem;
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

    // Add a status bar item that shows the app version and provides a small menu
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (!version) version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
    NSString *title = [NSString stringWithFormat:@"MagicMouse v%@", version ?: @"?"];
    statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    if (statusItem.button) statusItem.button.title = title;
    NSMenu *menu = [NSMenu new];
    [menu addItemWithTitle:@"Toggle Touch" action:@selector(toggleTouchManager:) keyEquivalent:@""];
    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    statusItem.menu = menu;
}

- (void)toggleTouchManager:(id)sender {
    TouchManager *mgr = [TouchManager sharedManager];
    if ([mgr isRunning]) {
        [mgr stop];
        NSLog(@"TouchManager paused via hotkey");
        // update status title to indicate paused
        NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        if (!version) version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
        if (statusItem.button) statusItem.button.title = [NSString stringWithFormat:@"MagicMouse v%@ (Paused)", version ?: @"?"];
    } else {
        [mgr start];
        NSLog(@"TouchManager started via hotkey");
        // restore status title
        NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
        if (!version) version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
        if (statusItem.button) statusItem.button.title = [NSString stringWithFormat:@"MagicMouse v%@", version ?: @"?"];
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
    if (statusItem) {
        [[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
        statusItem = nil;
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
