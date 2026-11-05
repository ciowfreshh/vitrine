#import <Foundation/Foundation.h>

// All entry points and completions run on the main thread. No player state lives here.
typedef NS_ENUM(NSInteger, SGTranslationFailure) {
    SGTranslationNetwork = 1, SGTranslationTimeout, SGTranslationRateLimit,
    SGTranslationServer, SGTranslationAuthentication, SGTranslationModel,
    SGTranslationJSON, SGTranslationLineCount, SGTranslationNoLyrics,
    SGTranslationContextLimit, SGTranslationConfiguration, SGTranslationStorage
};
extern NSString *const SGTranslationQueueErrorDomain;
NSError *SGTranslationQueueError(SGTranslationFailure code, NSString *message, NSTimeInterval retryAfter);
NSTimeInterval SGTranslationRetryAfter(NSString *value, NSDate *now);
SGTranslationFailure SGTranslationHTTPFailure(NSInteger status, NSError *network, NSString *serverCode);

@interface SGTranslationQueue : NSObject
@property (nonatomic) NSUInteger concurrency; // 1–3; default 2
@property (nonatomic, readonly) NSUInteger effectiveConcurrency;
@property (nonatomic, readonly) BOOL paused;
@property (nonatomic, readonly) NSArray<NSDictionary *> *items;
@property (nonatomic, readonly) NSString *language;
@property (nonatomic, readonly) NSString *notice;
@property (nonatomic, readonly) NSMutableDictionary *context;
@property (nonatomic, copy) void (^changed)(void);
// Result is succeeded or skipped. Success means the adapter already committed the translation.
@property (nonatomic, copy) void (^execute)(NSDictionary *item, NSString *language,
                                         void (^done)(NSString *result, NSError *error));
- (instancetype)initWithURL:(NSURL *)url;
- (BOOL)prepareLanguage:(NSString *)language;
- (BOOL)appendTracks:(NSArray<NSDictionary *> *)tracks;
- (BOOL)checkpoint;
- (void)resume;
- (void)pause;
- (void)retryFailures;
- (NSDictionary<NSString *, NSNumber *> *)statistics;
@end
