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
    float unknown1;
    float unknown2;
    float x; // normalized X [0..1]
    float y; // normalized Y [0..1]
    float size;
    float unknown3;
    float unknown4;
    float angle;
    float majorAxis;
    float minorAxis;
    float unknown5;
    // many other fields exist; we only use normalized x/y here
} MTContact;

typedef int (*MTContactCallback)(int, MTContact*, int, double, int);
    float unknown1;
    float unknown2;
    float normalizedPosition[2]; // x, y
    float size;
    float unknown3;
    float unknown4;
    float angle;
    float majorAxis;
    float minorAxis;
    float unknown5;
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
    float nx = c->x; // normalized X [0..1]
    float ny = c->y; // normalized Y [0..1]

    // Some devices present inverted Y; adjust if necessary
    ny = 1.0f - ny;

    // Track previous touch position for relative movement
    static float lastNx = -1.0f;
    static float lastNy = -1.0f;

    // Get main display size
    CGSize screenSize = CGDisplayBounds(CGMainDisplayID()).size;
    CGPoint mouseLoc = CGEventGetLocation(CGEventCreate(NULL));
        static int ignoreInitial = 0;
        static int ignoreInitialConfig = 3;
    static double sensitivity = 0.35;
    static double smoothing = 0.5;
    static int configRead = 0;
    static double smoothX = 0.0, smoothY = 0.0;
    if (!configRead) {
        NSString *configPath = [[NSBundle mainBundle] pathForResource:@"config" ofType:@"txt"];
        if (configPath) {
            NSString *contents = [NSString stringWithContentsOfFile:configPath encoding:NSUTF8StringEncoding error:nil];
            NSArray *lines = [contents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
            for (NSString *line in lines) {
                if ([line hasPrefix:@"sensitivity="]) {
                    sensitivity = [[line substringFromIndex:12] doubleValue];
                } else if ([line hasPrefix:@"smoothing="]) {
                    smoothing = [[line substringFromIndex:10] doubleValue];
                } else if ([line hasPrefix:@"ignore_initial="]) {
                    ignoreInitialConfig = [[line substringFromIndex:14] intValue];
                }
            }
        }
        configRead = 1;
    }

    double deltaX = 0.0, deltaY = 0.0;
    if (lastNx >= 0.0f && lastNy >= 0.0f) {
        deltaX = (nx - lastNx) * screenSize.width * sensitivity;
        deltaY = (ny - lastNy) * screenSize.height * sensitivity;
    }

    // Apply smoothing
    smoothX = (smoothX * smoothing) + (deltaX * (1.0 - smoothing));
    smoothY = (smoothY * smoothing) + (deltaY * (1.0 - smoothing));

    double newX = mouseLoc.x + smoothX;
    double newY = mouseLoc.y + smoothY;

    NSLog(@"Touch: frame=%d id=%d state=%d x=%f y=%f size=%f deltaX=%f deltaY=%f smoothX=%f smoothY=%f newX=%f newY=%f", c->frame, c->identifier, c->state, nx, ny, c->size, deltaX, deltaY, smoothX, smoothY, newX, newY);

    // Move cursor relatively
    if (lastNx >= 0.0f && lastNy >= 0.0f) {
        CGWarpMouseCursorPosition(CGPointMake(newX, newY));
    }

    lastNx = nx;
    lastNy = ny;
        // Move cursor relatively, but ignore initial inputs to prevent jump
        if (lastNx >= 0.0f && lastNy >= 0.0f && ignoreInitial == 0) {
            CGWarpMouseCursorPosition(CGPointMake(newX, newY));
        } else if (ignoreInitial > 0) {
            ignoreInitial--;
        }
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
    if (!wasTouching) {
        ignoreInitial = ignoreInitialConfig; // use config value
    }
    // We can't detect release reliably here because the callback doesn't always include a release contact.
    // Instead, approximate: if time since start < 0.15 and size small, synthesize click.
    double duration = timestamp - lastContactStart;
    if (duration < 0.15 && c->size < 0.03) {
        // synthesize a left-click (press + release)
        CGEventRef down = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseDown, CGPointMake(newX, newY), kCGMouseButtonLeft);
        CGEventRef up   = CGEventCreateMouseEvent(NULL, kCGEventLeftMouseUp,   CGPointMake(newX, newY), kCGMouseButtonLeft);
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
    if (!gDevices) {
        NSLog(@"No multitouch devices detected (MTDeviceCreateList returned NULL)");
        return;
    }

    CFIndex count = CFArrayGetCount(gDevices);
    NSLog(@"Detected %ld multitouch device(s)", count);
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

- (BOOL)isRunning {
    return gDevices != NULL;
}

@end
