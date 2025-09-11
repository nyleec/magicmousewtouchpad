#import <Cocoa/Cocoa.h>
#import "TouchManager.h"

@interface AppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation AppDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [[TouchManager sharedManager] start];
    NSLog(@"TouchManager started — grant Accessibility in System Settings!");
}
- (void)applicationWillTerminate:(NSNotification *)notification {
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
