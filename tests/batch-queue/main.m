#import <Foundation/Foundation.h>
#import "Core/BatchQueue/SGTranslationQueue.h"
#import "Core/BatchQueue/SGTranslationPage.h"
#import "Core/BatchQueue/SGTranslationJSON.h"
static NSUInteger checks;
static void check(BOOL ok, NSString *name) { if (!ok) { NSLog(@"FAIL: %@", name); exit(1); } ++checks; NSLog(@"PASS: %@", name); }
static void spin(BOOL (^until)(void), double seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!until() && end.timeIntervalSinceNow > 0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    check(until(), @"asynchronous queue completed before deadline");
}
static NSArray *tracks(NSUInteger count) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSUInteger i = 0; i < count; ++i) [result addObject:@{@"id":[NSString stringWithFormat:@"%022lu", (unsigned long)i], @"title":@(i).stringValue}];
    return result;
}
static SGTranslationQueue *job(NSURL *root, NSString *name, NSUInteger count) {
    SGTranslationQueue *q = [[SGTranslationQueue alloc] initWithURL:[root URLByAppendingPathComponent:name]];
    check(q.paused && [q prepareLanguage:@"vi"] && [q appendTracks:tracks(count)], @"create durable paused queue"); return q;
}
int main(void) { @autoreleasepool {
    NSURL *root = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    check(SGTranslationHTTPFailure(429, nil, nil) == SGTranslationRateLimit, @"HTTP 429 classification");
    check(SGTranslationHTTPFailure(500, nil, nil) == SGTranslationServer && SGTranslationHTTPFailure(503, nil, nil) == SGTranslationServer, @"HTTP 500/503 classification");
    check(SGTranslationHTTPFailure(401, nil, nil) == SGTranslationAuthentication && SGTranslationHTTPFailure(403, nil, nil) == SGTranslationAuthentication, @"authentication classification");
    check(SGTranslationHTTPFailure(404, nil, @"model_not_found") == SGTranslationModel, @"unsupported model classification");
    check(SGTranslationHTTPFailure(400, nil, @"context_length_exceeded") == SGTranslationContextLimit, @"context limit classification");
    check(SGTranslationHTTPFailure(0, [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil], nil) == SGTranslationTimeout, @"timeout classification");
    NSDate *now = [NSDate dateWithTimeIntervalSince1970:0];
    check(SGTranslationRetryAfter(@"17", now) == 17 && SGTranslationRetryAfter(@"Thu, 01 Jan 1970 00:00:20 GMT", now) == 20, @"Retry-After delta and HTTP date");
    SGTranslationFailure invalid = 0;
    check(SGTranslationValidateLines(@"{\"lines\":[\"Xin chào\",\"\"]}", 2, &invalid).count == 2, @"real JSON parser accepts one translation per input line");
    check(!SGTranslationValidateLines(@"not json", 2, &invalid) && invalid == SGTranslationJSON, @"real parser rejects invalid JSON");
    check(!SGTranslationValidateLines(@"[\"one\"]", 2, &invalid) && invalid == SGTranslationLineCount, @"real parser rejects missing lines");
    check(!SGTranslationValidateLines(@"[null,42]", 2, &invalid) && invalid == SGTranslationJSON, @"real parser rejects non-string entries");
    check(SGTranslationValidateLines(@"```json\n[\"a\",\"b\"]\n```", 2, &invalid).count == 2, @"compatible server fenced JSON support");
    NSMutableArray *collected = [NSMutableArray array]; NSUInteger scanned = 0;
    NSURL *base = [NSURL URLWithString:@"https://api.spotify.com/v1/me/tracks?limit=50"];
    for (NSUInteger offset = 0; offset < 1867; offset += 50) {
        NSMutableArray *items = [NSMutableArray array];
        for (NSUInteger i = offset; i < MIN(offset + 50, 1867); ++i) [items addObject:@{@"track":@{@"id":[NSString stringWithFormat:@"%022lu", (unsigned long)i], @"name":@(i).stringValue}}];
        NSString *next = nil; NSUInteger n;
        id after = offset + 50 < 1867 ? [NSString stringWithFormat:@"https://api.spotify.com/v1/me/tracks?offset=%lu", (unsigned long)(offset + 50)] : NSNull.null;
        NSArray *page = SGTranslationTracksPage(@{@"items":items, @"next":after}, base, &next, &n);
        check(page != nil, @"saved-track page parses"); [collected addObjectsFromArray:page]; scanned += n;
        check((next != nil) == (offset + 50 < 1867), @"pagination continues until final page");
    }
    check(scanned == 1867 && collected.count == 1867, @"all 1,867 Liked Songs across 38 pages");
    check(!SGTranslationPageURL(@"https://example.com/steal", base) && !SGTranslationPageURL(@"https://api.spotify.com@evil.test/", base), @"pagination never sends credentials to external hosts");
    NSString *next; NSUInteger count;
    check(SGTranslationTracksPage(@{@"pages":@[@{@"tracks":@[@{@"uri":@"spotify:track:0000000000000000000001"}], @"next_page_url":@"/context-resolve/v1/page2"}]}, [NSURL URLWithString:@"https://spclient.wg.spotify.com/context-resolve/v1/test"], &next, &count).count == 1 && next.length, @"album/playlist context pagination and relative URL");
    check([SGTranslationTracksPage(@{@"pages":@[@{@"tracks":@[@{@"gid":@"AAAAAAAAAAAAAAAAAAAAAQ=="}]}]}, [NSURL URLWithString:@"https://spclient.wg.spotify.com/"], &next, &count).firstObject[@"id"] isEqual:@"0000000000000000000001"], @"context GID-only tracks convert to Spotify base62 IDs");
    SGTranslationQueue *single = job(root, @"single.json", 1);
    single.execute = ^(NSDictionary *item, NSString *language, void (^done)(NSString *, NSError *)) { done(@"succeeded", nil); };
    [single resume]; check([single.statistics[@"succeeded"] integerValue] == 1, @"one song succeeds and commits");
    check([single prepareLanguage:@"vi"] && single.items.count == 0, @"new source scan archives the completed report without carrying terminal IDs forward");
    SGTranslationQueue *bulk = job(root, @"bulk.json", 1000); bulk.concurrency = 3;
    __block NSUInteger active = 0, peak = 0, calls = 0;
    NSMutableSet *seen = [NSMutableSet set];
    bulk.execute = ^(NSDictionary *item, NSString *language, void (^done)(NSString *, NSError *)) {
        ++active; ++calls; peak = MAX(peak, active); check(![seen containsObject:item[@"id"]], @"successful song is not resent"); [seen addObject:item[@"id"]];
        dispatch_async(dispatch_get_main_queue(), ^{ --active; done(@"succeeded", nil); });
    };
    [bulk resume]; spin(^BOOL { return [bulk.statistics[@"succeeded"] integerValue] == 1000; }, 60);
    check(peak == 3 && calls == 1000, @"1,000-song queue honors configured concurrency 3");
    [bulk pause]; check([bulk appendTracks:tracks(1000)] && bulk.items.count == 1000, @"deduplicate queued track IDs");
    SGTranslationQueue *paused = job(root, @"pause.json", 100);
    NSMutableArray *callbacks = [NSMutableArray array];
    paused.execute = ^(NSDictionary *item, NSString *language, void (^done)(NSString *, NSError *)) { [callbacks addObject:[done copy]]; };
    [paused resume]; [paused pause];
    check(callbacks.count == 2, @"default concurrency 2 and pause prevents new starts");
    for (void (^done)(NSString *, NSError *) in callbacks) done(@"succeeded", nil);
    check([paused.statistics[@"pending"] integerValue] == 98, @"in-flight songs finish while paused; remaining songs stay queued");
    SGTranslationQueue *recovered = [[SGTranslationQueue alloc] initWithURL:[root URLByAppendingPathComponent:@"pause.json"]];
    check(recovered.paused && [recovered.statistics[@"succeeded"] integerValue] == 2, @"restart preserves success and requires explicit resume");
    recovered.execute = ^(NSDictionary *item, NSString *language, void (^done)(NSString *, NSError *)) { done(@"skipped:same_language", nil); };
    [recovered resume]; spin(^BOOL { return [recovered.statistics[@"skipped"] integerValue] == 98; }, 15);
    check([recovered.statistics[@"succeeded"] integerValue] == 2, @"resume skips completed songs");
    SGTranslationQueue *retry = job(root, @"retry.json", 1); __block NSUInteger attempts = 0;
    retry.execute = ^(NSDictionary *item, NSString *language, void (^done)(NSString *, NSError *)) { ++attempts; done(attempts == 1 ? nil : @"succeeded", attempts == 1 ? SGTranslationQueueError(SGTranslationTimeout, @"fixture timeout", 0) : nil); };
    [retry resume]; spin(^BOOL { return [retry.statistics[@"succeeded"] integerValue] == 1; }, 8);
    check(attempts == 2, @"transient failure then successful single-song retry");
    SGTranslationQueue *limited = job(root, @"limit.json", 4); __block NSUInteger limitedCalls = 0; __block NSTimeInterval failedAt;
    limited.execute = ^(NSDictionary *item, NSString *language, void (^done)(NSString *, NSError *)) {
        ++limitedCalls;
        if (limitedCalls <= 2) { failedAt = NSDate.date.timeIntervalSince1970; done(nil, SGTranslationQueueError(SGTranslationRateLimit, @"fixture 429", 3)); }
        else { check(NSDate.date.timeIntervalSince1970 - failedAt >= 2.9, @"no AI starts before Retry-After cooldown"); done(@"succeeded", nil); }
    };
    [limited resume]; spin(^BOOL { return [limited.statistics[@"succeeded"] integerValue] == 4; }, 15);
    check(limited.effectiveConcurrency == 1, @"repeated 429 reduces concurrency");
    for (NSNumber *code in @[@(SGTranslationServer), @(SGTranslationJSON), @(SGTranslationLineCount), @(SGTranslationTimeout)]) {
        NSString *name = [NSString stringWithFormat:@"bounded-%@.json", code];
        SGTranslationQueue *q = job(root, name, 1); [q pause];
        NSMutableDictionary *fixture = [[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:[root URLByAppendingPathComponent:name]] options:NSJSONReadingMutableContainers error:nil] mutableCopy];
        fixture[@"items"][0][@"attempts"] = @3;
        [[NSJSONSerialization dataWithJSONObject:fixture options:0 error:nil] writeToURL:[root URLByAppendingPathComponent:name] atomically:YES];
        q = [[SGTranslationQueue alloc] initWithURL:[root URLByAppendingPathComponent:name]];
        q.execute = ^(NSDictionary *item, NSString *language, void (^done)(NSString *, NSError *)) { done(nil, SGTranslationQueueError(code.integerValue, @"fixture invalid response", 0)); };
        [q resume]; check([q.statistics[@"failed"] integerValue] == 1, @"500/invalid JSON/line mismatch/timeout stop after attempt four");
        [q pause]; [q retryFailures]; check([q.statistics[@"pending"] integerValue] == 1, @"manual retry resets only failed songs");
    }
    SGTranslationQueue *skips = job(root, @"skips.json", 3); __block NSUInteger skipped = 0;
    skips.execute = ^(NSDictionary *item, NSString *language, void (^done)(NSString *, NSError *)) { done(@[@"skipped:saved", @"skipped:no_lyrics", @"skipped:same_language"][skipped++], nil); };
    [skips resume]; check([skips.statistics[@"skipped"] integerValue] == 3 && [skips.statistics[@"failed"] integerValue] == 0, @"saved, unavailable lyrics and same-language outcomes are skips, not network failures");
    SGTranslationQueue *auth = job(root, @"auth.json", 5);
    auth.execute = ^(NSDictionary *item, NSString *language, void (^done)(NSString *, NSError *)) { done(nil, SGTranslationQueueError(SGTranslationAuthentication, @"fixture auth rejected", 0)); };
    [auth resume]; check(auth.paused && auth.notice.length && [auth.statistics[@"pending"] integerValue] >= 3, @"authentication failure pauses with an actionable error");
    NSURL *corruptURL = [root URLByAppendingPathComponent:@"corrupt.json"];
    NSData *corrupt = [@"{\"schema\":null}" dataUsingEncoding:NSUTF8StringEncoding]; [corrupt writeToURL:corruptURL atomically:YES];
    SGTranslationQueue *broken = [[SGTranslationQueue alloc] initWithURL:corruptURL];
    check(broken.paused && broken.notice.length && ![broken prepareLanguage:@"vi"] && [[NSData dataWithContentsOfURL:corruptURL] isEqual:corrupt], @"corrupt progress never crashes or overwrites the recovery file");
    NSLog(@"PASS: %lu native queue assertions; network and player are mocks, no API keys used", (unsigned long)checks);
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];
} return 0; }
