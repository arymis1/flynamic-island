#import "MusicBridge.h"
#import <assert.h>
#import <ScriptingBridge/ScriptingBridge.h>

@interface SpotifyTestTrack : NSObject
@property NSString *name;
@property NSString *artist;
@property NSString *album;
@property NSInteger duration;
@property NSString *artworkUrl;
@property NSString *identifier;
@end
@implementation SpotifyTestTrack
- (NSString *)id { return self.identifier; }
@end
@interface SpotifyTestApp : NSObject
@property BOOL isRunning;
@property SpotifyTestTrack *currentTrack;
@property AEKeyword playerState;
@property double playerPosition;
@property NSInteger soundVolume;
@property NSInteger playCalls;
@property NSInteger pauseCalls;
@property NSInteger nextCalls;
@property NSInteger previousCalls;
@property BOOL shuffling;
@property BOOL shufflingEnabled;
@end
@implementation SpotifyTestApp
- (void)play { self.playCalls++; self.playerState = 'kPSP'; }
- (void)pause { self.pauseCalls++; self.playerState = 'kPSp'; }
- (void)nextTrack { self.nextCalls++; }
- (void)previousTrack { self.previousCalls++; }
@end
int main(void) {
    @autoreleasepool {
        MusicBridge *bridge = [[MusicBridge alloc] initWithBundleIdentifier:@"com.spotify.client"];
        SpotifyTestApp *app = [SpotifyTestApp new];
        SpotifyTestTrack *track = [SpotifyTestTrack new];
        track.name = @"Test song"; track.artist = @"Artist"; track.album = @"Album";
        track.identifier = @"spotify:track:123"; track.duration = 215500;
        track.artworkUrl = @"https://i.scdn.co/image/example";
        app.currentTrack = track; app.isRunning = YES; app.playerState = 'kPSP';
        app.playerPosition = 12.5; app.soundVolume = 42; app.shufflingEnabled = YES;
        [bridge setValue:app forKey:@"application"];
        assert([bridge performCommand:@"shuffle" value:1] && app.shuffling);
        assert([bridge performCommand:@"shuffle" value:1] && app.shuffling);
        assert([[bridge snapshot][@"shuffle"] boolValue]);
        assert([[bridge snapshot][@"shuffleAvailable"] boolValue]);
        assert([bridge performCommand:@"shuffle" value:0] && !app.shuffling);
        app.shuffling = YES;
        assert([[bridge snapshot][@"shuffle"] boolValue]);
        app.shufflingEnabled = NO;
        assert(![bridge performCommand:@"shuffle" value:0] && app.shuffling);
        assert(![[bridge snapshot][@"shuffleAvailable"] boolValue]);
        app.shufflingEnabled = YES; app.shuffling = NO;
        NSDictionary *state = [bridge snapshot];
        assert([state[@"status"] isEqual:@"track"]);
        assert([state[@"id"] isEqual:track.identifier]);
        assert([state[@"title"] isEqual:track.name] && [state[@"artist"] isEqual:track.artist]);
        assert([state[@"album"] isEqual:track.album]);
        assert([state[@"duration"] doubleValue] == 215.5);
        assert([state[@"position"] doubleValue] == 12.5);
        assert([state[@"volume"] integerValue] == 42);
        assert([state[@"artworkURL"] isEqual:track.artworkUrl]);
        assert(![state[@"favoriteAvailable"] boolValue]);
        assert([[bridge setFavorite:YES forTrackID:track.identifier][@"reason"] isEqual:@"unsupported"]);
        assert([bridge performCommand:@"pause" value:0] && app.playerState == 'kPSp');
        assert(![[bridge playbackState][@"playing"] boolValue]);
        assert([bridge performCommand:@"pause" value:0] && app.pauseCalls == 2);
        assert([bridge performCommand:@"play" value:0] && app.playerState == 'kPSP');
        assert([[bridge playbackState][@"playing"] boolValue]);
        assert([bridge performCommand:@"play" value:0] && app.playCalls == 2);
        assert([bridge performCommand:@"next" value:0] && app.nextCalls == 1);
        assert([bridge performCommand:@"previous" value:0] && app.previousCalls == 1);
        assert([bridge performCommand:@"seek" value:30.25] && app.playerPosition == 30.25);
        assert([bridge performCommand:@"volume" value:77] && app.soundVolume == 77);
        track.identifier = @"";
        assert([[bridge snapshot][@"id"] isEqual:@"Test song|Artist|Album"]);
        app.playerState = 'kPSp';
        assert(![[bridge snapshot][@"playing"] boolValue]);
        track.name = @"";
        assert([[bridge snapshot][@"status"] isEqual:@"idle"]);
        app.isRunning = NO;
        assert([[bridge snapshot][@"status"] isEqual:@"closed"]);
        assert([[bridge playbackState][@"status"] isEqual:@"closed"]);
        assert(![bridge performCommand:@"play" value:0] && app.playCalls == 2);
        puts("34 Spotify bridge checks passed: shuffle state, context availability, metadata, millisecond duration, artwork URL, explicit playback, seek, volume, unsupported Favorites, and closed player.");
    }
}
