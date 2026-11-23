#import "SGLyricsLibrary.h"
#import "SGLibraryOriginal.h"
#import "Shared/Lyrics/Lyrics.h"

NSString *const SGLibraryShowTranslationKey = @"spotifyglass.synaLibrary.showTranslation";

BOOL SGLibraryShowsTranslation(void) {
    NSNumber *value = [NSUserDefaults.standardUserDefaults objectForKey:SGLibraryShowTranslationKey];
    return value ? value.boolValue : YES;
}

NSArray<SGKaraokeLine *> *SGLibraryKaraokeLines(NSDictionary *record) {
    NSMutableArray<SGKaraokeLine *> *result = [NSMutableArray array];
    for (NSDictionary *row in record[@"lines"]) {
        NSString *text = row[@"text"];
        if (![text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length ||
            [text isEqual:@"♪"]) continue;
        BOOL timed = row[@"startMs"] != NSNull.null;
        NSInteger start = timed ? [row[@"startMs"] integerValue] : 0;
        NSInteger end = row[@"endMs"] != NSNull.null ? [row[@"endMs"] integerValue] : start + 1800;
        SGKaraokeLine *line = [SGKaraokeLine new];
        SGKaraokeWord *word = [SGKaraokeWord new];
        word.text = text;
        word.start = start;
        word.end = timed ? end : 0;
        line.words = @[word];
        line.start = word.start;
        line.end = word.end;
        line.timing = timed ? SGKaraokeTimingLine : SGKaraokeTimingNone;
        line.translation = row[@"translation"];
        [result addObject:line];
    }
    return result.count ? SGKaraokeInTimeOrder(result) : nil;
}


NSArray<SGKaraokeLine *> *SGLibraryOverlayTranslations(NSArray<SGKaraokeLine *> *original, NSArray<SGKaraokeLine *> *imported) {
    if (!original.count || original.count != imported.count) return imported;
    NSMutableArray<SGKaraokeLine *> *merged = [NSMutableArray arrayWithCapacity:original.count];
    for (NSUInteger i = 0; i < original.count; i++) {
        SGKaraokeLine *base = original[i], *library = imported[i];
        if (base.start != library.start || (base.timing == SGKaraokeTimingNone) != (library.timing == SGKaraokeTimingNone) ||
            ![SGLibraryLineText(base) isEqual:SGKaraokeLineText(library)]) return imported;
        SGKaraokeLine *line = [base copy];
        line.translation = library.translation;
        line.translationMade = NO;
        [merged addObject:line];
    }
    return merged;
}
