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
@property id tracks;
@end
@implementation FavoriteTestMusic
- (void)playOnce:(BOOL)once { assert(!once); self.playCalls += 1; self.playerState = 'kPSP'; }
- (void)pause { self.pauseCalls += 1; self.playerState = 'kPSp'; }
@end

@interface FavoriteTestArtwork : NSObject
@property id rawData;
@property id data;
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

@interface MusicBridge (ArtworkTesting)
- (id)favoriteTargetForTrack:(id)track;
- (NSImage *)libraryArtworkForTitle:(NSString *)title artist:(NSString *)artist album:(NSString *)album;
@end
@interface ArtworkFallbackTestBridge : MusicBridge
@property id libraryTrack;
@end
@implementation ArtworkFallbackTestBridge
- (id)favoriteTargetForTrack:(id)track { return self.libraryTrack ?: track; }
@end
@interface ThrowingArtwork : NSObject
@property id data;
@end
@implementation ThrowingArtwork
- (id)rawData { [NSException raise:@"Missing raw data" format:@"Simulated unsupported artwork property"]; return nil; }
@end

@interface ArtworkTestCollection : NSObject
@property FavoriteTestTrack *match;
@end
@implementation ArtworkTestCollection
- (id)objectWithName:(NSString *)name { return [self.match.name isEqual:name] ? self.match : nil; }
@end

@interface ReconnectionTestBridge : MusicBridge
@property BOOL connected;
@property BOOL allowReconnect;
@property NSInteger snapshotReads;
@property NSInteger connectionAttempts;
@property NSString *reportedStatus;
@end
@implementation ReconnectionTestBridge
- (BOOL)connectToProcessIdentifier:(pid_t)pid {
    self.connectionAttempts += 1;
    self.connected = self.allowReconnect && pid == 4321;
    return self.connected;
}
- (NSDictionary *)snapshot {
    self.snapshotReads += 1;
    return @{@"status": self.connected ? @"track" : (self.reportedStatus ?: @"closed")};
}
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
        // A library item can supply artwork missing from the queue reference.
        ArtworkFallbackTestBridge *fallbackBridge = [ArtworkFallbackTestBridge new];
        [fallbackBridge setValue:music forKey:@"application"];
        FavoriteTestTrack *library = [FavoriteTestTrack new];
        library.persistentID = @"library-item"; library.name = track.name; library.artist = track.artist;
        library.artworkItems = @[art];
        fallbackBridge.libraryTrack = library;
        music.currentTrack = track; track.artworkItems = @[];
        NSDictionary *librarySnapshot = [fallbackBridge snapshot];
        assert([librarySnapshot[@"status"] isEqual:@"track"]);
        assert([librarySnapshot[@"artwork"] isKindOfClass:NSImage.class]);
        art.rawData = [[NSImage alloc] init]; // Non-nil, invalid image must fall through.
        art.data = image.TIFFRepresentation;
        track.persistentID = @"invalid-raw-image"; track.artworkItems = @[art];
        NSDictionary *validFallback = [fallbackBridge snapshot];
        assert([validFallback[@"artwork"] isValid]);
        ThrowingArtwork *throwing = [ThrowingArtwork new]; throwing.data = image.TIFFRepresentation;
        track.persistentID = @"throwing-raw-data"; track.artworkItems = @[throwing];
        NSDictionary *throwingFallback = [fallbackBridge snapshot];
        assert([throwingFallback[@"status"] isEqual:@"track"] && [throwingFallback[@"artwork"] isValid]);
        art.rawData = [NSData data]; art.data = nil;
        track.persistentID = @"later-artwork-item"; track.artworkItems = @[art, throwing];
        assert([[fallbackBridge snapshot][@"artwork"] isValid]);
        // Switching tracks with no available cover must not retain the previous album.
        track.persistentID = @"no-art-new-track"; track.artworkItems = @[]; library.artworkItems = @[];
        assert([fallbackBridge snapshot][@"artwork"] == nil);
        // Queue database IDs may not address the corresponding library object.
        // Name lookup recovers that artwork, with artist/album identity checks.
        ArtworkTestCollection *collection = [ArtworkTestCollection new];
        music.tracks = collection; collection.match = library;
        library.name = @"Title"; library.artist = @"Artist"; library.album = @"Correct Edition";
        library.artworkItems = @[throwing];
        assert([[fallbackBridge libraryArtworkForTitle:@"Title" artist:@"Artist" album:@"Correct Edition"] isValid]);
        assert([fallbackBridge libraryArtworkForTitle:@"Title" artist:@"Other Artist" album:@"Correct Edition"] == nil);
        assert([fallbackBridge libraryArtworkForTitle:@"Title" artist:@"Artist" album:@"Other Edition"] == nil);
        assert([fallbackBridge libraryArtworkForTitle:@"Missing Title" artist:@"Artist" album:@"Correct Edition"] == nil);
        MusicBridge *unavailablePlayer = [[MusicBridge alloc] initWithBundleIdentifier:@"local.flyn-island.nonexistent-test-player"];
        assert(![unavailablePlayer connectToProcessIdentifier:NSProcessInfo.processInfo.processIdentifier]);
        assert([[unavailablePlayer snapshot][@"status"] isEqual:@"closed"]);
        assert(![unavailablePlayer performCommand:@"play" value:0]);
        assert(![unavailablePlayer connectToProcessIdentifier:0]);
        ReconnectionTestBridge *recovery = [ReconnectionTestBridge new];
        recovery.connectionAttempts = 0; recovery.snapshotReads = 0; recovery.allowReconnect = YES;
        assert([[recovery snapshotForRunningProcessIdentifier:0][@"status"] isEqual:@"closed"]);
        assert(recovery.connectionAttempts == 0 && recovery.snapshotReads == 1);
        assert([[recovery snapshotForRunningProcessIdentifier:123][@"status"] isEqual:@"closed"]);
        assert(recovery.connectionAttempts == 1 && recovery.snapshotReads == 2);
        assert([[recovery snapshotForRunningProcessIdentifier:4321][@"status"] isEqual:@"track"]);
        assert(recovery.connectionAttempts == 2 && recovery.snapshotReads == 4);
        assert([[recovery snapshotForRunningProcessIdentifier:4321][@"status"] isEqual:@"track"]);
        assert(recovery.connectionAttempts == 2 && recovery.snapshotReads == 5);
        recovery.connected = NO; recovery.reportedStatus = @"error";
        assert([[recovery snapshotForRunningProcessIdentifier:4321][@"status"] isEqual:@"error"]);
        assert(recovery.connectionAttempts == 2); // Do not churn a live connection for other failures.
        puts("Bridge checks passed: stale connection recovery, verified PID guards, shuffle/playback/favorites, artwork retries, library artwork fallback with exact artist/album matching, invalid images, throwing properties, alternate artwork, and no stale cover on track change.");
    }
    return 0;
}
