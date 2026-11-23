#import <AppKit/AppKit.h>
NS_ASSUME_NONNULL_BEGIN
@interface ChromeBridge : NSObject
- (NSInteger)permissionRequestingConsent:(BOOL)request;
- (NSDictionary<NSString *, id> *)snapshot;
- (BOOL)performCommand:(NSString *)command value:(double)value trackID:(NSString *)trackID expectedPID:(pid_t)pid;
+ (BOOL)isYouTubeMusicURL:(NSString *)value;
@end
NS_ASSUME_NONNULL_END
