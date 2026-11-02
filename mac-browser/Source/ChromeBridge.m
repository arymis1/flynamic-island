#import "ChromeBridge.h"
#import <ScriptingBridge/ScriptingBridge.h>
#import <Carbon/Carbon.h>
@protocol YTChromeApplication
- (SBElementArray *)windows;
@end
@protocol YTChromeWindow
@property(readonly) NSString *mode;
- (SBElementArray *)tabs;
@end
@protocol YTChromeTab
@property(readonly) NSString *URL;
- (id)executeJavascript:(NSString *)javascript;
- (NSString *)id;
@end
@interface ChromeBridge () <SBApplicationDelegate>
@property SBApplication *application;
@property pid_t pid;
@property NSError *lastError;
@property NSString *script;
@property NSString *selectedTabID;
@end
@implementation ChromeBridge
- (instancetype)init {
    if ((self = [super init])) {
        NSString *path = [[NSBundle mainBundle] pathForResource:@"YouTubeMusic" ofType:@"js"];
        _script = path ? [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil] : nil;
    }
    return self;
}
+ (BOOL)isYouTubeMusicURL:(NSString *)value {
    NSURLComponents *url = [NSURLComponents componentsWithString:value];
    return [url.scheme.lowercaseString isEqual:@"https"] && [url.host.lowercaseString isEqual:@"music.youtube.com"] &&
        !url.user && !url.password && (!url.port || url.port.integerValue == 443);
}
- (BOOL)connect {
    NSRunningApplication *running = [[NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.google.Chrome"] firstObject];
    if (!running || running.isTerminated) { self.application = nil; self.pid = 0; return NO; }
    if (!self.application || self.pid != running.processIdentifier) {
        self.pid = running.processIdentifier;
        self.application = [[SBApplication alloc] initWithProcessIdentifier:self.pid];
        self.application.delegate = self;
        self.application.timeout = 120;
    }
    return self.application != nil;
}
- (id)eventDidFail:(const AppleEvent *)event withError:(NSError *)error { self.lastError = error; return nil; }
- (NSInteger)permissionRequestingConsent:(BOOL)request {
    const char *bundle = "com.google.Chrome";
    AEAddressDesc target = {typeNull, NULL};
    OSStatus status = AECreateDesc(typeApplicationBundleID, bundle, strlen(bundle), &target);
    if (!status) { status = AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, request); AEDisposeDesc(&target); }
    return status;
}
- (NSDictionary *)run:(id<YTChromeTab>)tab request:(NSDictionary *)request {
    self.lastError = nil;
    if (!self.script || ![ChromeBridge isYouTubeMusicURL:tab.URL]) return @{@"status": @"wrong-origin"};
    NSData *json = [NSJSONSerialization dataWithJSONObject:request options:NSJSONWritingFragmentsAllowed error:nil];
    NSString *code = [NSString stringWithFormat:@"(%@)(%@)", self.script, [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]];
    id result = [tab executeJavascript:code];
    if ([result respondsToSelector:@selector(get)]) result = [result get];
    if (![result isKindOfClass:NSString.class]) {
        if (self.lastError.code == -1743) return @{@"status": @"denied"};
        // Chrome reports disabled JavaScript through error text; avoid treating a
        // navigated/closed tab as a new permission problem.
        NSString *description = self.lastError.localizedDescription.lowercaseString ?: @"";
        BOOL disabled = self.lastError.code == 12 || [description containsString:@"javascript"] || [description containsString:@"java script"];
        return @{@"status": disabled ? @"chrome-setting" : @"error"};
    }
    NSData *data = [result dataUsingEncoding:NSUTF8StringEncoding];
    id decoded = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [decoded isKindOfClass:NSDictionary.class] ? decoded : @{@"status": @"error"};
}
- (NSArray *)musicTabs {
    NSMutableArray *tabs = [NSMutableArray array];
    for (id<YTChromeWindow> window in [(id<YTChromeApplication>)self.application windows]) {
        if ([window.mode isEqual:@"incognito"]) continue;
        for (id<YTChromeTab> tab in window.tabs) {
            if ([ChromeBridge isYouTubeMusicURL:tab.URL]) [tabs addObject:tab];
            if (tabs.count == 8) return tabs;
        }
    }
    return tabs;
}
- (NSDictionary *)snapshot {
    if (![self connect]) return @{@"status": @"closed"};
    NSInteger permission = [self permissionRequestingConsent:NO];
    if (permission) return @{@"status": permission == -1743 ? @"denied" : @"permission"};
    @try {
        NSDictionary *paused = nil;
        NSDictionary *failure = nil;
        NSArray *tabs = [self musicTabs];
        for (id<YTChromeTab> tab in tabs) {
            NSDictionary *snapshot = [self run:tab request:@{}];
            if ([snapshot[@"status"] isEqual:@"track"]) {
                NSMutableDictionary *bound = snapshot.mutableCopy;
                bound[@"id"] = [NSString stringWithFormat:@"%@:%@", [tab id], snapshot[@"id"]];
                if ([bound[@"playing"] boolValue]) { self.selectedTabID = [tab id]; return bound; }
                if (!paused || [[tab id] isEqual:self.selectedTabID]) paused = bound;
            } else if (![@[@"idle", @"wrong-origin"] containsObject:snapshot[@"status"]]) failure = snapshot;
        }
        if (paused) return paused;
        return failure ?: @{@"status": @"idle"};
    } @catch (NSException *exception) { return @{@"status": @"error"}; }
}
- (BOOL)performCommand:(NSString *)command value:(double)value trackID:(NSString *)trackID {
    if (![self connect] || [self permissionRequestingConsent:NO]) return NO;
    NSRange colon = [trackID rangeOfString:@":"];
    if (colon.location == NSNotFound) return NO;
    NSString *tabID = [trackID substringToIndex:colon.location];
    NSString *songID = [trackID substringFromIndex:colon.location + 1];
    @try {
        for (id<YTChromeTab> tab in [self musicTabs]) {
            if ([[NSString stringWithFormat:@"%@", [tab id]] isEqualToString:tabID]) {
                NSDictionary *reply = [self run:tab request:@{@"command": command, @"value": @(value), @"track": songID}];
                return [reply[@"success"] boolValue];
            }
        }
    } @catch (NSException *exception) {}
    return NO;
}
@end
