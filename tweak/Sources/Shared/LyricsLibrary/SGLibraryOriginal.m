#import "SGLibraryOriginal.h"
#import "SGLibraryModel.h"
#import "Shared/Lyrics/Lyrics.h"

static NSDictionary *row(NSUInteger index, NSString *text, id start, id end) {
    return @{@"id": @(index).stringValue, @"index": @(index), @"text": text,
             @"startMs": start ?: NSNull.null, @"endMs": end ?: NSNull.null};
}

static NSDictionary *withOriginal(NSDictionary *track, NSArray<NSDictionary *> *lines, id provider, id language) {
    if (!lines.count) return nil;
    NSMutableDictionary *record = [track mutableCopy];
    record[@"source"] = [provider isKindOfClass:NSString.class] && [provider length] ? provider : @"Spotify";
    record[@"language"] = [language isKindOfClass:NSString.class] && [language length] ? language : @"und";
    record[@"lines"] = lines;
    record[@"status"] = @"original";
    return SGLibraryTrack(record, nil);
}

static NSNumber *milliseconds(id value) {
    if ([value isKindOfClass:NSNumber.class]) {
        double number = [value doubleValue];
        if (number < 0 || number > INT32_MAX || number != [value longLongValue]) return nil;
        return @([value longLongValue]);
    }
    if (![value isKindOfClass:NSString.class] || ![value length] || [value length] > 10 ||
        [value rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet].location != NSNotFound ||
        [value longLongValue] > INT32_MAX) return nil;
    return @([value longLongValue]);
}

static BOOL isLyric(id text) {
    if (![text isKindOfClass:NSString.class]) return NO;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return trimmed.length && [trimmed rangeOfCharacterFromSet:NSCharacterSet.alphanumericCharacterSet].location != NSNotFound;
}

NSDictionary *SGLibrarySpotifyOriginal(NSDictionary *track, id response) {
    id lyrics = [response isKindOfClass:NSDictionary.class] ? response[@"lyrics"] : nil;
    if (![lyrics isKindOfClass:NSDictionary.class] || ![lyrics[@"lines"] isKindOfClass:NSArray.class]) return nil;
    NSString *syncType = lyrics[@"syncType"];
    BOOL timed = [syncType isEqual:@"LINE_SYNCED"] || [syncType isEqual:@"SYLLABLE_SYNCED"];
    NSMutableArray *lines = [NSMutableArray array];
    BOOL hasLyrics = NO;
    for (id entry in lyrics[@"lines"]) {
        if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"words"] isKindOfClass:NSString.class]) return nil;
        NSString *text = entry[@"words"];
        NSNumber *start = timed ? milliseconds(entry[@"startTimeMs"]) : nil;
        if (timed && !start) return nil;
        NSNumber *end = timed ? milliseconds(entry[@"endTimeMs"]) : nil;
        if (!end || end.longLongValue <= start.longLongValue) end = nil;
        [lines addObject:row(lines.count, text, start, end)];
        hasLyrics |= isLyric(text);
    }
    return hasLyrics ? withOriginal(track, lines, lyrics[@"providerDisplayName"] ?: lyrics[@"provider"], lyrics[@"language"]) : nil;
}

NSString *SGLibraryLineText(SGKaraokeLine *line) {
    NSString *main = SGKaraokeLineText(line) ?: @"";
    NSString *backing = line.backing ? SGKaraokeLineText(line.backing) : nil;
    if (!backing.length) return main;
    if (![backing hasPrefix:@"("] || ![backing hasSuffix:@")"])
        backing = [NSString stringWithFormat:@"(%@)", backing];
    return main.length ? [NSString stringWithFormat:@"%@ %@", main, backing] : backing;
}

NSDictionary *SGLibraryOriginalFromLines(NSDictionary *track, NSArray<SGKaraokeLine *> *lyrics, NSString *source) {
    NSMutableArray *lines = [NSMutableArray arrayWithCapacity:lyrics.count];
    BOOL hasLyrics = NO;
    for (SGKaraokeLine *line in lyrics) {
        NSString *text = SGLibraryLineText(line);
        BOOL timed = line.timing != SGKaraokeTimingNone;
        [lines addObject:row(lines.count, text, timed ? @(line.start) : nil, timed ? @(line.end) : nil)];
        hasLyrics |= isLyric(text);
    }
    return hasLyrics ? withOriginal(track, lines, source, nil) : nil;
}
