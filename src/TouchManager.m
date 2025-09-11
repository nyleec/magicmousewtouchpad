// TouchManager.m
#import "TouchManager.h"
#import <CoreGraphics/CoreGraphics.h>
#import <CoreFoundation/CoreFoundation.h>

// Use the private MultitouchSupport framework
// Link with -F/System/Library/PrivateFrameworks -framework MultitouchSupport

// Forward declarations / minimal finger struct extracted from community examples
typedef void* MTDeviceRef;

typedef struct {
    int frame;
    double timestamp;
    int identifier;
    int state;
    float x;
    float y;
    float size;
    // many other fields exist; we only use normalized x/y here
} MTContact;

typedef int (*MTContactCallback)(int, MTContact*, int, double, int);

extern CFArrayRef MTDeviceCreateList(void);
extern void MTRegisterContactFrameCallback(MTDeviceRef, MTContactCallback);
extern void MTDeviceStart(MTDeviceRef, int);
extern void MTDeviceStop(MTDeviceRef);

static CFArrayRef gDevices = NULL;

@implementation TouchManager

+ (instancetype)sharedManager {
    static TouchManager *m;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        m = [TouchManager new];
    });
    return m;
}

static int touchCallback(int frame, MTContact *contacts, int count, double timestamp, int unknown) {
    if (count <= 0 || !contacts) return 0;

    // Find first active contact
    MTContact *c = &contacts[0];

    // normalized coordinates (0..1) from the device — map to screen
    float nx = c->x; // expected normalized [0..1]
    float ny = c->y; // expected normalized [0..1]
    // Some devices present inverted Y; adjust if necessary
    ny = 1.0f - ny;

    // Get main display size
    CGSize screenSize = CGDisplayBounds(CGMainDisplayID()).size;
    double screenX = nx * screenSize.width;
    double screenY = ny * screenSize.height;

    // Move cursor
    CGWarpMouseCursorPosition(CGPointMake(screenX, screenY));

    // If contact is very short and small movement -> generate click
    static double lastContactStart = 0;
    static double lastContactEnd = 0;
    static BOOL wasTouching = NO;

    // state: historical examples show state codes: 0 = touch begin? 1 = continuing? 2 = end? Not standardized.
    // We'll detect changes via timestamp changes and size.
    if (!wasTouching) {
        lastContactStart = timestamp;
        wasTouching = YES;
    } else {
        // continuing
    }

    // Very naive tap detection: if contact size small and time short (<0.15s)
    // We can't detect release reliably here because the callback doesn't always include a release contact.
    // Instead, approximate: if time since start < 0.15 and size small, synthesize click.
    double duration = timestamp - lastContactStart;
    if (duration < 0.15 && c->size < 0.03) {
        // synthesize a left-click (press + release)
        CGEventRef down = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, CGPointMake(screenX, screenY), kCGMouseButtonLeft);
        CGEventRef up   = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp,   CGPointMake(screenX, screenY), kCGMouseButtonLeft);
        if (down && up) {
            CGEventPost(kCGHIDEventTap, down);
            CGEventPost(kCGHIDEventTap, up);
        }
        if (down) CFRelease(down);
        if (up)   CFRelease(up);

        // prevent immediate re-fire
        lastContactStart = timestamp + 0.5;
    }

    return 0;
}

- (void)start {
    if (gDevices) return;
    gDevices = MTDeviceCreateList();
    if (!gDevices) return;

    CFIndex count = CFArrayGetCount(gDevices);
    for (CFIndex i=0;i<count;i++) {
        MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(gDevices, i);
        MTRegisterContactFrameCallback(dev, touchCallback);
        MTDeviceStart(dev, 0);
    }
}

- (void)stop {
    if (!gDevices) return;
    CFIndex count = CFArrayGetCount(gDevices);
    for (CFIndex i=0;i<count;i++) {
        MTDeviceRef dev = (MTDeviceRef)CFArrayGetValueAtIndex(gDevices, i);
        MTDeviceStop(dev);
    }
    CFRelease(gDevices);
    gDevices = NULL;
}

@end
