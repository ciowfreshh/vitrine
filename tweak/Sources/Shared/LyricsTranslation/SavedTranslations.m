// Durable translations. SQLite commits one complete song at a time in Application Support.
#import "Core/SGCore.h"
#import "Core/TranslationStore/SGTranslationStore.h"
#import "Core/BatchQueue/SGTranslationAlignment.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Lyrics/Lyrics.h"
#import "LyricsTranslation.h"
#import "TranslationLibrary.h"

SGTranslationStore *SGSavedTranslationStore(void) {
    static SGTranslationStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSURL *support = [fm URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        NSURL *cache = [fm URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
        store = [[SGTranslationStore alloc] initWithURL:[support URLByAppendingPathComponent:@"Vitrine/Translations/translations.sqlite3"]
                                      legacyDirectory:[cache URLByAppendingPathComponent:@"Vitrine/Translations"]];
    });
    return store;
}

static void notify(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationsDidChangeNotification object:nil]; });
}

static void showFailure(NSError *error) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGLocalized(@"Translation storage error") message:SGLocalizedError(error) preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:SGLocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    });
}

NSDictionary<NSString *, NSString *> *SGSavedTranslationLines(id json, SGTranslationSource **source) {
    if (![json isKindOfClass:NSDictionary.class]) return nil;
    id lines = json[@"lines"];
    if (![lines isKindOfClass:NSDictionary.class]) {
        if (source) *source = [SGTranslationSource by:nil model:nil made:nil];   // saved before sources were kept
        return json;
    }
    id by = json[@"by"], model = json[@"model"], made = json[@"made"];
    if (source) *source = [SGTranslationSource by:[by isKindOfClass:NSString.class] ? by : nil model:[model isKindOfClass:NSString.class] ? model : nil
                                 made:[made isKindOfClass:NSNumber.class] ? [NSDate dateWithTimeIntervalSince1970:[made doubleValue]] : nil];
    return lines;
}

SGTranslationSource *SGLyricsSyncSavedTranslation(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines) {
    if (!track.length || !language.length || !lines.count) return nil;
    NSError *error = nil;
    NSDictionary *record = [SGSavedTranslationStore() compatibleRecordForTrack:track language:language error:&error];
    if (error) { SGLog(@"translation: durable read failed"); return nil; }
    SGTranslationSource *source = nil;
    NSDictionary *saved = SGSavedTranslationLines(record, &source);
    NSMutableArray *originals = [NSMutableArray arrayWithCapacity:lines.count];
    for (SGKaraokeLine *line in lines) [originals addObject:SGKaraokeLineText(line) ?: @""];
    NSArray *resolved = SGTranslationResolveLines(saved, originals);
    NSIndexSet *untranslated = SGTranslationUnchangedForeignLines(originals, resolved, language);
    BOOL shown = NO;
    for (NSUInteger i = 0; i < lines.count; ++i) {
        SGKaraokeLine *line = lines[i];
        id translation = resolved[i];
        BOOL has = [translation isKindOfClass:NSString.class] && [translation length] && ![untranslated containsIndex:i];
        if (line.translationMade && !has) { line.translation = nil; line.translationMade = NO; }
        // A community/native translation must not hide the user's saved AI translation.
        else if (has) { line.translation = translation; line.translationMade = YES; }
        shown |= line.translationMade;
    }
    return shown ? source : nil;
}

SGTranslationSource *SGLyricsSaveTranslation(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines, SGTranslationSource *source) {
    if (!track.length || !language.length) return nil;
    NSMutableDictionary *saved = [NSMutableDictionary dictionary];
    NSMutableArray *originals = [NSMutableArray arrayWithCapacity:lines.count];
    for (SGKaraokeLine *line in lines) {
        NSString *text = SGKaraokeLineText(line);
        [originals addObject:text ?: @""];
        if (text.length && line.translation.length) saved[text] = line.translation;
    }
    if (!saved.count) return nil;
    NSError *error = nil;
    NSDictionary *previous = [SGSavedTranslationStore() compatibleRecordForTrack:track language:language error:&error];
    if (error) { showFailure(error); return nil; }
    // Partial/on-device progress and a new lyrics source must never erase other saved lines.
    saved = [SGTranslationMergeLines(SGSavedTranslationLines(previous, NULL), saved) mutableCopy];
    NSDate *now = NSDate.date;
    // Keep the original on-disk identity when supplementing a regional alias. Reading an old file
    // never rewrites or deletes it; an explicit save keeps its data under its existing language tag.
    NSString *storageLanguage = previous[@"language"] ?: language;
    NSMutableDictionary *record = [@{@"type":@"vitrine.translation", @"schemaVersion":@1, @"track":track, @"language":storageLanguage,
                                    @"lines":saved, @"originals":originals, @"made":@(floor(now.timeIntervalSince1970))} mutableCopy];
    if (source.by) record[@"by"] = source.by;
    if (source.model) record[@"model"] = source.model;
    NSString *name = SGLyricsSongName(track);
    if (name.length) record[@"title"] = name;
    // Synchronous durability: callers can report completion only after the commit survives termination.
    if (![SGSavedTranslationStore() putRecord:record replace:YES didWrite:NULL error:&error]) { showFailure(error); return nil; }
    return [SGTranslationSource by:source.by model:source.model made:now];
}

BOOL SGLyricsHasSavedTranslation(NSString *track, NSString *language) {
    return track.length && language.length && [SGSavedTranslationStore() compatibleRecordForTrack:track language:language error:nil] != nil;
}

NSUInteger SGLyricsSavedTranslationMissing(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines) {
    NSDictionary *record = [SGSavedTranslationStore() compatibleRecordForTrack:track language:language error:nil];
    NSMutableArray *originals = [NSMutableArray arrayWithCapacity:lines.count];
    for (SGKaraokeLine *line in lines) [originals addObject:SGKaraokeLineText(line) ?: @""];
    NSArray *resolved = SGTranslationResolveLines(SGSavedTranslationLines(record, NULL), originals);
    NSMutableIndexSet *missing = [SGTranslationMissingLines(originals, resolved) mutableCopy];
    [missing addIndexes:SGTranslationUnchangedForeignLines(originals, resolved, language)];
    return missing.count;
}

void SGLyricsDeleteSavedTranslation(NSString *track, NSString *language) {
    if (!track.length || !language.length) return;
    NSError *error = nil;
    NSArray *records = [SGSavedTranslationStore() recordsForTrack:track compatibleLanguage:language error:&error];
    if (error) { showFailure(error); return; }
    for (NSDictionary *record in records) {
        if (![SGSavedTranslationStore() removeTrack:track language:record[@"language"] error:&error]) { showFailure(error); return; }
        SGLyricsForgetAITranslation(track, record[@"language"]);
    }
    SGLyricsForgetAITranslation(track, language); notify();
}

SGModRow *SGSavedTranslationsRow(void) {
    SGModRow *row = SGPageRow(SGLocalized(@"Saved translations"), ^UIViewController *{ return SGSavedTranslationsPage(); });
    row.value = ^NSString *{
        NSError *error = nil;
        NSArray *all = [SGSavedTranslationStore() summaries:&error];
        return error ? SGLocalized(@"Unavailable") : [NSString stringWithFormat:SGLocalized(@"%lu songs saved"), (unsigned long)all.count];
    };
    return row;
}
