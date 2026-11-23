#import <Foundation/Foundation.h>

@class UIViewController, SGKaraokeLine;
UIViewController *SGLyricsLibraryPage(void);
UIViewController *SGLibraryPlayingLyricsPage(void);
NSArray<SGKaraokeLine *> *SGLibraryKaraokeLines(NSDictionary *record);
NSArray<SGKaraokeLine *> *SGLibraryOverlayTranslations(NSArray<SGKaraokeLine *> *original, NSArray<SGKaraokeLine *> *imported);
BOOL SGLibraryShowsTranslation(void);
extern NSString *const SGLibraryShowTranslationKey;
