#import <Foundation/Foundation.h>

// Ignore typography and spacing, never accents or different words. Used for both playback and
// queue completeness, so a file's existence can never stand in for usable translated lyrics.
NSString *SGTranslationLineKey(NSString *text);
BOOL SGTranslationLineNeedsText(NSString *text);
NSArray<NSString *> *SGTranslationResolveLines(NSDictionary<NSString *, NSString *> *saved, NSArray<NSString *> *originals);
NSIndexSet *SGTranslationMissingLines(NSArray<NSString *> *originals, NSArray *translations);
// Conservative completeness guard: long, confidently foreign lines returned verbatim are not done.
// Short names/ad-libs and original lines already in the target language remain valid.
NSIndexSet *SGTranslationUnchangedForeignLines(NSArray<NSString *> *originals, NSArray *translations, NSString *target);
NSDictionary *SGTranslationMergeLines(NSDictionary *existing, NSDictionary *incoming);
