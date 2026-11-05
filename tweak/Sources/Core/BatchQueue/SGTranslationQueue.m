#import "SGTranslationQueue.h"
#import <fcntl.h>
#import <float.h>
#import <math.h>
#import <unistd.h>

NSString *const SGTranslationQueueErrorDomain = @"Vitrine.TranslationQueue";
NSError *SGTranslationQueueError(SGTranslationFailure code, NSString *message, NSTimeInterval retryAfter) {
    return [NSError errorWithDomain:SGTranslationQueueErrorDomain code:code userInfo:@{
        NSLocalizedDescriptionKey:message ?: @"", @"retryAfter":@(MAX(0, retryAfter))}];
}
NSTimeInterval SGTranslationRetryAfter(NSString *value, NSDate *now) {
    if (!value.length) return 0;
    NSScanner *scanner = [NSScanner scannerWithString:value];
    double seconds;
    if ([scanner scanDouble:&seconds] && scanner.isAtEnd) return MAX(0, seconds);
    NSDateFormatter *format = [NSDateFormatter new];
    format.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    format.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    format.dateFormat = @"EEE',' dd MMM yyyy HH':'mm':'ss z";
    return MAX(0, [[format dateFromString:value] timeIntervalSinceDate:now]);
}
SGTranslationFailure SGTranslationHTTPFailure(NSInteger status, NSError *network, NSString *serverCode) {
    if (network) return network.code == NSURLErrorTimedOut ? SGTranslationTimeout : SGTranslationNetwork;
    NSString *code = serverCode.lowercaseString ?: @"";
    if (status == 401 || status == 403 || [code containsString:@"invalid_api_key"]) return SGTranslationAuthentication;
    if ([code containsString:@"context"] || [code containsString:@"token"] || status == 413) return SGTranslationContextLimit;
    if (status == 429) return SGTranslationRateLimit;
    if (status == 408 || status == 504) return SGTranslationTimeout;
    if (status >= 500) return SGTranslationServer;
    if (status == 404 || [code containsString:@"model"]) return SGTranslationModel;
    return SGTranslationConfiguration;
}

@implementation SGTranslationQueue {
    NSURL *_url;
    NSMutableArray<NSMutableDictionary *> *_work;
    BOOL _paused, _saving, _unreadable;
    NSString *_language, *_notice;
    NSMutableDictionary *_context;
    NSUInteger _active, _effectiveConcurrency, _limited, _wakeGeneration;
    NSTimeInterval _cooldown;
}
- (instancetype)initWithURL:(NSURL *)url {
    if (!(self = [super init])) return nil;
    _url = url; _concurrency = _effectiveConcurrency = 2; _paused = YES;
    _work = [NSMutableArray array]; _context = [NSMutableDictionary dictionary];
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (data) {
        id root = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
        BOOL valid = [root isKindOfClass:NSDictionary.class] && [root[@"schema"] integerValue] == 1 &&
            [root[@"items"] isKindOfClass:NSArray.class] && [root[@"language"] isKindOfClass:NSString.class] &&
            [root[@"context"] isKindOfClass:NSDictionary.class];
        NSMutableSet *seen = [NSMutableSet set];
        for (id item in valid ? root[@"items"] : @[]) {
            if (![item isKindOfClass:NSMutableDictionary.class] || ![item[@"id"] isKindOfClass:NSString.class] ||
                ![item[@"id"] length] || [seen containsObject:item[@"id"]] ||
                ![@[@"pending", @"running", @"retry", @"succeeded", @"skipped", @"failed"] containsObject:item[@"state"]]) { valid = NO; break; }
            [seen addObject:item[@"id"]];
        }
        if (valid) {
            _work = root[@"items"]; _language = root[@"language"]; _context = root[@"context"];
            _cooldown = [root[@"cooldown"] doubleValue];
            for (NSMutableDictionary *item in _work) if ([item[@"state"] isEqual:@"running"]) item[@"state"] = @"pending";
        } else { _unreadable = YES; _notice = @"Queue recovery failed. The saved file was preserved."; }
    }
    return self;
}
@synthesize concurrency = _concurrency;
- (NSArray *)items { return [_work copy]; }
- (NSString *)language { return _language; }
- (NSString *)notice { return _notice; }
- (NSMutableDictionary *)context { return _context; }
- (BOOL)paused { return _paused; }
- (NSUInteger)effectiveConcurrency { return _effectiveConcurrency; }
- (void)setConcurrency:(NSUInteger)value { _concurrency = MIN(3, MAX(1, value)); _effectiveConcurrency = MIN(_effectiveConcurrency, _concurrency); }
- (BOOL)prepareLanguage:(NSString *)language {
    if (_active || !_paused || _unreadable) return NO;
    if (_language && ![_language isEqual:language]) {
        // A language change starts a new job only after every previous item is terminal.
        for (NSDictionary *item in _work) if ([@[@"pending", @"retry"] containsObject:item[@"state"]]) return NO;
        [_work removeAllObjects]; [_context removeAllObjects];
    }
    _language = [language copy];
    return [self checkpoint];
}
- (BOOL)appendTracks:(NSArray<NSDictionary *> *)tracks {
    NSMutableSet *seen = [NSMutableSet set];
    for (NSDictionary *item in _work) [seen addObject:item[@"id"]];
    for (NSDictionary *track in tracks) {
        NSString *identifier = track[@"id"];
        if (![identifier isKindOfClass:NSString.class] || !identifier.length || [seen containsObject:identifier]) continue;
        [seen addObject:identifier];
        [_work addObject:[@{@"id":identifier, @"title":track[@"title"] ?: identifier, @"state":@"pending", @"attempts":@0} mutableCopy]];
    }
    return [self checkpoint];
}
- (BOOL)checkpoint {
    if (_unreadable || !_language) return NO;
    NSError *error;
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *directory = [_url URLByDeletingLastPathComponent];
    BOOL ok = [fm createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error];
    NSData *data = ok ? [NSJSONSerialization dataWithJSONObject:@{@"schema":@1, @"language":_language, @"context":_context,
        @"items":_work, @"cooldown":@(_cooldown)} options:0 error:&error] : nil;
    ok = data && [data writeToURL:_url options:NSDataWritingAtomic error:&error];
    if (ok) {
        int fd = open(_url.fileSystemRepresentation, O_RDONLY);
        ok = fd >= 0 && fsync(fd) == 0; if (fd >= 0) close(fd);
        int dir = open(directory.fileSystemRepresentation, O_RDONLY); if (dir >= 0) { fsync(dir); close(dir); }
    }
    if (!ok) { _paused = YES; _notice = @"Could not save queue progress. Check available storage."; }
    if (!_saving && self.changed) { _saving = YES; self.changed(); _saving = NO; }
    return ok;
}
- (void)pause { _paused = YES; ++_wakeGeneration; [self checkpoint]; }
- (void)resume {
    if (_unreadable || !_language || !self.execute) return;
    _paused = NO; _notice = nil; _effectiveConcurrency = _concurrency; _limited = 0;
    if ([self checkpoint]) [self pump];
}
- (void)retryFailures {
    if (_active) return;
    for (NSMutableDictionary *item in _work) if ([item[@"state"] isEqual:@"failed"]) {
        item[@"state"] = @"pending"; item[@"attempts"] = @0;
        [item removeObjectForKey:@"next"]; [item removeObjectForKey:@"error"];
    }
    [self checkpoint];
}
- (NSDictionary *)statistics {
    NSMutableDictionary *stats = [@{@"total":@(_work.count), @"succeeded":@0, @"failed":@0, @"skipped":@0, @"running":@0, @"pending":@0} mutableCopy];
    for (NSDictionary *item in _work) {
        NSString *state = [item[@"state"] isEqual:@"retry"] ? @"pending" : item[@"state"];
        stats[state] = @([stats[state] unsignedIntegerValue] + 1);
    }
    return stats;
}
- (void)pump {
    if (_paused || !self.execute) return;
    NSTimeInterval now = NSDate.date.timeIntervalSince1970, soonest = DBL_MAX;
    if (_cooldown > now) soonest = _cooldown;
    for (NSMutableDictionary *item in _work) {
        if (_paused || _active >= _effectiveConcurrency || _cooldown > now) break;
        if (![@[@"pending", @"retry"] containsObject:item[@"state"]]) continue;
        NSTimeInterval due = [item[@"next"] doubleValue];
        if (due > now) { soonest = MIN(soonest, due); continue; }
        item[@"state"] = @"running";
        item[@"attempts"] = @([item[@"attempts"] unsignedIntegerValue] + 1);
        ++_active;
        if (![self checkpoint]) { --_active; item[@"state"] = @"pending"; return; }
        __block BOOL completed = NO;
        __weak SGTranslationQueue *weak = self;
        self.execute([item copy], _language, ^(NSString *result, NSError *error) {
            NSAssert(NSThread.isMainThread, @"Queue callback must be on main");
            SGTranslationQueue *q = weak;
            if (!q || completed) return;
            completed = YES; --q->_active;
            if (!error && ([result isEqual:@"succeeded"] || [result hasPrefix:@"skipped"])) {
                item[@"state"] = [result hasPrefix:@"skipped"] ? @"skipped" : result;
                if ([result hasPrefix:@"skipped:"]) item[@"reason"] = [result substringFromIndex:8]; [item removeObjectForKey:@"error"]; [item removeObjectForKey:@"next"];
            } else {
                NSInteger code = [error.domain isEqual:SGTranslationQueueErrorDomain] ? error.code : SGTranslationNetwork;
                item[@"error"] = error.localizedDescription ?: @"Translation failed"; item[@"code"] = @(code);
                BOOL configuration = code == SGTranslationAuthentication || code == SGTranslationModel || code == SGTranslationConfiguration || code == SGTranslationStorage;
                BOOL transient = code == SGTranslationNetwork || code == SGTranslationTimeout || code == SGTranslationRateLimit || code == SGTranslationServer || code == SGTranslationJSON || code == SGTranslationLineCount;
                NSUInteger attempts = [item[@"attempts"] unsignedIntegerValue];
                NSTimeInterval delay = MAX([error.userInfo[@"retryAfter"] doubleValue], MIN(60, pow(2, attempts) + arc4random_uniform(1000) / 1000.0));
                if (code == SGTranslationRateLimit) {
                    if (++q->_limited >= 2) q->_effectiveConcurrency = MAX(1, q->_effectiveConcurrency - 1);
                    q->_cooldown = MAX(q->_cooldown, NSDate.date.timeIntervalSince1970 + delay);
                }
                item[@"state"] = transient && attempts < 4 ? @"retry" : @"failed";
                item[@"next"] = @(NSDate.date.timeIntervalSince1970 + delay);
                if (configuration) { q->_paused = YES; q->_notice = item[@"error"]; }
            }
            if ([q checkpoint]) dispatch_async(dispatch_get_main_queue(), ^{ [q pump]; });
        });
    }
    if (!_active && [self statistics][@"pending"].unsignedIntegerValue == 0) { _paused = YES; [self checkpoint]; return; }
    if (soonest != DBL_MAX) {
        NSUInteger generation = ++_wakeGeneration;
        __weak SGTranslationQueue *weak = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MAX(0.01, soonest - now) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            SGTranslationQueue *q = weak; if (q && generation == q->_wakeGeneration) [q pump];
        });
    }
}
@end
