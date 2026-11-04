#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
extern NSString *const SGTranslationStoreErrorDomain;
// Foundation-only, serialized SQLite store. Its URL must be in Application Support, never Caches.
@interface SGTranslationStore : NSObject
- (instancetype)initWithURL:(NSURL *)url legacyDirectory:(nullable NSURL *)legacy;
- (nullable NSDictionary *)recordForTrack:(NSString *)track language:(NSString *)language error:(NSError **)error;
- (BOOL)putRecord:(NSDictionary *)record replace:(BOOL)replace didWrite:(nullable BOOL *)didWrite error:(NSError **)error;
- (NSArray<NSDictionary *> *)summaries:(NSError **)error;
- (BOOL)removeTrack:(nullable NSString *)track language:(nullable NSString *)language error:(NSError **)error;
// Rejects malformed data and returns only the documented, non-secret export fields.
+ (nullable NSDictionary *)validatedRecord:(id)value error:(NSError **)error;
+ (NSString *)identityForRecord:(NSDictionary *)record;
@end
NS_ASSUME_NONNULL_END
