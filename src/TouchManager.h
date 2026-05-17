// TouchManager.h
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TouchManager : NSObject

+ (instancetype)sharedManager;
- (void)start;
- (void)stop;

- (BOOL)isRunning;

// Check for firmware updates. The URL to query can be set in `config.txt` as
// `firmware_check_url=https://example.com/firmware.json` which should return
// a JSON object like `{ "latest": "1.2.3", "url": "https://…" }`.
- (void)checkForFirmwareUpdatesWithCompletion:(void(^)(BOOL updateAvailable, NSString * _Nullable latestVersion, NSString * _Nullable updateURL))completion;

@end

NS_ASSUME_NONNULL_END
