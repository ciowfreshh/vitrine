#import <Foundation/Foundation.h>
#import "Core/SGVietnamese.h"
#import "Shared/LyricsLibrary/SGLibraryModel.h"
#import "Shared/LyricsLibrary/SGLibraryStore.h"
#import "Shared/LyricsLibrary/SGLibraryZIP.h"
#import "Shared/LyricsLibrary/SGLibraryScan.h"
#import "Shared/LyricsLibrary/SGLyricsLibrary.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Shared/LyricsLibrary/SGLibraryOriginal.h"

void SGSpclientHeaders(void (^completion)(NSDictionary *headers)) { completion(nil); }
void SGLog(NSString *format, ...) {}
NSString *SGKaraokeCollectionContext(void) { return nil; }
NSArray<SGKaraokeLine *> *SGKaraokeLinesForTrack(NSString *trackID) { return nil; }
NSString *SGLyricsCreditFor(NSString *trackID) { return nil; }
BOOL SGLyricsEnabled(void) { return NO; }
void SGLyricsFetchForQuery(SGLyricsQuery *query, void (^done)(SGLyricsResult *result)) { done(nil); }
NSString *const SGLyricsOwnRequestKey = @"TestOwnedRequest";
@implementation SGLyricsQuery
@end

static void check(BOOL condition, NSString *message) {
    if (condition) return;
    NSLog(@"FAIL: %@", message);
    exit(1);
}

static NSString *trackID(NSUInteger index) { return [NSString stringWithFormat:@"%022lu", (unsigned long)index]; }

static NSDictionary *fixture(NSUInteger index) {
    NSString *identifier = trackID(index);
    BOOL missing = index % 13 == 0;
    BOOL timed = index % 7 != 0;
    return @{@"trackId": identifier, @"uri": [@"spotify:track:" stringByAppendingString:identifier],
             @"title": [NSString stringWithFormat:@"Bài %lu", (unsigned long)index], @"artists": @[@"Nghệ sĩ mô phỏng"],
             @"source": missing ? @"" : @"Bộ dữ liệu mô phỏng", @"language": @"en",
             @"status": missing ? @"missing" : @"original", @"token": @"not-a-real-secret",
             @"lines": missing ? @[] : @[
                 @{@"id": @"0", @"index": @0, @"text": @"Synthetic repeated line", @"startMs": timed ? @1000 : NSNull.null,
                   @"endMs": timed ? @2000 : NSNull.null},
                 @{@"id": @"1", @"index": @1, @"text": @"Synthetic repeated line", @"startMs": timed ? @3000 : NSNull.null,
                   @"endMs": timed ? @4000 : NSNull.null},
             ]};
}

static NSDictionary *translatedTrack(NSDictionary *original) {
    NSMutableDictionary *record = [original mutableCopy];
    NSMutableArray *lines = [NSMutableArray array];
    for (NSDictionary *line in original[@"lines"]) {
        NSMutableDictionary *translated = [line mutableCopy];
        translated[@"translation"] = [line[@"id"] isEqual:@"0"] ? @"Dòng thứ nhất" : @"Dòng điệp khúc";
        [lines addObject:translated];
    }
    record[@"lines"] = lines;
    return record;
}

static NSURL *temporary(NSURL *root, NSString *name) { return [root URLByAppendingPathComponent:name]; }

static void writeJSON(id value, NSURL *url) {
    check([SGLibraryJSON(value, nil) writeToURL:url atomically:YES], @"write JSON fixture");
}

int main(void) {
    @autoreleasepool {
        check([SGVI(@"SponsorBlock") isEqual:@"SponsorBlock"] &&
              [SGVI(@"Categories & behavior") isEqual:@"Danh mục và hành vi"] &&
              [SGVI(@"Legacy Liquid Glass") isEqual:@"Liquid Glass cho iOS cũ"] &&
              [SGVIError(@"Gemini answered 2 lines for the song's 3. Try again.") isEqual:@"Gemini trả về 2 dòng trong khi bài có 3 dòng. Hãy thử lại."],
              @"Vietnamese settings and formatted errors preserve provider and numeric values");
        NSURL *root = [NSFileManager.defaultManager.temporaryDirectory URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSURL *storeURL = temporary(root, @"db");
        SGLibraryStore *store = [[SGLibraryStore alloc] initWithDirectory:storeURL];
        NSMutableArray *ids = [NSMutableArray array];
        for (NSUInteger i = 1; i <= 2100; i++) @autoreleasepool {
            check([store save:fixture(i) error:nil], @"write generated track");
            [ids addObject:trackID(i)];
        }
        store = [[SGLibraryStore alloc] initWithDirectory:storeURL];
        check(store.summaries.count == 2100, @"relaunch 2,100 tracks");
        NSURL *backup = temporary(root, @"liked.zip");
        check([store exportIDs:ids toURL:backup error:nil], @"export all with missing records");
        SGLibraryZIP *zip = [[SGLibraryZIP alloc] initWithData:[NSData dataWithContentsOfURL:backup] error:nil];
        check(zip.names.count == 2101, @"one manifest and 2,100 track files");
        NSArray *manifest = SGLibraryDocument(SGLibraryReadJSON([zip dataForName:@"manifest.json" error:nil], nil), nil);
        check(manifest.count == 2100 && [manifest[12][@"status"] isEqual:@"missing"], @"manifest preserves missing status");
        NSDictionary *original = SGLibraryReadJSON([zip dataForName:[NSString stringWithFormat:@"tracks/%@.json", ids[0]] error:nil], nil);
        check(!original[@"token"] && [original[@"lines"] count] == 2, @"export original and exclude unknown fields");
        NSURL *single = temporary(root, @"edited.json");
        writeJSON(translatedTrack(original), single);
        check([[store importURL:single error:nil][@"translated"] intValue] == 1, @"import translations");
        NSDictionary *saved = [store track:ids[0] error:nil];
        NSArray<SGKaraokeLine *> *playback = SGLibraryKaraokeLines(saved);
        check(playback.count == 2 && playback[0].start == 1000 && playback[1].start == 3000 &&
              [playback[0].translation isEqual:@"Dòng thứ nhất"] && [playback[1].translation isEqual:@"Dòng điệp khúc"] &&
              SGKaraokeLeadLine(playback, 3500) == 1, @"repeated line playback uses index and exact timing");
        NSArray<SGKaraokeLine *> *plain = SGLibraryKaraokeLines([store track:trackID(7) error:nil]);
        check(SGKaraokeLinesTiming(plain) == SGKaraokeTimingNone, @"untimed lyrics");
        NSMutableDictionary *damaged = [translatedTrack(original) mutableCopy];
        NSMutableArray *lines = [damaged[@"lines"] mutableCopy];
        NSMutableDictionary *changed = [lines[0] mutableCopy];
        changed[@"startMs"] = @1001;
        lines[0] = changed;
        damaged[@"lines"] = lines;
        writeJSON(damaged, single);
        check([[store importURL:single error:nil][@"errors"] intValue] == 1 &&
              [[store track:ids[0] error:nil] isEqual:saved], @"changed timestamp leaves persisted good data");
        writeJSON(@{@"format": SGLibraryFormat, @"version": @1, @"tracks": @[original, original, translatedTrack(fixture(2))]}, single);
        NSDictionary *duplicates = [store importURL:single error:nil];
        check([duplicates[@"errors"] integerValue] == 2 && [duplicates[@"translated"] integerValue] == 1,
              @"reject both duplicates and keep valid independent import");
        [@"{broken" writeToURL:single atomically:YES encoding:NSUTF8StringEncoding error:nil];
        check(![store importURL:single error:nil], @"malformed JSON rejected");
        NSMutableData *badZIP = [[NSData dataWithContentsOfURL:backup] mutableCopy];
        badZIP.length -= 1;
        check(![[SGLibraryZIP alloc] initWithData:badZIP error:nil], @"truncated ZIP rejected");
        SGLibraryStore *restored = [[SGLibraryStore alloc] initWithDirectory:temporary(root, @"restore")];
        check([[restored importURL:backup error:nil][@"imported"] integerValue] == 2100, @"ZIP round trip");
        check([restored remove:trackID(5) error:nil], @"delete local record");
        restored = [[SGLibraryStore alloc] initWithDirectory:temporary(root, @"restore")];
        check(restored.summaries.count == 2099 && ![restored track:trackID(5) error:nil], @"local delete persisted");
        check([[restored importURL:backup error:nil][@"errors"] integerValue] == 0 && restored.summaries.count == 2100,
              @"retry is idempotent after interruption and restores deleted copy");
        NSString *next;
        NSDictionary *page = @{@"pages": @[@{@"tracks": @[@{@"uri": original[@"uri"], @"metadata": @{@"name": @"Tên bài"}},
            @{@"uri": @"spotify:local:skip"}], @"next_page_url": @"hm://collection/v1/page2"}]};
        check(SGLibraryCollectionPage(page, &next, nil).count == 1 &&
              [SGLibrarySpotifyPageURL(next).host isEqual:@"spclient.wg.spotify.com"] &&
              !SGLibrarySpotifyPageURL(@"https://example.org/collection/redirect"), @"pagination does not send headers off host");
        NSDictionary *savedTracks = @{@"items": @[@{@"track": @{@"uri": original[@"uri"], @"name": @"Tên bài",
            @"artists": @[@{@"name": @"Nghệ sĩ"}]}}], @"next": @"https://api.spotify.com/v1/me/tracks?offset=50&limit=50"};
        NSArray *liked = SGLibraryCollectionPage(savedTracks, &next, nil);
        check(liked.count == 1 && [liked[0][@"title"] isEqual:@"Tên bài"] &&
            [liked[0][@"artists"] isEqual:@[@"Nghệ sĩ"]] && SGLibrarySpotifyPageURL(next) &&
            !SGLibrarySpotifyPageURL(@"https://api.spotify.com/v1/me"), @"Spotify Web API pagination");
        NSDictionary *source = @{@"lyrics": @{@"syncType": @"LINE_SYNCED", @"providerDisplayName": @"Fixture",
            @"language": @"en", @"lines": @[
                @{@"startTimeMs": @"1500", @"endTimeMs": @"2000", @"words": @"A quiet line ((Hey))"},
                @{@"startTimeMs": @"3500", @"endTimeMs": @"0", @"words": @"A quiet line ((Hey))"},
            ]}};
        NSDictionary *scanned = SGLibrarySpotifyOriginal(fixture(13), source);
        check([scanned[@"status"] isEqual:@"original"] && [scanned[@"language"] isEqual:@"en"] &&
              [scanned[@"lines"][0][@"text"] isEqual:@"A quiet line ((Hey))"] &&
              [scanned[@"lines"][0][@"startMs"] isEqual:@1500] && [scanned[@"lines"][1][@"endMs"] isEqual:NSNull.null],
              @"lyrics scan fills a previously metadata-only track with original lyrics");
        check([store save:scanned error:nil] && [store exportIDs:@[trackID(13)] toURL:backup error:nil],
              @"newly scanned lyrics export straight from Liked Songs");
        SGLibraryZIP *scannedZip = [[SGLibraryZIP alloc] initWithData:[NSData dataWithContentsOfURL:backup] error:nil];
        NSString *trackFile = [NSString stringWithFormat:@"tracks/%@.json", trackID(13)];
        NSDictionary *scannedFile = SGLibraryReadJSON([scannedZip dataForName:trackFile error:nil], nil);
        writeJSON(translatedTrack(scannedFile), single);
        check([[store importURL:single error:nil][@"translated"] intValue] == 1, @"import a translation of the newly scanned lyrics");
        NSArray<SGKaraokeLine *> *scanLines = SGLibraryKaraokeLines(scanned);
        NSArray<SGKaraokeLine *> *importedLines = SGLibraryKaraokeLines([store track:trackID(13) error:nil]);
        NSArray<SGKaraokeLine *> *overlay = SGLibraryOverlayTranslations(scanLines, importedLines);
        check(overlay.count == 2 && overlay[0].words == scanLines[0].words &&
              [overlay[0].translation isEqual:@"Dòng thứ nhất"] && [overlay[1].translation isEqual:@"Dòng điệp khúc"],
              @"inline player displays the imported translations on separate original lines");
        check(!SGLibrarySpotifyOriginal(fixture(13), @{@"lyrics": @{@"lines": @[]}}), @"empty network lyrics stay missing");
        [NSFileManager.defaultManager removeItemAtURL:root error:nil];
        puts("PASS: Spotify original lyrics fixture and inline translations; 2100 tracks, JSON/ZIP round trip, playback line timing, missing, duplicates, invalid data, deletion and resume");
    }
    return 0;
}
