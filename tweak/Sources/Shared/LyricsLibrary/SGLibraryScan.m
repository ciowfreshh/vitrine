#import "SGLibraryScan.h"
#import "SGLibraryModel.h"
#import "SGLibraryOriginal.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "SGLibraryStore.h"
#import "Shared/Lyrics/Lyrics.h"
#include <math.h>

NSNotificationName const SGLibraryScanDidChange = @"syna.lyricsLibrary.scan";
static NSString *const spotifyHost = @"spclient.wg.spotify.com";
static NSString *const webHost = @"api.spotify.com";
static NSString *const savedTracksURL = @"https://api.spotify.com/v1/me/tracks?limit=50&offset=0";
static NSString *const fallbackCollection = @"https://spclient.wg.spotify.com/context-resolve/v1/spotify:collection:tracks";

static BOOL transientStatus(NSInteger status) {
    return status == 0 || status == 408 || status == 429 || (status >= 500 && status <= 599);
}

static NSTimeInterval retryDelay(NSHTTPURLResponse *response, NSUInteger attempt) {
    NSString *value = [response valueForHTTPHeaderField:@"Retry-After"];
    NSScanner *scanner = [NSScanner scannerWithString:value ?: @""];
    double seconds = 0;
    if ([scanner scanDouble:&seconds] && scanner.isAtEnd && isfinite(seconds) && seconds >= 0)
        return MAX(1, seconds);
    if (value.length) {
        NSDateFormatter *formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
        formatter.dateFormat = @"EEE, dd MMM yyyy HH:mm:ss zzz";
        NSTimeInterval until = [[formatter dateFromString:value] timeIntervalSinceNow];
        if (until > 0) return until;
    }
    return (response.statusCode == 429 ? 30.0 : 2.0) * (1 << MIN(attempt, 2u));
}

static NSDictionary *dict(id object) { return [object isKindOfClass:NSDictionary.class] ? object : nil; }
static NSArray *list(id object) { return [object isKindOfClass:NSArray.class] ? object : nil; }
static NSString *string(id object) { return [object isKindOfClass:NSString.class] ? object : nil; }

NSURL *SGLibrarySpotifyPageURL(NSString *address) {
    if (![address isKindOfClass:NSString.class] || !address.length || address.length > 8192) return nil;
    if ([address hasPrefix:@"hm://"]) address = [@"https://spclient.wg.spotify.com/" stringByAppendingString:[address substringFromIndex:5]];
    if ([address hasPrefix:@"/"] && ![address hasPrefix:@"//"]) address = [@"https://spclient.wg.spotify.com" stringByAppendingString:address];
    NSURLComponents *parts = [NSURLComponents componentsWithString:address];
    NSString *path = parts.URL.path;
    if (![parts.scheme.lowercaseString isEqual:@"https"] || parts.user || parts.password || parts.port || parts.fragment) return nil;
    NSString *host = parts.host.lowercaseString;
    if ([host isEqual:webHost]) return [path isEqual:@"/v1/me/tracks"] ? parts.URL : nil;
    if (![host isEqual:spotifyHost] || (![path hasPrefix:@"/context-resolve/"] && ![path hasPrefix:@"/context/"] &&
         ![path hasPrefix:@"/playlist/"] && ![path hasPrefix:@"/collection/"])) return nil;
    return parts.URL;
}

static NSArray<NSString *> *artistsIn(id value) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (id item in list(value)) {
        NSString *name = string(item) ?: string(dict(item)[@"name"]);
        if (name.length && ![names containsObject:name]) [names addObject:name];
    }
    return names;
}

NSArray *SGLibraryCollectionPage(id json, NSString **next, NSError **error) {
    *next = nil;
    NSDictionary *response = dict(json);
    NSArray *pages = list(response[@"pages"]);
    NSArray *items = list(response[@"items"]);
    if (items) pages = @[@{@"tracks": items, @"next_page_url": string(response[@"next"]) ?: @""}];
    if (!pages && list(response[@"tracks"])) pages = @[response];
    if (!pages) {
        SGLibraryError(error, @"Spotify trả về trang Bài hát đã thích sai định dạng.");
        return nil;
    }
    NSMutableArray *tracks = [NSMutableArray array];
    for (id item in pages) {
        NSDictionary *page = dict(item);
        NSArray *pageTracks = list(page[@"tracks"]);
        NSString *pageURL = string(page[@"page_url"]);
        NSString *nextURL = string(page[@"next_page_url"]);
        if (!page || (!pageTracks && !pageURL.length)) {
            SGLibraryError(error, @"Không đọc được danh sách bài hát trên trang Spotify.");
            return nil;
        }
        if (nextURL.length) *next = nextURL;
        if (!pageTracks && pageURL.length) *next = pageURL;
        for (id entry in pageTracks) {
            NSDictionary *item = dict(entry);
            NSDictionary *track = dict(item[@"track"]) ?: item;
            NSString *uri = string(track[@"uri"]);
            if (![uri hasPrefix:@"spotify:track:"]) continue;
            NSString *trackID = [uri substringFromIndex:@"spotify:track:".length];
            if (!SGLibraryTrackID(trackID)) continue;
            NSDictionary *meta = dict(track[@"metadata"]);
            NSString *title = string(track[@"name"]) ?: string(meta[@"title"]) ?: string(meta[@"track_name"]) ?: @"";
            NSArray *artists = artistsIn(track[@"artists"] ?: meta[@"artists"]);
            NSString *artist = string(meta[@"artist_name"]) ?: string(meta[@"artist"]);
            if (!artists.count && artist.length) artists = @[artist];
            [tracks addObject:@{@"trackId": trackID, @"uri": uri, @"title": title, @"artists": artists,
                                @"language": @"und", @"source": @"", @"status": @"missing", @"lines": @[]}];
        }
    }
    return tracks;
}

// Spotify's catalog metadata accepts the 128-bit hexadecimal form of the base-62 track ID.
static NSString *hexID(NSString *trackID) {
    const char *digits = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
    uint8_t bytes[16] = {0};
    for (NSUInteger i = 0; i < trackID.length; i++) {
        const char *digit = strchr(digits, [trackID characterAtIndex:i]);
        if (!digit) return nil;
        unsigned carry = (unsigned)(digit - digits);
        for (int j = 15; j >= 0; j--) {
            carry += bytes[j] * 62;
            bytes[j] = carry & 255;
            carry >>= 8;
        }
        if (carry) return nil;
    }
    NSMutableString *hex = [NSMutableString stringWithCapacity:32];
    for (NSUInteger i = 0; i < sizeof(bytes); i++) [hex appendFormat:@"%02x", bytes[i]];
    return hex;
}

@interface SGLibraryRequestDelegate : NSObject <NSURLSessionTaskDelegate>
@end
@implementation SGLibraryRequestDelegate
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
    completionHandler:(void (^)(NSURLRequest *))completionHandler {
    completionHandler(nil);
}
@end

static NSURLSession *scanSession(void) {
    static NSURLSession *session;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.HTTPShouldSetCookies = NO;
        configuration.URLCredentialStorage = nil;
        configuration.URLCache = nil;
        configuration.timeoutIntervalForRequest = 18;
        configuration.timeoutIntervalForResource = 35;
        session = [NSURLSession sessionWithConfiguration:configuration delegate:[SGLibraryRequestDelegate new] delegateQueue:nil];
    });
    return session;
}

@implementation SGLibraryScanner {
    NSURLSessionDataTask *_task;
    NSURL *_source;
    NSMutableOrderedSet<NSString *> *_tracks;
    NSMutableSet<NSString *> *_pages;
    NSUInteger _generation, _processed, _failed, _missing, _original, _translated;
    BOOL _hasHeaders;
    BOOL _contextFallback, _pagesComplete, _canResume, _retrying;
    NSUInteger _total;
    NSMutableOrderedSet<NSString *> *_deferred;
    NSMutableDictionary<NSString *, NSNumber *> *_notBefore;
}

+ (instancetype)shared {
    static SGLibraryScanner *scanner;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ scanner = [self new]; });
    return scanner;
}

- (void)report:(NSString *)text {
    _progress = [text copy];
    [NSNotificationCenter.defaultCenter postNotificationName:SGLibraryScanDidChange object:self];
}

- (void)stop:(NSString *)text {
    _generation++;
    [_task cancel];
    _task = nil;
    _running = NO;
    [self report:text];
    [NSNotificationCenter.defaultCenter postNotificationName:SGLibraryDidChange object:nil];
}

- (void)pause {
    if (!_running) return;
    _canResume = _pagesComplete;
    [self stop:@"Đã tạm dừng. Quét tiếp sẽ xử lý từ bài đang chờ."];
}

- (void)startWithSource:(NSURL *)source {
    if (_running) return;
    BOOL resume = _canResume && (_source == source || [_source isEqual:source]);
    _canResume = NO;
    _source = [source copy];
    if (!resume) {
        _tracks = [NSMutableOrderedSet orderedSet];
        _pages = [NSMutableSet set];
        _deferred = [NSMutableOrderedSet orderedSet];
        _total = _processed = _failed = _missing = _original = _translated = 0;
        _contextFallback = _pagesComplete = _retrying = NO;
    }
    if (!_notBefore) _notBefore = [NSMutableDictionary dictionary];
    _running = YES;
    _hasHeaders = NO;
    NSUInteger generation = ++_generation;
    [self report:@"Đang kết nối với Bài hát đã thích…"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (generation == self->_generation && !self->_hasHeaders) {
            self->_canResume = resume;
            [self stop:@"Spotify chưa sẵn sàng. Hãy mở Bài hát đã thích rồi quét tiếp."];
        }
    });
    SGSpclientHeaders(^(NSDictionary *headers) {
        if (generation != self->_generation) return;
        self->_hasHeaders = YES;
        if (resume) [self processNextWithHeaders:headers];
        else [self fetchPage:SGLibrarySpotifyPageURL(savedTracksURL) headers:headers];
    });
}

- (void)request:(NSURL *)url headers:(NSDictionary *)headers done:(void (^)(id json, NSInteger status))done {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    if ([url.host.lowercaseString isEqual:webHost]) {
        [request setValue:headers[@"authorization"] forHTTPHeaderField:@"Authorization"];
    } else {
        request.allHTTPHeaderFields = headers;
    }
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    if ([url.host isEqual:spotifyHost] && [url.path hasPrefix:@"/color-lyrics/"])
        [NSURLProtocol setProperty:@YES forKey:SGLyricsOwnRequestKey inRequest:request];
    [self sendRequest:request attempt:0 done:done];
}

- (void)after:(NSTimeInterval)delay perform:(dispatch_block_t)action {
    NSUInteger generation = _generation;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(MIN(delay, 86400) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation == self->_generation) action();
    });
}

- (void)loadRequest:(NSURLRequest *)request reply:(void (^)(id, NSHTTPURLResponse *))reply {
    _task = [scanSession() dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSHTTPURLResponse *http = !error && [response isKindOfClass:NSHTTPURLResponse.class] ? (id)response : nil;
        id json = http.statusCode == 200 && data.length <= 12 * 1024 * 1024 ? SGLibraryReadJSON(data, nil) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ reply(json, http); });
    }];
    [_task resume];
}

- (NSTimeInterval)uptime { return NSProcessInfo.processInfo.systemUptime; }

- (void)sendRequest:(NSURLRequest *)request attempt:(NSUInteger)attempt done:(void (^)(id, NSInteger))done {
    NSString *host = request.URL.host.lowercaseString;
    NSTimeInterval now = [self uptime];
    NSTimeInterval wait = [_notBefore[host] doubleValue] - now;
    if (wait > 0) {
        [self after:wait perform:^{ [self sendRequest:request attempt:attempt done:done]; }];
        return;
    }
    NSUInteger generation = _generation;
    [self loadRequest:request reply:^(id json, NSHTTPURLResponse *http) {
        if (generation != self->_generation) return;
        self->_task = nil;
        NSInteger status = http.statusCode;
        if (status == 429)
            self->_notBefore[host] = @([self uptime] + retryDelay(http, attempt));
        if (transientStatus(status) && attempt < 2) {
            [self report:[NSString stringWithFormat:@"Đã xử lý %lu/%lu bài · %@ App sẽ tự thử lại.",
                          (unsigned long)self->_processed, (unsigned long)self->_total,
                          status == 429 ? @"Nguồn yêu cầu chờ." : @"Kết nối bị gián đoạn."]];
            if (status == 429) [self sendRequest:request attempt:attempt + 1 done:done];
            else [self after:retryDelay(http, attempt) perform:^{ [self sendRequest:request attempt:attempt + 1 done:done]; }];
            return;
        }
        done(json, status);
    }];
}

- (SGLibraryStore *)store { return SGLibraryLocalStore(); }

- (void)fetchPage:(NSURL *)url headers:(NSDictionary *)headers {
    if (!url || [_pages containsObject:url.absoluteString] || _pages.count >= 5000) {
        [self stop:@"Spotify trả về liên kết trang không hợp lệ hoặc lặp. Các bài đã lưu vẫn còn."];
        return;
    }
    [_pages addObject:url.absoluteString];
    [self request:url headers:headers done:^(id json, NSInteger status) {
        NSString *next;
        NSArray *tracks = SGLibraryCollectionPage(json, &next, nil);
        if (!tracks) {
            if (!self->_contextFallback && [url.host isEqual:webHost] && self->_pages.count == 1 &&
                status != 0 && status != 429 && status < 500) {
                [self openCollectionContext:headers];
                return;
            }
            [self stop:[NSString stringWithFormat:@"Tải danh sách Spotify thất bại (%ld). Bạn có thể quét tiếp.", (long)status]];
            return;
        }
        NSUInteger generation = self->_generation;
        dispatch_async(SGLibraryQueue(), ^{
            SGLibraryStore *store = [self store];
            for (NSDictionary *candidate in tracks) @autoreleasepool {
                NSError *error;
                NSDictionary *existing = [store track:candidate[@"trackId"] error:&error];
                if (error || (!existing && ![store save:candidate error:&error])) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (generation == self->_generation) [self stop:@"Không thể lưu danh sách bài hát trên thiết bị."];
                    });
                    return;
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != self->_generation) return;
                [self->_tracks addObjectsFromArray:[tracks valueForKey:@"trackId"]];
                [self report:[NSString stringWithFormat:@"Đã tìm thấy %lu bài hát đã thích.", (unsigned long)self->_tracks.count]];
                if (next.length) [self fetchPage:SGLibrarySpotifyPageURL(next) headers:headers];
                else {
                    self->_pagesComplete = YES;
                    self->_total = self->_tracks.count;
                    [self processNextWithHeaders:headers];
                }
            });
        });
    }];
}

- (void)openCollectionContext:(NSDictionary *)headers {
    _contextFallback = YES;
    NSString *active = SGKaraokeCollectionContext();
    if (active.length) {
        [self fetchOwnerCollection:active headers:headers];
        return;
    }
    [self request:[NSURL URLWithString:@"https://api.spotify.com/v1/me"] headers:headers done:^(id json, NSInteger status) {
        NSString *account = string(dict(json)[@"id"]);
        NSString *context = account.length ? [NSString stringWithFormat:@"spotify:user:%@:collection", account] : nil;
        [self fetchOwnerCollection:context headers:headers];
    }];
}

- (void)fetchOwnerCollection:(NSString *)context headers:(NSDictionary *)headers {
    NSString *url = fallbackCollection;
    NSArray<NSString *> *parts = [context componentsSeparatedByString:@":"];
    if (parts.count == 4 && [parts[0] isEqual:@"spotify"] && [parts[1] isEqual:@"user"] && [parts[3] isEqual:@"collection"]) {
        NSCharacterSet *safe = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"];
        NSString *account = [parts[2] stringByAddingPercentEncodingWithAllowedCharacters:safe];
        if (account.length && account.length <= 256) {
            url = [NSString stringWithFormat:@"https://%@/context-resolve/v1/spotify:user:%@:collection", spotifyHost, account];
        }
    }
    [self fetchPage:SGLibrarySpotifyPageURL(url) headers:headers];
}

- (void)processNextWithHeaders:(NSDictionary *)headers {
    if (_processed == _tracks.count) {
        if (!_retrying && _deferred.count) {
            _retrying = YES;
            _failed -= _deferred.count;
            _tracks = _deferred;
            _processed = 0;
            [self report:[NSString stringWithFormat:@"Đang thử lại %lu bài bị lỗi tạm thời…", (unsigned long)_tracks.count]];
            [self processNextWithHeaders:headers];
            return;
        }
        [self stop:[NSString stringWithFormat:@"Đã quét %lu bài · %lu có lời gốc · %lu đã dịch · %lu thiếu lời · %lu lỗi.",
                    (unsigned long)_total, (unsigned long)_original, (unsigned long)_translated,
                    (unsigned long)_missing, (unsigned long)_failed]];
        return;
    }
    NSString *trackID = _tracks[_processed];
    NSUInteger generation = _generation;
    dispatch_async(SGLibraryQueue(), ^{
        NSDictionary *track = [[self store] track:trackID error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self->_generation) return;
            if (!track) {
                [self finished:nil headers:headers retryLater:NO];
            } else if ([track[@"title"] length] && [track[@"artists"] count]) {
                [self processLyrics:track headers:headers];
            } else {
                [self fetchMetadata:track headers:headers];
            }
        });
    });
}

- (void)fetchMetadata:(NSDictionary *)track headers:(NSDictionary *)headers {
    NSString *identifier = hexID(track[@"trackId"]);
    if (!identifier) {
        [self processLyrics:track headers:headers];
        return;
    }
    NSString *address = [NSString stringWithFormat:@"https://%@/metadata/4/track/%@", spotifyHost, identifier];
    [self request:[NSURL URLWithString:address] headers:headers done:^(id json, NSInteger status) {
        NSDictionary *meta = dict(json);
        NSMutableDictionary *named = [track mutableCopy];
        if (string(meta[@"name"]).length) named[@"title"] = meta[@"name"];
        NSArray *artists = artistsIn(meta[@"artist"] ?: meta[@"artists"]);
        if (artists.count) named[@"artists"] = artists;
        [self processLyrics:named headers:headers];
    }];
}

- (void)processLyrics:(NSDictionary *)track headers:(NSDictionary *)headers {
    if ([track[@"lines"] count]) {
        [self commit:track headers:headers retryLater:NO];
        return;
    }
    if (!_source) {
        [self fetchSpotifyOriginal:track headers:headers];
        return;
    }
    NSURL *url = [_source URLByAppendingPathComponent:[track[@"trackId"] stringByAppendingString:@".json"]];
    // The authorized source receives the public track ID and never receives Spotify session headers.
    [self request:url headers:nil done:^(id json, NSInteger status) {
        NSMutableDictionary *record = [track mutableCopy];
        NSDictionary *candidate = status == 200 ? SGLibraryTrack(json, nil) : nil;
        if ([candidate[@"trackId"] isEqual:track[@"trackId"]] && [candidate[@"lines"] count]) {
            for (NSString *key in @[@"source", @"language", @"lines"]) record[key] = candidate[key];
            if (![record[@"title"] length]) record[@"title"] = candidate[@"title"];
            if (![record[@"artists"] count]) record[@"artists"] = candidate[@"artists"];
            [self commit:record headers:headers retryLater:NO];
        } else {
            [self fetchSpotifyOriginal:track headers:headers];
        }
    }];
}

- (void)fetchSpotifyOriginal:(NSDictionary *)track headers:(NSDictionary *)headers {
    NSString *trackID = track[@"trackId"];
    NSArray<SGKaraokeLine *> *cached = SGKaraokeLinesForTrack(trackID);
    NSDictionary *original = SGLibraryOriginalFromLines(track, cached, SGLyricsCreditFor(trackID));
    if (original) {
        [self commit:original headers:headers retryLater:NO];
        return;
    }
    NSString *address = [NSString stringWithFormat:@"https://%@/color-lyrics/v2/track/%@?format=json&vocalRemoval=false&market=from_token", spotifyHost, trackID];
    [self request:[NSURL URLWithString:address] headers:headers done:^(id json, NSInteger status) {
        NSDictionary *record = SGLibrarySpotifyOriginal(track, json);
        if (record) {
            [self commit:record headers:headers retryLater:NO];
            return;
        }
        [self tryVitrineSources:track headers:headers status:status];
    }];
}

- (void)tryVitrineSources:(NSDictionary *)track headers:(NSDictionary *)headers status:(NSInteger)status {
    if (!SGLyricsEnabled()) {
        [self finishMissing:track headers:headers status:status];
        return;
    }
    SGLyricsQuery *query = [SGLyricsQuery new];
    query.trackID = track[@"trackId"];
    query.title = track[@"title"];
    query.artist = [track[@"artists"] firstObject];
    NSUInteger generation = _generation;
    SGLyricsFetchForQuery(query, ^(SGLyricsResult *result) {
        if (generation != self->_generation) return;
        NSDictionary *record = SGLibraryOriginalFromLines(track, result.karaokeLines, result.provider ?: @"Vitrine");
        if (record) [self commit:record headers:headers retryLater:NO];
        else [self finishMissing:track headers:headers status:status];
    });
}

- (void)finishMissing:(NSDictionary *)track headers:(NSDictionary *)headers status:(NSInteger)status {
    NSMutableDictionary *record = [track mutableCopy];
    record[@"status"] = status == 404 || status == 204 ? @"missing" : @"error";
    [self commit:record headers:headers retryLater:transientStatus(status)];
}

- (void)commit:(NSDictionary *)track headers:(NSDictionary *)headers retryLater:(BOOL)retryLater {
    NSUInteger generation = _generation;
    dispatch_async(SGLibraryQueue(), ^{
        SGLibraryStore *store = [self store];
        NSError *error;
        NSDictionary *existing = [store track:track[@"trackId"] error:&error];
        // An import may have happened during the network request. Its original and translations take precedence.
        NSDictionary *candidate = [existing[@"lines"] count] ? existing : SGLibraryTrack(track, &error);
        BOOL saved = !error && candidate && ([candidate isEqual:existing] || [store save:candidate error:&error]);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self->_generation) return;
            [self finished:saved ? candidate : nil headers:headers retryLater:retryLater];
        });
    });
}

- (void)finished:(NSDictionary *)track headers:(NSDictionary *)headers retryLater:(BOOL)retryLater {
    _processed++;
    NSString *status = track[@"status"];
    if ([status isEqual:@"original"]) _original++;
    else if ([status isEqual:@"translated"]) _translated++;
    else if ([status isEqual:@"missing"]) _missing++;
    else _failed++;
    if (retryLater && !_retrying && ![track[@"lines"] count]) [_deferred addObject:_tracks[_processed - 1]];
    if (_processed == 1 || _processed % 10 == 0) {
        [self report:[NSString stringWithFormat:@"%@ %lu/%lu bài · %lu có lời · %lu chưa tìm thấy · %lu lỗi",
                      _retrying ? @"Đang thử lại" : @"Đang lấy lời", (unsigned long)_processed, (unsigned long)_tracks.count, (unsigned long)(_original + _translated),
                      (unsigned long)_missing, (unsigned long)_failed]];
        [NSNotificationCenter.defaultCenter postNotificationName:SGLibraryDidChange object:nil];
    }
    [self after:0.75 perform:^{ [self processNextWithHeaders:headers]; }];
}
@end
