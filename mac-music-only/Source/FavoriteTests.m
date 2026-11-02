#import "MusicBridge.h"
#import <assert.h>
#import <ScriptingBridge/ScriptingBridge.h>

// These tests use a stand-in for Music, leaving the user's library untouched.
@interface FavoriteTestTrack : NSObject
@property NSString *persistentID;
@property NSString *name;
@property NSString *artist;
@property NSString *album;
@property(nonatomic) BOOL favorited;
@property BOOL refuseWrites;
@property NSInteger writes;
@property double duration;
@property NSArray *artworkItems;
@end
@implementation FavoriteTestTrack
- (id)artworks { return self.artworkItems ?: @[]; }
- (void)setFavorited:(BOOL)value {
    self.writes += 1;
    if (!self.refuseWrites) _favorited = value;
}
@end

@interface FavoriteTestMusic : NSObject
@property BOOL isRunning;
@property FavoriteTestTrack *currentTrack;
@property AEKeyword playerState;
@property double playerPosition;
@property NSInteger soundVolume;
@property NSInteger playCalls;
@property NSInteger pauseCalls;
@property BOOL shuffleEnabled;
@end
@implementation FavoriteTestMusic
- (void)playOnce:(BOOL)once { assert(!once); self.playCalls += 1; self.playerState = 'kPSP'; }
- (void)pause { self.pauseCalls += 1; self.playerState = 'kPSp'; }
@end

@interface FavoriteTestArtwork : NSObject
@property id rawData;
@end
@implementation FavoriteTestArtwork
@end

@interface FavoriteTestReference : NSObject
@property FavoriteTestTrack *resolved;
@end
@implementation FavoriteTestReference
- (BOOL)isKindOfClass:(Class)cls { return cls == SBObject.class || [super isKindOfClass:cls]; }
- (id)get { return self.resolved; }
@end

int main(void) {
    @autoreleasepool {
        MusicBridge *bridge = [MusicBridge new];
        FavoriteTestMusic *music = [FavoriteTestMusic new];
        FavoriteTestTrack *track = [FavoriteTestTrack new];
        track.persistentID = @"song-A"; track.name = @"Song";
        track.artist = @"Artist"; track.album = @"Album";
        music.currentTrack = track; music.isRunning = YES;
        [bridge setValue:music forKey:@"application"];

        // Explicit commands cannot invert playback when Music reports an old state.
        assert([bridge performCommand:@"play" value:0] && music.playerState == 'kPSP');
        assert([bridge performCommand:@"play" value:0] && music.playerState == 'kPSP' && music.playCalls == 2);
        assert([bridge performCommand:@"pause" value:0] && music.playerState == 'kPSp');
        assert([bridge performCommand:@"pause" value:0] && music.playerState == 'kPSp' && music.pauseCalls == 2);
        assert(![bridge performCommand:@"playpause" value:0]);
        music.isRunning = NO;
        assert(![bridge performCommand:@"play" value:0] && music.playCalls == 2);
        music.isRunning = YES;

        assert([bridge performCommand:@"shuffle" value:1] && music.shuffleEnabled);
        assert([bridge performCommand:@"shuffle" value:1] && music.shuffleEnabled);
        assert([bridge performCommand:@"shuffle" value:0] && !music.shuffleEnabled);
        music.shuffleEnabled = YES;
        music.playerState = 'kPSP';
        assert([[bridge snapshot][@"shuffle"] boolValue]);
        assert([[bridge snapshot][@"shuffleAvailable"] boolValue]);
        music.shuffleEnabled = NO;
        assert(![[bridge snapshot][@"shuffle"] boolValue]);
        NSDictionary *result = [bridge setFavorite:YES forTrackID:@"song-A"];
        assert([result[@"success"] boolValue] && track.favorited);
        assert(track.writes == 1);
        result = [bridge setFavorite:YES forTrackID:@"song-A"];
        assert([result[@"success"] boolValue] && track.writes == 1);
        result = [bridge setFavorite:NO forTrackID:@"song-A"];
        assert([result[@"success"] boolValue] && !track.favorited);
        assert(track.writes == 2);
        result = [bridge setFavorite:YES forTrackID:@"previous-song"];
        assert(![result[@"success"] boolValue] && [result[@"reason"] isEqual:@"changed"]);
        assert(track.writes == 2 && !track.favorited);
        track.refuseWrites = YES;
        result = [bridge setFavorite:YES forTrackID:@"song-A"];
        assert([result[@"success"] boolValue] && ![result[@"confirmed"] boolValue] && !track.favorited);
        track.refuseWrites = NO;
        track.persistentID = @"";
        result = [bridge setFavorite:YES forTrackID:@"Song|Artist|Album"];
        assert([result[@"success"] boolValue] && track.favorited);
        track.name = @"";
        result = [bridge setFavorite:NO forTrackID:@"|Artist|Album"];
        assert(![result[@"success"] boolValue] && track.favorited);
        music.isRunning = NO;
        result = [bridge setFavorite:NO forTrackID:@"Song|Artist|Album"];
        assert(![result[@"success"] boolValue] && [result[@"reason"] isEqual:@"closed"]);
        assert(track.favorited);
        music.isRunning = YES; music.playerState = 'kPSP'; track.name = @"Song"; track.duration = 60;
        NSDictionary *withoutArt = [bridge snapshot];
        assert(withoutArt[@"artwork"] == nil);
        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(4, 4)];
        [image lockFocus]; [NSColor.blueColor setFill]; NSRectFill(NSMakeRect(0, 0, 4, 4)); [image unlockFocus];
        FavoriteTestArtwork *art = [FavoriteTestArtwork new]; art.rawData = image.TIFFRepresentation;
        track.artworkItems = @[art];
        [bridge setValue:@0 forKey:@"nextArtworkAttempt"];
        NSDictionary *retried = [bridge snapshot];
        assert([retried[@"artwork"] isKindOfClass:NSImage.class]);
        assert([retried[@"favorited"] boolValue] == track.favorited);
        track.persistentID = @"fresh-reference";
        art.rawData = [NSAppleEventDescriptor descriptorWithDescriptorType:'tdta' data:image.TIFFRepresentation];
        FavoriteTestReference *reference = [FavoriteTestReference new]; reference.resolved = track;
        music.currentTrack = (id)reference;
        NSDictionary *fresh = [bridge snapshot];
        assert([fresh[@"id"] isEqual:@"fresh-reference"] && [fresh[@"favorited"] boolValue]);
        assert([fresh[@"artwork"] isKindOfClass:NSImage.class]);
        result = [bridge setFavorite:NO forTrackID:@"fresh-reference"];
        assert([result[@"success"] boolValue] && !track.favorited);
        puts("30 bridge checks passed: native shuffle state, explicit play/pause, canonical track references, delayed favorites, descriptor artwork, and artwork retries.");
    }
    return 0;
}
