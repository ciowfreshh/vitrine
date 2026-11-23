#import <Foundation/Foundation.h>

@class SGKaraokeLine;

// Converts lyrics into the export schema without copying any source-provided translations.
NSDictionary *SGLibrarySpotifyOriginal(NSDictionary *track, id response);
NSDictionary *SGLibraryOriginalFromLines(NSDictionary *track, NSArray<SGKaraokeLine *> *lines, NSString *source);
NSString *SGLibraryLineText(SGKaraokeLine *line);
