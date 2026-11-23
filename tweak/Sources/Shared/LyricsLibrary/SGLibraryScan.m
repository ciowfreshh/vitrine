#import "SGLibraryScan.h"
#import "SGLibraryModel.h"
#import "SGLibraryOriginal.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "SGLibraryStore.h"
#import "Shared/Lyrics/Lyrics.h"

NSNotificationName const SGLibraryScanDidChange = @"syna.lyricsLibrary.scan";
static NSString *const spotifyHost = @"spclient.wg.spotify.com";
static NSString *const webHost = @"api.spotify.com";
static NSString *const savedTracksURL = @"https://api.spotify.com/v1/me/tracks?limit=50&offset=0";
static NSString *const fallbackCollection = @"https://spclient.wg.spotify.com/context-resolve/v1/spotify:collection:tracks";

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
    BOOL _contextFallback;
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
    if (_running) [self stop:@"Đã tạm dừng. Các bài đã lưu sẽ được giữ khi quét tiếp."];
}

- (void)startWithSource:(NSURL *)source {
    if (_running) return;
    _source = [source copy];
    _tracks = [NSMutableOrderedSet orderedSet];
    _pages = [NSMutableSet set];
    _processed = _failed = _missing = _original = _translated = 0;
    _contextFallback = NO;
    _running = YES;
    NSUInteger generation = ++_generation;
    [self report:@"Đang kết nối với Bài hát đã thích…"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (generation == self->_generation && !self->_pages.count) {
            [self stop:@"Spotify chưa sẵn sàng. Hãy mở Bài hát đã thích rồi quét tiếp."];
        }
    });
    SGSpclientHeaders(^(NSDictionary *headers) {
        if (generation != self->_generation) return;
        [self fetchPage:SGLibrarySpotifyPageURL(savedTracksURL) headers:headers];
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
    NSUInteger generation = _generation;
    _task = [scanSession() dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = !error && [response isKindOfClass:NSHTTPURLResponse.class] ? [(NSHTTPURLResponse *)response statusCode] : 0;
        id json = status == 200 && data.length <= 12 * 1024 * 1024 ? SGLibraryReadJSON(data, nil) : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self->_generation) return;
            self->_task = nil;
            done(json, status);
        });
    }];
    [_task resume];
}

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
            SGLibraryStore *store = SGLibraryLocalStore();
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
                else [self processNextWithHeaders:headers];
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
        [self stop:[NSString stringWithFormat:@"Đã quét %lu bài · %lu có lời gốc · %lu đã dịch · %lu thiếu lời · %lu lỗi.",
                    (unsigned long)_processed, (unsigned long)_original, (unsigned long)_translated,
                    (unsigned long)_missing, (unsigned long)_failed]];
        return;
    }
    NSString *trackID = _tracks[_processed];
    NSUInteger generation = _generation;
    dispatch_async(SGLibraryQueue(), ^{
        NSDictionary *track = [SGLibraryLocalStore() track:trackID error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self->_generation) return;
            if (!track) {
                [self finished:nil headers:headers pauseForError:NO];
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
        if (status == 429 || status == 401 || status == 403 || status == 0) {
            if (![track[@"lines"] count]) named[@"status"] = @"error";
            [self commit:named headers:headers pauseForError:YES];
        } else {
            [self processLyrics:named headers:headers];
        }
    }];
}

- (void)processLyrics:(NSDictionary *)track headers:(NSDictionary *)headers {
    if ([track[@"lines"] count]) {
        [self commit:track headers:headers pauseForError:NO];
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
            [self commit:record headers:headers pauseForError:NO];
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
        [self commit:original headers:headers pauseForError:NO];
        return;
    }
    NSString *address = [NSString stringWithFormat:@"https://%@/color-lyrics/v2/track/%@?format=json&vocalRemoval=false&market=from_token", spotifyHost, trackID];
    [self request:[NSURL URLWithString:address] headers:headers done:^(id json, NSInteger status) {
        NSDictionary *record = SGLibrarySpotifyOriginal(track, json);
        if (record) {
            [self commit:record headers:headers pauseForError:NO];
            return;
        }
        if (status == 429 || status == 0 || status >= 500) {
            [self finishMissing:track headers:headers status:status];
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
        if (record) [self commit:record headers:headers pauseForError:NO];
        else [self finishMissing:track headers:headers status:status];
    });
}

- (void)finishMissing:(NSDictionary *)track headers:(NSDictionary *)headers status:(NSInteger)status {
    NSMutableDictionary *record = [track mutableCopy];
    record[@"status"] = status == 404 || status == 204 ? @"missing" : @"error";
    [self commit:record headers:headers pauseForError:status == 0 || status == 429 || status >= 500];
}

- (void)commit:(NSDictionary *)track headers:(NSDictionary *)headers pauseForError:(BOOL)pauseForError {
    NSUInteger generation = _generation;
    dispatch_async(SGLibraryQueue(), ^{
        SGLibraryStore *store = SGLibraryLocalStore();
        NSError *error;
        NSDictionary *existing = [store track:track[@"trackId"] error:&error];
        // An import may have happened during the network request. Its original and translations take precedence.
        NSDictionary *candidate = [existing[@"lines"] count] ? existing : SGLibraryTrack(track, &error);
        BOOL saved = !error && candidate && ([candidate isEqual:existing] || [store save:candidate error:&error]);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self->_generation) return;
            [self finished:saved ? candidate : nil headers:headers pauseForError:pauseForError];
        });
    });
}

- (void)finished:(NSDictionary *)track headers:(NSDictionary *)headers pauseForError:(BOOL)pauseForError {
    _processed++;
    NSString *status = track[@"status"];
    if ([status isEqual:@"original"]) _original++;
    else if ([status isEqual:@"translated"]) _translated++;
    else if ([status isEqual:@"missing"]) _missing++;
    else _failed++;
    if (pauseForError) {
        [self stop:[NSString stringWithFormat:@"Đã tạm dừng do lỗi kết nối. Đã xử lý %lu/%lu bài. Chọn quét tiếp để thử lại.",
                    (unsigned long)_processed, (unsigned long)_tracks.count]];
        return;
    }
    if (_processed == 1 || _processed % 10 == 0) {
        [self report:[NSString stringWithFormat:@"Đang lấy lời %lu/%lu bài · %lu có lời · %lu chưa tìm thấy · %lu lỗi",
                      (unsigned long)_processed, (unsigned long)_tracks.count, (unsigned long)(_original + _translated),
                      (unsigned long)_missing, (unsigned long)_failed]];
        [NSNotificationCenter.defaultCenter postNotificationName:SGLibraryDidChange object:nil];
    }
    [self processNextWithHeaders:headers];
}
@end
