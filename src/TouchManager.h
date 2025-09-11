// TouchManager.h
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TouchManager : NSObject

+ (instancetype)sharedManager;
- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
