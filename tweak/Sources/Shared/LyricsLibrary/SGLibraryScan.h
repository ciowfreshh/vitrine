#import <Foundation/Foundation.h>

extern NSNotificationName const SGLibraryScanDidChange;

@interface SGLibraryScanner : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly, getter=isRunning) BOOL running;
@property (nonatomic, readonly) NSString *progress;
- (void)startWithSource:(NSURL *)source;
- (void)pause;
@end

// Only the URI forms used by Spotify's own context pager are accepted.
NSURL *SGLibrarySpotifyPageURL(NSString *address);
NSArray *SGLibraryCollectionPage(id json, NSString **next, NSError **error);
