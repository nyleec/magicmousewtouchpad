// TouchManager.m
#import "TouchManager.h"
#import <CoreGraphics/CoreGraphics.h>
#import <CoreFoundation/CoreFoundation.h>
#import <IOKit/hid/IOHIDManager.h>
#import <IOKit/hid/IOHIDKeys.h>
#import <Foundation/Foundation.h>

// Use the private MultitouchSupport framework
// Link with -F/System/Library/PrivateFrameworks -framework MultitouchSupport

// Minimal finger struct extracted from community examples
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
    // We only use normalized x/y here
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
    static float startNx = -1.0f;
    static float startNy = -1.0f;

    // Get main display size
    CGSize screenSize = CGDisplayBounds(CGMainDisplayID()).size;
    CGEventRef locEvent = CGEventCreate(NULL);
    CGPoint mouseLoc = CGEventGetLocation(locEvent);
    if (locEvent) CFRelease(locEvent);

    static int ignoreInitial = 0;
    static int ignoreInitialConfig = 3;
    static double sensitivity = 0.35;
    static double smoothing = 0.5;
    static double tapTimeThreshold = 0.15; // seconds
    static double tapSizeThreshold = 0.03; // normalized size
    static double tapMoveThreshold = 10.0; // pixels
    static double pushSizeThreshold = 0.5; // normalized size (heuristic)
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
                } else if ([line hasPrefix:@"tap_time_threshold="]) {
                    tapTimeThreshold = [[line substringFromIndex:19] doubleValue];
                } else if ([line hasPrefix:@"tap_size_threshold="]) {
                    tapSizeThreshold = [[line substringFromIndex:19] doubleValue];
                } else if ([line hasPrefix:@"tap_move_threshold="]) {
                    tapMoveThreshold = [[line substringFromIndex:19] doubleValue];
                } else if ([line hasPrefix:@"push_size_threshold="]) {
                    pushSizeThreshold = [[line substringFromIndex:20] doubleValue];
                }
            }
        }
        configRead = 1;
    }


    // Initialize start position when contact begins
    static BOOL contactIsActive = NO;
    static BOOL didFireClick = NO;
    static double lastContactStart = 0;
    static int activeContactCount = 0;
    static int currentContactId = -1;
    static float lastSize = -1.0f;
    if (!contactIsActive || timestamp - lastContactStart > 1.0 || c->identifier != currentContactId) {
        contactIsActive = YES;
        didFireClick = NO;
        lastContactStart = timestamp;
        activeContactCount = count;
        currentContactId = c->identifier;
        startNx = nx;
        startNy = ny;
        lastSize = c->size;
        smoothX = 0.0;
        smoothY = 0.0;
        lastNx = nx;
        lastNy = ny;
    }

    double deltaX = 0.0, deltaY = 0.0;
    if (lastNx >= 0.0f && lastNy >= 0.0f) {
        deltaX = (nx - lastNx) * screenSize.width * sensitivity;
        deltaY = (ny - lastNy) * screenSize.height * sensitivity;
    }

    // Movement since contact start (pixels)
    double moveFromStartX = (nx - startNx) * screenSize.width * sensitivity;
    double moveFromStartY = (ny - startNy) * screenSize.height * sensitivity;
    double moveFromStartMag = sqrt(moveFromStartX*moveFromStartX + moveFromStartY*moveFromStartY);

    // Apply smoothing
    smoothX = (smoothX * smoothing) + (deltaX * (1.0 - smoothing));
    smoothY = (smoothY * smoothing) + (deltaY * (1.0 - smoothing));

    double newX = mouseLoc.x + smoothX;
    double newY = mouseLoc.y + smoothY;

    NSLog(@"Touch: frame=%d id=%d state=%d x=%f y=%f size=%f deltaX=%f deltaY=%f smoothX=%f smoothY=%f newX=%f newY=%f moveFromStart=%f", c->frame, c->identifier, c->state, nx, ny, c->size, deltaX, deltaY, smoothX, smoothY, newX, newY, moveFromStartMag);

    double duration = timestamp - lastContactStart;
    BOOL isQuickTap = (duration < tapTimeThreshold && c->size < tapSizeThreshold && moveFromStartMag < tapMoveThreshold && lastSize >= 0.0f);
    BOOL isPushClick = (lastSize >= 0.0f && c->size > pushSizeThreshold && (c->size - lastSize) > 0.3);

    if (didFireClick) {
        lastSize = c->size;
        return 0;
    }

    if (isQuickTap || isPushClick) {
        int fingerCount = MAX(1, count);
        BOOL useRightClick = (fingerCount >= 2 && isQuickTap);
        CGEventType downType = useRightClick ? kCGEventRightMouseDown : kCGEventLeftMouseDown;
        CGEventType upType = useRightClick ? kCGEventRightMouseUp : kCGEventLeftMouseUp;
        CGMouseButton button = useRightClick ? kCGMouseButtonRight : kCGMouseButtonLeft;

        CGEventRef down = CGEventCreateMouseEvent(NULL, downType, CGPointMake(newX, newY), button);
        CGEventRef up = CGEventCreateMouseEvent(NULL, upType, CGPointMake(newX, newY), button);
        if (down && up) {
            CGEventPost(kCGAnnotatedSessionEventTap, down);
            CGEventPost(kCGAnnotatedSessionEventTap, up);
        }
        if (down) CFRelease(down);
        if (up) CFRelease(up);

        didFireClick = YES;
        lastSize = c->size;
        lastNx = nx;
        lastNy = ny;
        return 0;
    }

    lastSize = c->size;
    // Move cursor relatively by synthesizing a mouse-move event.
    if (lastNx >= 0.0f && lastNy >= 0.0f) {
        CGEventRef moveEvent = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved, CGPointMake(newX, newY), kCGMouseButtonLeft);
        if (moveEvent) {
            CGEventPost(kCGAnnotatedSessionEventTap, moveEvent);
            CFRelease(moveEvent);
        }
    }

    lastNx = nx;
    lastNy = ny;
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



// Firmware check implementation
// Reads `firmware_check_url` from config.txt (if present), queries the URL
// for JSON { "latest": "x.y.z", "url": "https://..." }, finds the
// connected HID device firmware (if available) and calls completion with
// whether an update is recommended.

- (void)checkForFirmwareUpdatesWithCompletion:(void(^)(BOOL updateAvailable, NSString * _Nullable latestVersion, NSString * _Nullable updateURL))completion {
    // Read firmware_check_url from config.txt in bundle
    NSString *configPath = [[NSBundle mainBundle] pathForResource:@"config" ofType:@"txt"];
    NSString *firmwareURLString = nil;
    if (configPath) {
        NSString *contents = [NSString stringWithContentsOfFile:configPath encoding:NSUTF8StringEncoding error:nil];
        if (contents) {
            NSArray *lines = [contents componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
            for (NSString *line in lines) {
                if ([line hasPrefix:@"firmware_check_url="]) {
                    firmwareURLString = [line substringFromIndex:[@"firmware_check_url=" length]];
                    firmwareURLString = [firmwareURLString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    break;
                }
            }
        }
    }

    if (!firmwareURLString || firmwareURLString.length == 0) {
        if (completion) completion(NO, nil, nil);
        return;
    }

    // Attempt to discover firmware version from connected HID devices
    __block NSString *currentFirmware = nil;
    IOHIDManagerRef hidManager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (hidManager) {
        IOHIDManagerSetDeviceMatching(hidManager, NULL);
        IOReturn r = IOHIDManagerOpen(hidManager, kIOHIDOptionsTypeNone);
        if (r == kIOReturnSuccess) {
            CFSetRef devices = IOHIDManagerCopyDevices(hidManager);
            if (devices) {
                CFIndex count = CFSetGetCount(devices);
                IOHIDDeviceRef *devs = malloc(sizeof(IOHIDDeviceRef) * count);
                CFSetGetValues(devices, (const void **)devs);
                for (CFIndex i = 0; i < count; i++) {
                    IOHIDDeviceRef d = devs[i];
                    CFTypeRef prod = IOHIDDeviceGetProperty(d, CFSTR("Product"));
                    CFStringRef product = NULL;
                    if (prod && CFGetTypeID(prod) == CFStringGetTypeID()) product = (CFStringRef)prod;

                    // Try several common firmware property keys
                    CFTypeRef fw = IOHIDDeviceGetProperty(d, CFSTR("FirmwareRevision"));
                    if (!fw) fw = IOHIDDeviceGetProperty(d, CFSTR("FirmwareVersion"));
                    if (!fw) fw = IOHIDDeviceGetProperty(d, CFSTR("firmware"));

                    if (fw && CFGetTypeID(fw) == CFStringGetTypeID()) {
                        NSString *fwStr = (__bridge NSString *)(fw);
                        // Prefer devices that look like a mouse
                        if (product) {
                            NSString *prodStr = (__bridge NSString *)(product);
                            if ([[prodStr lowercaseString] containsString:@"mouse"] || [[prodStr lowercaseString] containsString:@"magic"]) {
                                currentFirmware = [fwStr copy];
                                break;
                            }
                        }
                        if (!currentFirmware) currentFirmware = [fwStr copy];
                    }
                }
                free(devs);
                CFRelease(devices);
            }
        }
        IOHIDManagerClose(hidManager, kIOHIDOptionsTypeNone);
        CFRelease(hidManager);
    }

    NSURL *url = [NSURL URLWithString:firmwareURLString];
    if (!url) { if (completion) completion(NO, nil, nil); return; }

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error || !data) {
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, nil, nil); });
            return;
        }
        NSError *jsonErr = nil;
        NSDictionary *obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonErr];
        if (jsonErr || ![obj isKindOfClass:[NSDictionary class]]) {
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, nil, nil); });
            return;
        }
        NSString *latest = obj[@"latest"] ?: obj[@"version"];
        NSString *updateURL = obj[@"url"] ?: obj[@"download_url"];
        if (!latest) {
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(NO, nil, nil); });
            return;
        }

        BOOL shouldUpdate = NO;
        if (currentFirmware && currentFirmware.length > 0) {
            NSComparisonResult cmp = [currentFirmware compare:latest options:NSNumericSearch];
            if (cmp == NSOrderedAscending) shouldUpdate = YES;
        } else {
            // Unknown current firmware — recommend update so user can verify
            shouldUpdate = YES;
        }

        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(shouldUpdate, latest, updateURL); });
    }];
    [task resume];
}

    @end
