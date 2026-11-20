#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN
// Call this object on one serial queue. It uses Music's public scripting interface.
@interface MusicBridge : NSObject
- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier;
- (void)connectToRunningMusic;
- (BOOL)connectToProcessIdentifier:(pid_t)pid;
- (NSInteger)permissionRequestingConsent:(BOOL)request;
- (NSDictionary<NSString *, id> *)snapshot;
- (NSDictionary<NSString *, id> *)snapshotForRunningProcessIdentifier:(pid_t)pid;
- (NSDictionary<NSString *, id> *)playbackState;
- (BOOL)performCommand:(NSString *)command value:(double)value;
- (NSDictionary<NSString *, id> *)setFavorite:(BOOL)favorite forTrackID:(NSString *)trackID;
- (NSDictionary<NSString *, id> *)airPlayOutputs;
- (BOOL)selectAirPlayOutput:(NSString *)identifier;
@end
NS_ASSUME_NONNULL_END
