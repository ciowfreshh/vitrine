#import <Foundation/Foundation.h>

extern NSString *const SGLibraryFormat;
extern NSString *const SGLibraryErrorDomain;

BOOL SGLibraryTrackID(id value);
NSDictionary *SGLibraryTrack(id value, NSError **error);
NSDictionary *SGLibraryMerge(NSDictionary *original, NSDictionary *incoming, NSError **error);
NSDictionary *SGLibraryTrackSummary(NSDictionary *track);
NSData *SGLibraryJSON(id object, NSError **error);
id SGLibraryReadJSON(NSData *data, NSError **error);
void SGLibraryError(NSError **error, NSString *message);

// A document can contain one track, or a tracks array with the same schema and version as a ZIP.
NSArray *SGLibraryDocument(id object, NSError **error);
