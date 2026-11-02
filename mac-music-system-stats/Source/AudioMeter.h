#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface IslandAudioMeter : NSObject
- (NSInteger)startForProcess:(int)pid bundleIdentifier:(NSString *)bundleIdentifier;
- (void)setPlaybackActive:(BOOL)active;
- (NSArray<NSNumber *> *)levels;
- (void)stop;
@end
NS_ASSUME_NONNULL_END
