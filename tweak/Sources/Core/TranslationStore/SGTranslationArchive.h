#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
// ZIP32, stored or raw-deflate JSON entries. No paths from an archive are ever written to disk.
@interface SGTranslationArchive : NSObject
+ (BOOL)writeRecords:(NSArray<NSDictionary *> *)summaries toURL:(NSURL *)url
             record:(nullable NSDictionary *(^)(NSDictionary *summary, NSError **error))record
           progress:(void (^)(NSUInteger done, NSUInteger total))progress error:(NSError **)error;
+ (BOOL)readURL:(NSURL *)url consume:(BOOL (^)(id record, NSError **error))consume
      progress:(void (^)(NSUInteger done, NSUInteger total))progress error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
