// TouchManager.h
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TouchManager : NSObject

+ (instancetype)sharedManager;
- (void)start;
- (void)stop;

- (BOOL)isRunning;

@end

NS_ASSUME_NONNULL_END
