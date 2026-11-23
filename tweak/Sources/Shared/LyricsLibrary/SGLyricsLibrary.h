#import <Foundation/Foundation.h>

@class UIViewController, SGKaraokeLine;
UIViewController *SGLyricsLibraryPage(void);
UIViewController *SGLibraryPlayingLyricsPage(void);
NSArray<SGKaraokeLine *> *SGLibraryKaraokeLines(NSDictionary *record);
BOOL SGLibraryShowsTranslation(void);
extern NSString *const SGLibraryShowTranslationKey;
