#import "MusicBridge.h"
#import <ScriptingBridge/ScriptingBridge.h>
#import <Carbon/Carbon.h>
#import <CoreAudio/CoreAudio.h>

static NSArray *IslandSystemOutputs(BOOL musicUsesSystem) {
    AudioObjectPropertyAddress address = {kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    AudioDeviceID current = kAudioObjectUnknown;
    UInt32 size = sizeof(current);
    AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, &current);
    address.mSelector = kAudioHardwarePropertyDevices;
    size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, NULL, &size) != noErr || !size) return @[];
    AudioDeviceID *devices = malloc(size);
    if (!devices) return @[];
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &size, devices) != noErr) { free(devices); return @[]; }
    NSMutableArray *result = [NSMutableArray array];
    for (UInt32 i = 0; i < size / sizeof(AudioDeviceID); i++) {
        AudioDeviceID device = devices[i];
        AudioObjectPropertyAddress output = {kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput, kAudioObjectPropertyElementMain};
        UInt32 streamSize = 0;
        if (AudioObjectGetPropertyDataSize(device, &output, 0, NULL, &streamSize) != noErr || !streamSize) continue;
        CFStringRef name = NULL;
        output.mSelector = kAudioObjectPropertyName; output.mScope = kAudioObjectPropertyScopeGlobal;
        UInt32 nameSize = sizeof(name);
        if (AudioObjectGetPropertyData(device, &output, 0, NULL, &nameSize, &name) != noErr || !name) continue;
        NSString *label = CFBridgingRelease(name);
        UInt32 transport = 0, transportSize = sizeof(transport);
        output.mSelector = kAudioDevicePropertyTransportType;
        AudioObjectGetPropertyData(device, &output, 0, NULL, &transportSize, &transport);
        BOOL headphones = transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE;
        NSString *symbol = headphones ? @"headphones" : (transport == kAudioDeviceTransportTypeBuiltIn ? @"laptopcomputer" : (transport == kAudioDeviceTransportTypeHDMI || transport == kAudioDeviceTransportTypeDisplayPort ? @"tv" : @"speaker.wave.2"));
        [result addObject:@{@"id": [NSString stringWithFormat:@"system:%u", device], @"name": label,
                           @"selected": @(musicUsesSystem && device == current), @"available": @YES, @"symbol": symbol}];
    }
    free(devices);
    return result;
}

// Selectors and event codes come from com.apple.Music.sdef, shipped with macOS.
@protocol IslandArtwork
@property(readonly) id data;
@property(readonly) id rawData;
@end
@protocol IslandTrack
@property(readonly) NSString *name;
@property(readonly) NSString *artist;
@property(readonly) NSString *album;
@property(readonly) NSString *persistentID;
@property(readonly) double duration;
@property BOOL favorited;
@property(readonly) NSInteger databaseID;
- (NSInteger)id;
- (SBElementArray *)artworks;
@end
@protocol IslandMusic
@property(readonly) AEKeyword playerState;
@property(readonly) id<IslandTrack> currentTrack;
@property double playerPosition;
@property NSInteger soundVolume;
@property BOOL shuffleEnabled;
- (void)playOnce:(BOOL)once;
- (void)pause;
- (void)nextTrack;
- (void)previousTrack;
- (SBElementArray *)tracks;
@end
@protocol IslandSpotifyTrack
@property(readonly) NSString *name;
@property(readonly) NSString *artist;
@property(readonly) NSString *album;
@property(readonly) NSInteger duration;
@property(readonly) NSString *artworkUrl;
- (NSString *)id;
@end
@protocol IslandSpotify <IslandMusic>
@property BOOL shuffling;
@property(readonly) BOOL shufflingEnabled;
- (void)play;
@end
@interface MusicBridge () <SBApplicationDelegate>
@property NSString *bundleIdentifier;
@property SBApplication *application;
@property NSError *lastError;
@property NSString *artworkID;
@property NSImage *artwork;
@property NSTimeInterval nextArtworkAttempt;
@property NSInteger artworkAttempts;
@property NSString *favoriteTargetID;
@property id<IslandTrack> favoriteTarget;
@end

@implementation MusicBridge
- (id<IslandTrack>)resolvedTrack:(id<IslandTrack>)track {
    if ([(id)track isKindOfClass:SBObject.class]) {
        id resolved = [(SBObject *)track get];
        if (resolved) return resolved;
    }
    return track;
}
- (BOOL)favoriteForTrack:(id<IslandTrack>)track {
    if ([(id)track isKindOfClass:SBObject.class]) {
        id value = [[(SBObject *)track propertyWithCode:'pLov'] get];
        return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
    }
    return track.favorited;
}
- (id<IslandTrack>)favoriteTargetForTrack:(id<IslandTrack>)track {
    if (![(id)track isKindOfClass:SBObject.class]) return track;
    NSString *identifier = [self identifierForTrack:track];
    if ([self.favoriteTargetID isEqual:identifier] && self.favoriteTarget) return self.favoriteTarget;
    self.favoriteTargetID = identifier;
    self.favoriteTarget = track;
    @try {
        // Queue entries can carry stale favorite flags. Prefer the underlying library item.
        NSInteger databaseID = track.databaseID;
        if (databaseID > 0) {
            SBElementArray *tracks = [(id<IslandMusic>)self.application tracks];
            id<IslandTrack> candidate = (id)[tracks objectWithID:@(databaseID)];
            if ([candidate.name isEqual:track.name] && [candidate.artist isEqual:track.artist]) self.favoriteTarget = candidate;
        }
    } @catch (NSException *exception) { /* Current-track reference remains available. */ }
    self.lastError = nil;
    return self.favoriteTarget;
}
- (NSString *)identifierForTrack:(id<IslandTrack>)track {
    NSString *identifier = track.persistentID;
    return identifier.length ? identifier : [NSString stringWithFormat:@"%@|%@|%@", track.name ?: @"", track.artist ?: @"", track.album ?: @""];
}
- (instancetype)init {
    return [self initWithBundleIdentifier:@"com.apple.Music"];
}
- (instancetype)initWithBundleIdentifier:(NSString *)bundleIdentifier {
    if ((self = [super init])) {
        _bundleIdentifier = [bundleIdentifier copy];
        [self connectToRunningMusic];
    }
    return self;
}
- (void)connectToRunningMusic {
    // A process target cannot relaunch Music if it quits during an in-flight read.
    NSRunningApplication *running = nil;
    for (NSRunningApplication *candidate in [NSRunningApplication runningApplicationsWithBundleIdentifier:self.bundleIdentifier]) {
        if (!candidate.isTerminated) { running = candidate; break; }
    }
    self.application = running ? [SBApplication applicationWithProcessIdentifier:running.processIdentifier] : nil;
    self.application.delegate = self;
    self.application.timeout = 2 * 60; // Apple-event ticks: two seconds.
    self.artworkID = nil; self.artwork = nil;
    self.favoriteTargetID = nil; self.favoriteTarget = nil;
    self.nextArtworkAttempt = 0; self.artworkAttempts = 0;
}
- (id)eventDidFail:(const AppleEvent *)event withError:(NSError *)error {
    self.lastError = error;
    return nil;
}
- (NSInteger)permissionRequestingConsent:(BOOL)request {
    const char *bundle = self.bundleIdentifier.UTF8String;
    AEAddressDesc target = {typeNull, NULL};
    OSStatus status = AECreateDesc(typeApplicationBundleID, bundle, strlen(bundle), &target);
    if (status == noErr) {
        status = AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, request);
        AEDisposeDesc(&target);
    }
    return status;
}
- (NSDictionary *)snapshot {
    if (!self.application.isRunning) return @{@"status": @"closed"};
    if ([self.bundleIdentifier isEqual:@"com.spotify.client"]) return [self spotifySnapshot];
    self.lastError = nil;
    @try {
        id<IslandMusic> music = (id)self.application;
        AEKeyword state = music.playerState;
        if (self.lastError) return @{@"status": @"error", @"code": @(self.lastError.code)};
        if (state == 'kPSS') return @{@"status": @"idle"};
        id<IslandTrack> track = [self resolvedTrack:music.currentTrack];
        NSString *title = track.name;
        if (!title.length) return @{@"status": @"idle"};
        NSString *artist = track.artist ?: @"";
        NSString *album = track.album ?: @"";
        NSString *trackID = [self identifierForTrack:track];
        if (![self.artworkID isEqualToString:trackID]) {
            self.artworkID = trackID;
            self.artwork = nil;
            self.nextArtworkAttempt = 0;
            self.artworkAttempts = 0;
        }
        if (!self.artwork && NSProcessInfo.processInfo.systemUptime >= self.nextArtworkAttempt) {
            self.artworkAttempts += 1;
            self.nextArtworkAttempt = NSProcessInfo.processInfo.systemUptime + MIN(8, pow(2, MIN(3, self.artworkAttempts - 1)));
            SBElementArray *artworks = [track artworks];
            if (artworks.count > 0) {
                id<IslandArtwork> art = (id)[artworks objectAtIndex:0];
                id raw = art.rawData;
                if ([raw isKindOfClass:SBObject.class]) raw = [raw get];
                if ([raw isKindOfClass:[NSImage class]]) self.artwork = raw;
                else if ([raw isKindOfClass:[NSData class]]) self.artwork = [[NSImage alloc] initWithData:raw];
                else if ([raw isKindOfClass:NSAppleEventDescriptor.class]) self.artwork = [[NSImage alloc] initWithData:[raw data]];
                if (!self.artwork) {
                    raw = art.data;
                    if ([raw isKindOfClass:SBObject.class]) raw = [raw get];
                    if ([raw isKindOfClass:[NSImage class]]) self.artwork = raw;
                    else if ([raw isKindOfClass:[NSData class]]) self.artwork = [[NSImage alloc] initWithData:raw];
                    else if ([raw isKindOfClass:NSAppleEventDescriptor.class]) self.artwork = [[NSImage alloc] initWithData:[raw data]];
                }
            }
        }
        NSMutableDictionary *result = [@{
            @"status": @"track", @"title": title, @"artist": artist,
            @"album": album, @"id": trackID, @"playing": @(state == 'kPSP'),
            @"position": @(music.playerPosition), @"duration": @(track.duration),
            @"volume": @(music.soundVolume)
        } mutableCopy];
        self.lastError = nil;
        BOOL favorited = [self favoriteForTrack:[self favoriteTargetForTrack:track]];
        result[@"favoriteAvailable"] = @(self.lastError == nil);
        result[@"favorited"] = @(favorited);
        if (self.artwork) result[@"artwork"] = self.artwork;
        [result addEntriesFromDictionary:[self shuffleState]];
        return result;
    } @catch (NSException *exception) {
        return @{@"status": @"error", @"code": @(-1)};
    }
}
- (NSDictionary *)spotifySnapshot {
    self.lastError = nil;
    @try {
        id<IslandSpotify> spotify = (id)self.application;
        AEKeyword state = spotify.playerState;
        if (self.lastError) return @{@"status": @"error", @"code": @(self.lastError.code)};
        id<IslandSpotifyTrack> track = (id)[self resolvedTrack:(id)spotify.currentTrack];
        NSString *name = track.name;
        if (!name.length) return @{@"status": @"idle"};
        NSString *identifier = [track id];
        NSString *artist = track.artist ?: @"";
        NSString *album = track.album ?: @"";
        // Spotify's desktop interface reports duration in milliseconds, position in seconds.
        NSMutableDictionary *result = [@{@"status": @"track", @"title": name, @"artist": artist, @"album": album,
                 @"id": identifier.length ? identifier : [NSString stringWithFormat:@"%@|%@|%@", name, artist, album],
                 @"playing": @(state == 'kPSP'), @"position": @(spotify.playerPosition),
                 @"duration": @(MAX(0, track.duration) / 1000.0), @"volume": @(spotify.soundVolume),
                 @"artworkURL": track.artworkUrl ?: @"", @"favoriteAvailable": @NO, @"favorited": @NO} mutableCopy];
        [result addEntriesFromDictionary:[self shuffleState]];
        return result;
    } @catch (NSException *exception) { return @{@"status": @"error", @"code": @(-1)}; }
}
- (NSDictionary *)shuffleState {
    self.lastError = nil;
    @try {
        BOOL available = YES;
        BOOL enabled;
        BOOL spotifySource = [self.bundleIdentifier isEqual:@"com.spotify.client"];
        if ([(id)self.application isKindOfClass:SBObject.class]) {
            SBObject *application = (id)self.application;
            id value = [[application propertyWithCode:spotifySource ? 'pShu' : 'pShE'] get];
            enabled = [value isKindOfClass:NSAppleEventDescriptor.class] ? [value booleanValue] : ([value respondsToSelector:@selector(boolValue)] && [value boolValue]);
            if (spotifySource) {
                value = [[application propertyWithCode:'pReE'] get];
                available = [value isKindOfClass:NSAppleEventDescriptor.class] ? [value booleanValue] : ([value respondsToSelector:@selector(boolValue)] && [value boolValue]);
            }
        } else if (spotifySource) {
            id<IslandSpotify> spotify = (id)self.application;
            available = spotify.shufflingEnabled;
            enabled = spotify.shuffling;
        } else { enabled = ((id<IslandMusic>)self.application).shuffleEnabled; }
        return @{@"shuffle": @(enabled), @"shuffleAvailable": @(available && self.lastError == nil)};
    } @catch (NSException *exception) { return @{@"shuffle": @NO, @"shuffleAvailable": @NO}; }
}
- (NSDictionary *)playbackState {
    if (!self.application.isRunning) return @{@"status": @"closed"};
    self.lastError = nil;
    @try {
        id<IslandMusic> music = (id)self.application;
        AEKeyword state = music.playerState;
        double position = music.playerPosition;
        if (self.lastError) return @{@"status": @"error"};
        return @{@"status": @"ready", @"playing": @(state == 'kPSP'), @"position": @(position)};
    } @catch (NSException *exception) { return @{@"status": @"error"}; }
}
- (NSDictionary *)setFavorite:(BOOL)favorite forTrackID:(NSString *)trackID {
    if ([self.bundleIdentifier isEqual:@"com.spotify.client"]) return @{@"success": @NO, @"reason": @"unsupported"};
    if (!self.application.isRunning) return @{@"success": @NO, @"reason": @"closed"};
    self.lastError = nil;
    @try {
        id<IslandTrack> track = [self resolvedTrack:((id<IslandMusic>)self.application).currentTrack];
        // Bind the write to the song the user saw, even if playback advanced meanwhile.
        if (!track.name.length || ![[self identifierForTrack:track] isEqualToString:trackID]) {
            return @{@"success": @NO, @"reason": @"changed"};
        }
        self.lastError = nil;
        track = [self favoriteTargetForTrack:track];
        BOOL before = [self favoriteForTrack:track];
        if (self.lastError) return @{@"success": @NO, @"reason": @"unavailable", @"code": @(self.lastError.code)};
        if (before != favorite) {
            if ([(id)track isKindOfClass:SBObject.class]) [[(SBObject *)track propertyWithCode:'pLov'] setTo:@(favorite)];
            else track.favorited = favorite;
        }
        if (self.lastError) return @{@"success": @NO, @"reason": @"failed", @"code": @(self.lastError.code)};
        BOOL confirmed = [self favoriteForTrack:track];
        // Music may accept a write before its library/cloud state reflects it.
        // The UI verifies subsequent fresh snapshots instead of treating that delay as failure.
        return @{@"success": @YES, @"confirmed": @(self.lastError == nil && confirmed == favorite),
                 @"favorited": @(confirmed), @"reason": confirmed == favorite ? @"confirmed" : @"pending"};
    } @catch (NSException *exception) {
        return @{@"success": @NO, @"reason": @"failed"};
    }
}
- (BOOL)performCommand:(NSString *)command value:(double)value {
    if (!self.application.isRunning) return NO;
    self.lastError = nil;
    @try {
        id<IslandMusic> music = (id)self.application;
        if ([command isEqualToString:@"play"]) {
            if ([self.bundleIdentifier isEqual:@"com.spotify.client"]) [(id<IslandSpotify>)music play];
            else [music playOnce:NO];
        }
        else if ([command isEqualToString:@"pause"]) [music pause];
        else if ([command isEqualToString:@"next"]) [music nextTrack];
        else if ([command isEqualToString:@"previous"]) [music previousTrack];
        else if ([command isEqualToString:@"seek"]) music.playerPosition = MAX(0, value);
        else if ([command isEqualToString:@"volume"]) music.soundVolume = (NSInteger)MAX(0, MIN(100, value));
        else if ([command isEqualToString:@"shuffle"]) {
            BOOL spotifySource = [self.bundleIdentifier isEqual:@"com.spotify.client"];
            if ([(id)self.application isKindOfClass:SBObject.class]) {
                if (![[self shuffleState][@"shuffleAvailable"] boolValue]) return NO;
                [[(SBObject *)self.application propertyWithCode:spotifySource ? 'pShu' : 'pShE'] setTo:[NSAppleEventDescriptor descriptorWithBoolean:value != 0]];
            } else if (spotifySource) {
                id<IslandSpotify> spotify = (id)music;
                if (!spotify.shufflingEnabled || self.lastError) return NO;
                spotify.shuffling = value != 0;
            } else { music.shuffleEnabled = value != 0; }
        }
        else return NO;
        return self.lastError == nil;
    } @catch (NSException *exception) { return NO; }
}
- (NSDictionary *)airPlayOutputs {
    // The Mac owns routing. Reading the picker never queries or changes Music's AirPlay context.
    return @{@"status": @"ready", @"outputs": IslandSystemOutputs(YES)};
}
- (BOOL)selectAirPlayOutput:(NSString *)identifier {
    if (![identifier hasPrefix:@"system:"]) return NO;
    BOOL exists = NO;
    for (NSDictionary *output in IslandSystemOutputs(YES)) {
        if ([output[@"id"] isEqual:identifier]) {
            if ([output[@"selected"] boolValue]) return YES;
            exists = YES;
            break;
        }
    }
    if (!exists) return NO;
    AudioDeviceID device = (AudioDeviceID)[[identifier substringFromIndex:7] longLongValue];
    AudioObjectPropertyAddress address = {kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    return AudioObjectSetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, sizeof(device), &device) == noErr;
}
@end
