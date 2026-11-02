#import "AudioMeter.h"
#import "AudioBands.h"
#import <CoreAudio/CoreAudio.h>
#import <CoreAudio/CATapDescription.h>
#import <CoreAudio/AudioHardwareTapping.h>
#include <stdatomic.h>
#include <time.h>

@interface IslandAudioMeter () {
    AudioObjectID _tap;
    AudioDeviceID _device;
    AudioDeviceIOProcID _ioProc;
    IslandAudioBands _bands;
    _Atomic(float) _levels[4];
    atomic_bool _active;
    atomic_uint_fast64_t _lastSample;
}
- (void)consume:(const AudioBufferList *)input;
@end

static uint64_t IslandNow(void) { return clock_gettime_nsec_np(CLOCK_UPTIME_RAW); }
static OSStatus IslandAudioIO(AudioObjectID device, const AudioTimeStamp *now, const AudioBufferList *input,
                              const AudioTimeStamp *inputTime, AudioBufferList *output, const AudioTimeStamp *outputTime, void *context) {
    [(__bridge IslandAudioMeter *)context consume:input];
    return noErr;
}

@implementation IslandAudioMeter
- (instancetype)init {
    if ((self = [super init])) {
        atomic_init(&_active, false); atomic_init(&_lastSample, 0);
        for (int i = 0; i < 4; i++) atomic_init(&_levels[i], 0);
    }
    return self;
}
- (NSInteger)startForProcess:(int)pid bundleIdentifier:(NSString *)bundleIdentifier {
    [self stop];
    if (@available(macOS 14.2, *)) {
        AudioObjectID process = kAudioObjectUnknown;
        AudioObjectPropertyAddress address = {kAudioHardwarePropertyTranslatePIDToProcessObject, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
        UInt32 size = sizeof(process);
        OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, sizeof(pid), &pid, &size, &process);
        NSMutableArray<NSNumber *> *processes = [NSMutableArray array];
        NSMutableSet<NSString *> *bundleIDs = [NSMutableSet setWithObject:bundleIdentifier];
        if (status == noErr && process != kAudioObjectUnknown) [processes addObject:@(process)];
        // Chromium-based players can send audio from a helper process rather than the UI process.
        address.mSelector = kAudioHardwarePropertyProcessObjectList;
        size = 0;
        if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, NULL, &size) == noErr && size) {
            AudioObjectID *objects = malloc(size);
            if (objects && AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, objects) == noErr) {
                for (UInt32 i = 0; i < size / sizeof(AudioObjectID); i++) {
                    AudioObjectPropertyAddress property = {kAudioProcessPropertyBundleID, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
                    CFStringRef value = NULL; UInt32 valueSize = sizeof(value);
                    if (AudioObjectGetPropertyData(objects[i], &property, 0, NULL, &valueSize, &value) == noErr && value) {
                        NSString *identifier = CFBridgingRelease(value);
                        if ([identifier isEqual:bundleIdentifier] || [identifier hasPrefix:[bundleIdentifier stringByAppendingString:@"."]]) {
                            if (![processes containsObject:@(objects[i])]) [processes addObject:@(objects[i])];
                            [bundleIDs addObject:identifier];
                        }
                    }
                }
            }
            free(objects);
        }
        if (!processes.count) return status ?: -1;
        CATapDescription *description = [[CATapDescription alloc] initMonoMixdownOfProcesses:processes];
        description.name = @"FLYnamic Island live levels";
        description.privateTap = YES;
        description.muteBehavior = CATapUnmuted;
        if (@available(macOS 26.0, *)) {
            description.bundleIDs = bundleIDs.allObjects;
            description.processRestoreEnabled = YES;
        }
        status = AudioHardwareCreateProcessTap(description, &_tap);
        if (status != noErr) { [self stop]; return status; }
        AudioStreamBasicDescription format = {0};
        address.mSelector = kAudioTapPropertyFormat; size = sizeof(format);
        status = AudioObjectGetPropertyData(_tap, &address, 0, NULL, &size, &format);
        if (status != noErr || format.mFormatID != kAudioFormatLinearPCM || !(format.mFormatFlags & kAudioFormatFlagIsFloat) || format.mBitsPerChannel != 32) { [self stop]; return -2; }
        IslandAudioBandsInit(&_bands, format.mSampleRate);
        CFStringRef tapUID = NULL;
        address.mSelector = kAudioTapPropertyUID; size = sizeof(tapUID);
        status = AudioObjectGetPropertyData(_tap, &address, 0, NULL, &size, &tapUID);
        if (status != noErr || !tapUID) { [self stop]; return status ?: -3; }
        NSDictionary *aggregate = @{
            @kAudioAggregateDeviceNameKey: @"FLYnamic Island (private)",
            @kAudioAggregateDeviceUIDKey: NSUUID.UUID.UUIDString,
            @kAudioAggregateDeviceIsPrivateKey: @YES,
            @kAudioAggregateDeviceTapAutoStartKey: @YES,
            @kAudioAggregateDeviceTapListKey: @[@{@kAudioSubTapUIDKey: (__bridge NSString *)tapUID,
                                                  @kAudioSubTapDriftCompensationKey: @YES}]
        };
        status = AudioHardwareCreateAggregateDevice((__bridge CFDictionaryRef)aggregate, &_device);
        CFRelease(tapUID);
        if (status != noErr) { [self stop]; return status; }
        status = AudioDeviceCreateIOProcID(_device, IslandAudioIO, (__bridge void *)self, &_ioProc);
        if (status == noErr) status = AudioDeviceStart(_device, _ioProc);
        if (status != noErr) { [self stop]; return status; }
        return noErr;
    }
    return -4;
}
- (void)setPlaybackActive:(BOOL)active {
    atomic_store_explicit(&_active, active, memory_order_relaxed);
    if (!active) for (int i = 0; i < 4; i++) atomic_store_explicit(&_levels[i], 0, memory_order_relaxed);
}
- (void)consume:(const AudioBufferList *)input {
    if (!atomic_load_explicit(&_active, memory_order_relaxed) || !input || !input->mNumberBuffers) return;
    const AudioBuffer *buffer = &input->mBuffers[0];
    if (!buffer->mData || !buffer->mNumberChannels) return;
    const float *samples = buffer->mData;
    const unsigned channels = buffer->mNumberChannels;
    const unsigned frames = buffer->mDataByteSize / (sizeof(float) * channels);
    for (unsigned frame = 0; frame < frames; frame++) {
        float value = 0;
        for (unsigned channel = 0; channel < channels; channel++) value += samples[frame * channels + channel];
        if (IslandAudioBandsFeed(&_bands, value / channels)) {
            for (int i = 0; i < 4; i++) atomic_store_explicit(&_levels[i], _bands.levels[i], memory_order_relaxed);
        }
    }
    atomic_store_explicit(&_lastSample, IslandNow(), memory_order_relaxed);
}
- (NSArray<NSNumber *> *)levels {
    uint64_t last = atomic_load_explicit(&_lastSample, memory_order_relaxed);
    if (!atomic_load_explicit(&_active, memory_order_relaxed) || !last || IslandNow() - last > 150000000) return @[@0, @0, @0, @0];
    return @[@(atomic_load_explicit(&_levels[0], memory_order_relaxed)), @(atomic_load_explicit(&_levels[1], memory_order_relaxed)),
             @(atomic_load_explicit(&_levels[2], memory_order_relaxed)), @(atomic_load_explicit(&_levels[3], memory_order_relaxed))];
}
- (void)stop {
    [self setPlaybackActive:NO];
    if (_device && _ioProc) { AudioDeviceStop(_device, _ioProc); AudioDeviceDestroyIOProcID(_device, _ioProc); }
    _ioProc = NULL;
    if (_device) AudioHardwareDestroyAggregateDevice(_device);
    _device = kAudioObjectUnknown;
    if (@available(macOS 14.2, *)) { if (_tap) AudioHardwareDestroyProcessTap(_tap); }
    _tap = kAudioObjectUnknown;
}
- (void)dealloc { [self stop]; }
@end
