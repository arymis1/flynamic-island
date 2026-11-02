#import "MusicBridge.h"
#import <CoreAudio/CoreAudio.h>
#include <assert.h>
int main(void) {
    @autoreleasepool {
        MusicBridge *bridge = [MusicBridge new];
        NSDictionary *snapshot = [bridge airPlayOutputs];
        assert([snapshot[@"status"] isEqual:@"ready"]);
        AudioDeviceID current = kAudioObjectUnknown;
        AudioObjectPropertyAddress address = {kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
        UInt32 size = sizeof(current);
        assert(AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, &current) == noErr);
        NSString *currentID = [NSString stringWithFormat:@"system:%u", current];
        NSMutableSet *ids = [NSMutableSet set];
        BOOL foundCurrent = NO;
        for (NSDictionary *row in snapshot[@"outputs"]) {
            assert([row[@"id"] hasPrefix:@"system:"]);
            assert(![ids containsObject:row[@"id"]]);
            [ids addObject:row[@"id"]];
            if ([row[@"selected"] boolValue]) {
                assert([row[@"id"] isEqual:currentID]);
                foundCurrent = YES;
            }
        }
        assert(foundCurrent);
        assert([bridge selectAirPlayOutput:currentID]);
        assert(![bridge selectAirPlayOutput:@"music:7"]);
        assert(![bridge selectAirPlayOutput:@"system:9999999"]);
        assert(![bridge selectAirPlayOutput:@""]);
        AudioDeviceID after = 0; size = sizeof(after);
        assert(AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, &after) == noErr);
        assert(after == current);
        puts("System-output checks passed: selected row matches macOS, no duplicate devices, Music-specific routes rejected, no output change during tests.");
    }
}
