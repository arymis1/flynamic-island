#import "ChromeBridge.h"
int main(void) {
    @autoreleasepool {
        NSCAssert([ChromeBridge isYouTubeMusicURL:@"https://music.youtube.com/watch?v=abc"], @"YT origin allowed");
        NSCAssert([ChromeBridge isYouTubeMusicURL:@"https://music.youtube.com:443/"], @"Default HTTPS port allowed");
        for (NSString *url in @[@"http://music.youtube.com/", @"https://music.youtube.com.evil.test/", @"https://youtube.com/", @"https://evil.test/?next=https://music.youtube.com", @"https://user@music.youtube.com/", @"https://music.youtube.com:8443/"]) {
            NSCAssert(![ChromeBridge isYouTubeMusicURL:url], @"Reject other origin");
        }
        puts("Chrome origin checks passed: exact HTTPS host, no embedded credentials or alternate ports.");
    }
}
