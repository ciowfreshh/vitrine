#import "TranslationQueue.h"
#import <math.h>
#import "LyricsTranslation.h"
#import "Core/SGCore.h"
#import "Core/BatchQueue/SGTranslationQueue.h"
#import "Core/BatchQueue/SGTranslationPage.h"
#import "Core/BatchQueue/SGTranslationAlignment.h"
#import "Core/TranslationStore/SGTranslationStore.h"
#import "TranslationLibrary.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Shared/AlbumQueue/AlbumQueue.h"
#import "Shared/Navigation/Links.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"

static NSString *const kConcurrency = @"spotifyglass.lyrics.batch.concurrency";
static NSString *const kChanged = @"Vitrine.BatchQueueChanged";
static void notice(NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGLocalized(@"Batch translation") message:message preferredStyle:UIAlertControllerStyleAlert];
    alert.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    [alert addAction:[UIAlertAction actionWithTitle:SGLocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}
// Header capture can wait forever before Spotify's first request; the queue must not.
static void headers(void (^done)(NSDictionary *, NSError *)) {
    __block BOOL answered = NO;
    SGSpclientHeaders(^(NSDictionary *value) { if (answered) return; answered = YES; done(value, nil); });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (answered) return; answered = YES;
        done(nil, SGTranslationQueueError(SGTranslationNetwork, SGLocalized(@"Spotify is not ready. Open a song and try again."), 0));
    });
}
static void getJSONAttempt(NSURL *url, NSUInteger attempt, void (^done)(id, NSHTTPURLResponse *, NSError *)) {
    headers(^(NSDictionary *values, NSError *headerError) {
        if (headerError) { done(nil, nil, headerError); return; }
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
        request.timeoutInterval = 30;
        if ([url.host isEqual:@"api.spotify.com"]) {
            for (NSString *key in values) if ([key caseInsensitiveCompare:@"Authorization"] == NSOrderedSame) [request setValue:values[key] forHTTPHeaderField:@"Authorization"];
        } else request.allHTTPHeaderFields = values;
        [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
        [NSURLProtocol setProperty:@YES forKey:SGLyricsOwnRequestKey inRequest:request];
        [[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            id root = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (id)response : nil;
            BOOL transient = error || http.statusCode == 408 || http.statusCode == 429 || http.statusCode >= 500;
            if (transient && attempt < 3) {
                NSTimeInterval delay = MAX(SGTranslationRetryAfter([http valueForHTTPHeaderField:@"Retry-After"], NSDate.date), pow(2, attempt + 1));
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ getJSONAttempt(url, attempt + 1, done); });
            } else dispatch_async(dispatch_get_main_queue(), ^{ done(root, http, error); });
        }] resume];
    });
}
static void getJSON(NSURL *url, void (^done)(id, NSHTTPURLResponse *, NSError *)) { getJSONAttempt(url, 0, done); }
static NSError *requestError(NSHTTPURLResponse *response, NSError *error) {
    if ([error.domain isEqual:SGTranslationQueueErrorDomain]) return error;
    NSInteger status = response.statusCode;
    NSString *message = (status == 401 || status == 403) ? SGLocalized(@"Spotify denied library access. Your session may lack permission for this source.") :
        [NSString stringWithFormat:SGLocalized(@"Could not load Spotify data (HTTP %ld)."), (long)status];
    return SGTranslationQueueError(SGTranslationHTTPFailure(status, error, nil), error ? SGLocalized(@"Network error while loading lyrics. Try again.") : message,
        SGTranslationRetryAfter([response valueForHTTPHeaderField:@"Retry-After"], NSDate.date));
}

@interface SGBatchManager : NSObject
@property (nonatomic, strong) SGTranslationQueue *queue;
@property (nonatomic) BOOL scanning, scanPaused;
- (void)start:(NSString *)uri;
- (void)resume;
- (void)pause;
- (void)scanPage;
@end
@implementation SGBatchManager
- (instancetype)init {
    if (!(self = [super init])) return nil;
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
    _queue = [[SGTranslationQueue alloc] initWithURL:[support URLByAppendingPathComponent:@"Vitrine/Translations/queue-v1.json"]];
    _scanPaused = YES;
    NSInteger count = [NSUserDefaults.standardUserDefaults integerForKey:kConcurrency];
    _queue.concurrency = count ?: 2;
    _queue.changed = ^{ [NSNotificationCenter.defaultCenter postNotificationName:kChanged object:nil]; };
    __weak SGTranslationQueue *weakQueue = _queue;
    _queue.execute = ^(NSDictionary *item, NSString *language, void (^done)(NSString *, NSError *)) {
        NSString *track = item[@"id"];
        void (^translate)(NSArray<SGKaraokeLine *> *, NSError *) = ^(NSArray<SGKaraokeLine *> *original, NSError *error) {
            if (error) { done(nil, error); return; }
            BOOL words = NO;
            for (SGKaraokeLine *line in original) if (SGTranslationLineNeedsText(SGKaraokeLineText(line))) words = YES;
            if (!words) { done(@"skipped:no_lyrics", nil); return; }
            NSError *readError = nil;
            BOOL saved = [SGSavedTranslationStore() recordForTrack:track language:language error:&readError] != nil;
            if (readError) { done(nil, SGTranslationQueueError(SGTranslationStorage, SGLocalized(@"Could not read saved translations."), 0)); return; }
            NSUInteger missing = saved ? SGLyricsSavedTranslationMissing(track, language, original) : original.count;
            if (saved && !missing) { done(@"skipped:saved", nil); return; }
            BOOL verifyOnly = [weakQueue.context[@"verifyOnly"] boolValue];
            if (saved && (verifyOnly || ![weakQueue.context[@"repairSaved"] boolValue])) {
                done(nil, SGTranslationQueueError(SGTranslationSavedMismatch,
                    [NSString stringWithFormat:SGLocalized(@"Saved translation does not cover %lu lyric lines from this source. No AI request was sent. Use Translate missing saved lines to repair it."), (unsigned long)missing], 0)); return;
            }
            if (verifyOnly) { done(@"skipped:not_saved", nil); return; }
            if ([weakQueue.context[@"repairSaved"] boolValue] && !saved) { done(@"skipped:not_saved", nil); return; }
            if (!SGKaraokeInAnotherLanguage(original, language)) { done(@"skipped:same_language", nil); return; }
            if (!SGAITranslatorReady()) { done(nil, SGTranslationQueueError(SGTranslationConfiguration, SGLocalized(@"Configure the AI provider, model and API key in Lyrics settings."), 0)); return; }
            NSMutableArray *lines = [NSMutableArray arrayWithCapacity:original.count];
            for (SGKaraokeLine *line in original) {
                SGKaraokeLine *copy = [line copy]; copy.translation = nil; copy.translationMade = NO;
                [lines addObject:copy];
            }
            SGLyricsSyncSavedTranslation(track, language, lines);
            NSMutableArray *needed = [NSMutableArray array], *positions = [NSMutableArray array];
            for (NSUInteger i = 0; i < lines.count; ++i) if (!((SGKaraokeLine *)lines[i]).translationMade && SGTranslationLineNeedsText(SGKaraokeLineText(lines[i]))) {
                [needed addObject:lines[i]]; [positions addObject:@(i)];
            }
            if (!needed.count) { done(@"skipped:saved", nil); return; }
            if (![weakQueue markCandidate:track]) { done(nil, SGTranslationQueueError(SGTranslationStorage, SGLocalized(@"Could not write translations. Check available storage."), 0)); return; }
            SGTranslationSource *source = SGAITranslatorSource();
            SGLyricsTranslateQueuedWithContext(track, needed, saved ? original : nil, language, ^(NSArray *answer, NSError *failure) {
                if (failure) { done(nil, failure); return; }
                NSMutableArray *texts = [NSMutableArray array];
                for (SGKaraokeLine *line in needed) [texts addObject:SGKaraokeLineText(line) ?: @""];
                if (answer.count != needed.count || SGTranslationMissingLines(texts, answer).count) {
                    done(nil, SGTranslationQueueError(SGTranslationLineCount, SGLocalized(@"The AI returned empty translations for lyric lines. The song was not marked complete."), 0)); return;
                }
                // Re-read before merging: a single-song request may have completed while this one ran.
                SGLyricsSyncSavedTranslation(track, language, lines);
                for (NSUInteger n = 0; n < positions.count; ++n) {
                    SGKaraokeLine *line = lines[[positions[n] unsignedIntegerValue]];
                    if (!line.translationMade) { line.translation = answer[n]; line.translationMade = YES; }
                }
                if (!SGLyricsSaveTranslation(track, language, lines, source) || SGLyricsSavedTranslationMissing(track, language, original)) {
                    done(nil, SGTranslationQueueError(SGTranslationStorage, SGLocalized(@"Could not write translations. Check available storage."), 0)); return;
                }
                [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationsDidChangeNotification object:nil];
                done(@"succeeded", nil);
            });
        };
        NSArray *cached = SGKaraokeLinesForTrack(track);
        if (cached.count) { translate(cached, nil); return; }
        void (^spotifyFallback)(BOOL) = ^(BOOL providerFailed) {
            NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://spclient.wg.spotify.com/color-lyrics/v2/track/%@?format=json&vocalRemoval=false&market=from_token", track]];
            getJSON(url, ^(id root, NSHTTPURLResponse *response, NSError *error) {
                if (error || (response.statusCode != 200 && response.statusCode != 404)) { translate(nil, requestError(response, error)); return; }
                NSData *body = [root isKindOfClass:NSDictionary.class] ? [NSJSONSerialization dataWithJSONObject:root options:0 error:nil] : nil;
                NSArray *spotify = SGKaraokeLinesFromBody(body);
                if (spotify.count && !providerFailed) { translate(spotify, nil); return; }
                if (response.statusCode == 404 && !providerFailed) done(@"skipped:no_lyrics", nil);
                else translate(nil, SGTranslationQueueError(SGTranslationNetwork, SGLocalized(@"Lyrics could not be loaded. This is not confirmed as a song without lyrics."), 0));
            });
        };
        if (!SGLyricsEnabled()) { spotifyFallback(NO); return; }
        void (^fetchSources)(NSDictionary *) = ^(NSDictionary *metadata) {
            SGLyricsQuery *query = [SGLyricsQuery new]; query.trackID = track;
            query.title = [metadata[@"name"] isKindOfClass:NSString.class] ? metadata[@"name"] : item[@"name"];
            query.artist = item[@"artist"];
            NSArray *artists = [metadata[@"artists"] isKindOfClass:NSArray.class] ? metadata[@"artists"] : nil;
            if ([artists.firstObject isKindOfClass:NSDictionary.class] && [artists.firstObject[@"name"] isKindOfClass:NSString.class]) query.artist = artists.firstObject[@"name"];
            if ([metadata[@"duration_ms"] isKindOfClass:NSNumber.class]) query.seconds = [metadata[@"duration_ms"] integerValue] / 1000;
            NSUInteger failures = SGLyricsFailures();
            SGLyricsFetchForQuery(query, ^(SGLyricsResult *result) {
                if (result.karaokeLines.count) translate(result.karaokeLines, nil);
                else if (result.instrumental) done(@"skipped:no_lyrics", nil);
                else spotifyFallback(SGLyricsFailures() != failures);
            });
        };
        // Off-player album/context pages sometimes carry IDs only. Name the track before asking the
        // same provider chain the player uses; never silently translate a different lower-priority source.
        if ([item[@"name"] length] && [item[@"artist"] length]) { fetchSources(nil); return; }
        NSURL *metadataURL = [NSURL URLWithString:[@"https://api.spotify.com/v1/tracks/" stringByAppendingString:track]];
        getJSON(metadataURL, ^(id root, NSHTTPURLResponse *response, NSError *error) {
            if (error || response.statusCode != 200 || ![root isKindOfClass:NSDictionary.class]) { translate(nil, requestError(response, error)); return; }
            fetchSources(root);
        });
    };
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(pause) name:UIApplicationDidEnterBackgroundNotification object:nil];
    return self;
}
- (void)pause { _scanPaused = YES; [_queue pause]; }
- (void)start:(NSString *)uri {
    if (_scanning || !_queue.paused) { notice(SGLocalized(@"Pause the current queue before adding another source.")); return; }
    if (![_queue prepareLanguage:SGLyricsTranslationTarget()]) { notice(SGLocalized(@"Finish the existing queue before changing its target language.")); return; }
    NSURL *url;
    if ([uri isEqual:@"spotify:collection:tracks"]) url = [NSURL URLWithString:@"https://api.spotify.com/v1/me/tracks?limit=50&offset=0"];
    else if (SGIsValidEntityURI(uri)) url = [NSURL URLWithString:[@"https://spclient.wg.spotify.com/context-resolve/v1/" stringByAppendingString:uri]];
    if (!url) { notice(SGLocalized(@"Choose a valid Spotify album or playlist.")); return; }
    // A partially scanned source keeps its cursor until resumed; never silently replace it.
    if (_queue.context[@"next"]) { notice(SGLocalized(@"Resume the unfinished source scan first.")); return; }
    _queue.context[@"source"] = uri; _queue.context[@"next"] = url.absoluteString;
    _queue.context[@"visited"] = @[]; _queue.context[@"scanned"] = @0;
    [_queue.context removeObjectForKey:@"scanError"];
    if ([_queue checkpoint]) { _scanPaused = NO; [self scanPage]; }
}
- (void)resume {
    if (_queue.context[@"next"]) { if (_scanning) return; _scanPaused = NO; [self scanPage]; }
    else [_queue resume];
}
- (void)scanPage {
    if (_scanPaused || _scanning) return;
    NSString *address = _queue.context[@"next"];
    NSURL *url = SGTranslationPageURL(address, nil);
    if (!url) { _queue.context[@"scanError"] = SGLocalized(@"Invalid source pagination URL."); [_queue checkpoint]; return; }
    _scanning = YES;
    getJSON(url, ^(id root, NSHTTPURLResponse *response, NSError *error) {
        self.scanning = NO;
        if (error || response.statusCode != 200) {
            self.queue.context[@"scanError"] = requestError(response, error).localizedDescription;
            self.scanPaused = YES; [self.queue checkpoint]; return;
        }
        NSString *next; NSUInteger scanned;
        NSArray *tracks = SGTranslationTracksPage(root, url, &next, &scanned);
        NSArray *visited = self.queue.context[@"visited"] ?: @[];
        if (!tracks || (next && ([visited containsObject:next] || [next isEqual:address]))) {
            self.queue.context[@"scanError"] = SGLocalized(@"Spotify returned incomplete or repeated pagination. The partial scan was preserved.");
            self.scanPaused = YES; [self.queue checkpoint]; return;
        }
        self.queue.context[@"visited"] = [visited arrayByAddingObject:address];
        self.queue.context[@"scanned"] = @([self.queue.context[@"scanned"] unsignedIntegerValue] + scanned);
        if (next) self.queue.context[@"next"] = next; else [self.queue.context removeObjectForKey:@"next"];
        [self.queue.context removeObjectForKey:@"scanError"];
        if (![self.queue appendTracks:tracks]) { self.scanPaused = YES; return; }
        if (self.scanPaused) return;
        if (next) [self scanPage]; else [self.queue resume];
    });
}
@end
static SGBatchManager *manager(void) { static SGBatchManager *value; static dispatch_once_t once; dispatch_once(&once, ^{ value = [SGBatchManager new]; }); return value; }

@interface SGBatchLibraryPicker : SGPage
@property (nonatomic, copy) NSString *address;
@property (nonatomic, strong) NSMutableArray *entries;
@property (nonatomic, strong) NSMutableSet *visited;
@end
@implementation SGBatchLibraryPicker
- (void)viewDidLoad { [super viewDidLoad]; _entries = [NSMutableArray array]; _visited = [NSMutableSet set]; [self loadPage]; }
- (void)loadPage {
    NSURL *url = SGTranslationPageURL(_address, nil);
    if (!url || [_visited containsObject:_address]) return;
    [_visited addObject:_address];
    getJSON(url, ^(id root, NSHTTPURLResponse *response, NSError *error) {
        if (error || response.statusCode != 200 || ![root isKindOfClass:NSDictionary.class] || ![root[@"items"] isKindOfClass:NSArray.class]) {
            [self.visited removeObject:self.address]; notice(requestError(response, error).localizedDescription); [self.tableView reloadData]; return;
        }
        for (id item in root[@"items"]) {
            if (![item isKindOfClass:NSDictionary.class]) continue;
            id entity = item[@"album"] ?: item;
            if ([entity isKindOfClass:NSDictionary.class] && SGIsValidEntityURI(entity[@"uri"])) [self.entries addObject:entity];
        }
        id next = root[@"next"];
        self.address = [next isKindOfClass:NSString.class] ? SGTranslationPageURL(next, url).absoluteString : nil;
        [self.tableView reloadData];
        if (!self.entries.count && !self.address) notice(SGLocalized(@"No songs found"));
    });
}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return _entries.count + (_address ? 1 : 0); }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.textLabel.text = path.row < (NSInteger)_entries.count ? _entries[path.row][@"name"] : SGLocalized(@"Load more");
    cell.textLabel.numberOfLines = 0; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    if (path.row == (NSInteger)_entries.count) { [self loadPage]; return; }
    [manager() start:_entries[path.row][@"uri"]]; [self.navigationController popViewControllerAnimated:YES];
}
@end

@interface SGBatchPage : SGPage
@property (nonatomic, strong) UIProgressView *progress;
@property (nonatomic, strong) UILabel *progressLabel;
@end
@implementation SGBatchPage
- (void)viewDidLoad {
    [super viewDidLoad]; self.title = SGLocalized(@"Batch translation");
    _progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _progress.frame = CGRectMake(20, 20, MAX(1, self.view.bounds.size.width - 40), 4);
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 76)];
    _progressLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 30, self.view.bounds.size.width - 40, 40)];
    _progressLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth; _progressLabel.numberOfLines = 0;
    _progressLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; [header addSubview:_progressLabel];
    _progress.autoresizingMask = UIViewAutoresizingFlexibleWidth; [header addSubview:_progress]; self.tableView.tableHeaderView = header;
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:kChanged object:nil]; [self refresh]; }
- (void)viewWillDisappear:(BOOL)animated { [super viewWillDisappear:animated]; [NSNotificationCenter.defaultCenter removeObserver:self name:kChanged object:nil]; }
- (void)refresh {
    NSDictionary *s = manager().queue.statistics;
    NSUInteger processed = [s[@"succeeded"] unsignedIntegerValue] + [s[@"failed"] unsignedIntegerValue] + [s[@"skipped"] unsignedIntegerValue];
    _progress.progress = [s[@"total"] floatValue] ? processed / [s[@"total"] floatValue] : 0;
    _progressLabel.text = [NSString stringWithFormat:SGLocalized(@"Processed %lu / %lu songs"), (unsigned long)processed, [s[@"total"] unsignedLongValue]];
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 4; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 4; if (section == 1) return 9; if (section == 2) return 6;
    NSUInteger n = 0; for (NSDictionary *item in manager().queue.items) if (item[@"error"]) ++n; return n;
}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    return @[SGLocalized(@"Source"), SGLocalized(@"Progress"), SGLocalized(@"Controls"), SGLocalized(@"Error details")][section];
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    if (section == 0) return SGLocalized(@"Each song uses your AI settings and translation rules. Saved translations and songs in the target language are skipped.");
    if (section == 2) return manager().queue.notice ? SGLocalized(manager().queue.notice) : manager().queue.context[@"scanError"] ?: SGLocalized(@"Progress is saved after each song. Resume when Spotify is active; iOS may suspend work in the background.");
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.textLabel.numberOfLines = 0; cell.detailTextLabel.numberOfLines = 0;
    SGTranslationQueue *q = manager().queue; NSDictionary *s = q.statistics;
    if (path.section == 0) { cell.textLabel.text = @[SGLocalized(@"Translate all Liked Songs"), SGLocalized(@"Choose playlist"), SGLocalized(@"Choose album"), SGLocalized(@"Add album or playlist link")][path.row]; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator; }
    else if (path.section == 1) {
        NSArray *keys = @[@"total", @"succeeded", @"failed", @"skipped", @"running", @"pending"];
        NSArray *labels = @[SGLocalized(@"Songs in queue"), SGLocalized(@"Translated"), SGLocalized(@"Failed"), SGLocalized(@"Skipped"), SGLocalized(@"Translating"), SGLocalized(@"Unprocessed")];
        if (path.row < 6) { cell.textLabel.text = labels[path.row]; cell.detailTextLabel.text = [s[keys[path.row]] stringValue]; }
        else if (path.row == 6) { cell.textLabel.text = SGLocalized(@"Songs scanned from source"); cell.detailTextLabel.text = [q.context[@"scanned"] stringValue] ?: @"0"; }
        else if (path.row == 7) { cell.textLabel.text = SGLocalized(@"Target language"); cell.detailTextLabel.text = q.language ?: SGLyricsTranslationTarget(); }
        else { cell.textLabel.text = SGLocalized(@"Songs needing translation (checked)"); cell.detailTextLabel.text = [s[@"eligible"] stringValue]; }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if (path.section == 2) {
        cell.textLabel.text = @[SGLocalized(@"Start / Resume untranslated songs"), SGLocalized(@"Pause"), SGLocalized(@"Retry failed songs"), SGLocalized(@"Concurrent AI requests"), SGLocalized(@"Check saved results (no AI)"), SGLocalized(@"Translate missing saved lines")][path.row];
        if (path.row == 3) cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu (%lu)", (unsigned long)q.concurrency, (unsigned long)q.effectiveConcurrency];
        if (path.row == 4) cell.detailTextLabel.text = SGLocalized(@"Recheck this queue against the playback lyrics source. No AI requests are sent.");
        if (path.row == 5) cell.detailTextLabel.text = SGLocalized(@"Uses your AI API only for missing lines in saved songs. Existing translated lines are kept.");
    } else {
        NSMutableArray *errors = [NSMutableArray array]; for (NSDictionary *item in q.items) if (item[@"error"]) [errors addObject:item];
        NSDictionary *item = errors[path.row]; cell.textLabel.text = item[@"title"]; cell.detailTextLabel.text = SGLocalized(item[@"error"]); cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES]; SGBatchManager *m = manager();
    if (path.section == 2) {
        if (path.row == 0) { [m.queue.context removeObjectForKey:@"verifyOnly"]; [m.queue.context removeObjectForKey:@"repairSaved"]; [m resume]; }
        else if (path.row == 1) [m pause];
        else if (path.row == 2) { [m.queue.context removeObjectForKey:@"verifyOnly"]; [m.queue.context removeObjectForKey:@"repairSaved"]; [m.queue retryFailures]; [m resume]; }
        else if (path.row == 4 || path.row == 5) {
            [m pause];
            if (![m.queue recheckSavedResults]) { notice(SGLocalized(@"Wait for the current requests to finish, then try again.")); return; }
            if (path.row == 5) { [m.queue.context removeObjectForKey:@"verifyOnly"]; m.queue.context[@"repairSaved"] = @YES; }
            [m.queue checkpoint]; [m.queue resume];
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGLocalized(@"Concurrent AI requests") message:nil preferredStyle:UIAlertControllerStyleAlert];
            for (NSInteger i = 1; i <= 3; ++i) [alert addAction:[UIAlertAction actionWithTitle:@(i).stringValue style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { m.queue.concurrency = i; [NSUserDefaults.standardUserDefaults setInteger:i forKey:kConcurrency]; [self refresh]; }]];
            [alert addAction:[UIAlertAction actionWithTitle:SGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:alert animated:YES completion:nil];
        }
        return;
    }
    if (path.section != 0) return;
    if (path.row == 0) { [m start:@"spotify:collection:tracks"]; return; }
    if (path.row == 3) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGLocalized(@"Add album or playlist link") message:nil preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.keyboardType = UIKeyboardTypeURL; field.autocapitalizationType = UITextAutocapitalizationTypeNone; }];
        [alert addAction:[UIAlertAction actionWithTitle:SGLocalized(@"Start") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) { [m start:SGSpotifyURIFromText(alert.textFields.firstObject.text).absoluteString]; }]];
        [alert addAction:[UIAlertAction actionWithTitle:SGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]]; [self presentViewController:alert animated:YES completion:nil]; return;
    }
    SGBatchLibraryPicker *picker = [SGBatchLibraryPicker new]; picker.title = path.row == 1 ? SGLocalized(@"Choose playlist") : SGLocalized(@"Choose album");
    picker.address = path.row == 1 ? @"https://api.spotify.com/v1/me/playlists?limit=50" : @"https://api.spotify.com/v1/me/albums?limit=50";
    SGShowPage(self, picker);
}
@end
UIViewController *SGBatchQueuePage(void) { return [SGBatchPage new]; }
SGModRow *SGBatchQueueRow(void) { return SGPageRow(SGLocalized(@"Batch translation"), ^UIViewController *{ return SGBatchQueuePage(); }); }
void SGBatchQueueStart(NSString *uri, UIWindow *window) { [manager() start:uri]; SGShowPage(SGTopController(), SGBatchQueuePage()); }
BOOL SGBatchQueueRunning(void) { return manager().scanning || !manager().queue.paused; }
