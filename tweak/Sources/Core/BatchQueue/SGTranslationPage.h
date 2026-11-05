#import <Foundation/Foundation.h>
// Strict parsing shared by the production adapter and native pagination tests.
NSURL *SGTranslationPageURL(NSString *address, NSURL *base);
NSArray<NSDictionary *> *SGTranslationTracksPage(id root, NSURL *base, NSString **next, NSUInteger *scanned);
