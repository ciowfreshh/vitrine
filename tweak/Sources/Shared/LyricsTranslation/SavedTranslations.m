// Durable translations. SQLite commits one complete song at a time in Application Support.
#import "Core/SGCore.h"
#import "Core/TranslationStore/SGTranslationStore.h"
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
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Translation storage error" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
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
    NSDictionary *record = [SGSavedTranslationStore() recordForTrack:track language:language error:&error];
    if (error) { SGLog(@"translation: durable read failed"); return nil; }
    SGTranslationSource *source = nil;
    NSDictionary *saved = SGSavedTranslationLines(record, &source);
    BOOL shown = NO;
    for (SGKaraokeLine *line in lines) {
        id translation = saved[SGKaraokeLineText(line) ?: @""];
        BOOL has = [translation isKindOfClass:NSString.class] && [translation length];
        if (line.translationMade && !has) { line.translation = nil; line.translationMade = NO; }
        else if (!line.translation.length && has) { line.translation = translation; line.translationMade = YES; }
        shown |= line.translationMade;
    }
    return shown ? source : nil;
}

SGTranslationSource *SGLyricsSaveTranslation(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines, SGTranslationSource *source) {
    if (!track.length || !language.length) return nil;
    NSMutableDictionary *saved = [NSMutableDictionary dictionary];
    for (SGKaraokeLine *line in lines) {
        NSString *text = SGKaraokeLineText(line);
        if (text.length && line.translation.length) saved[text] = line.translation;
    }
    if (!saved.count) return nil;
    NSDate *now = NSDate.date;
    NSMutableDictionary *record = [@{@"type":@"vitrine.translation", @"schemaVersion":@1, @"track":track, @"language":language,
                                    @"lines":saved, @"made":@(floor(now.timeIntervalSince1970))} mutableCopy];
    if (source.by) record[@"by"] = source.by;
    if (source.model) record[@"model"] = source.model;
    NSString *name = SGLyricsSongName(track);
    if (name.length) record[@"title"] = name;
    NSError *error = nil;
    // Synchronous durability: callers can report completion only after the commit survives termination.
    if (![SGSavedTranslationStore() putRecord:record replace:YES didWrite:NULL error:&error]) { showFailure(error); return nil; }
    return [SGTranslationSource by:source.by model:source.model made:now];
}

BOOL SGLyricsHasSavedTranslation(NSString *track, NSString *language) {
    return track.length && language.length && [SGSavedTranslationStore() recordForTrack:track language:language error:nil] != nil;
}

void SGLyricsDeleteSavedTranslation(NSString *track, NSString *language) {
    if (!track.length || !language.length) return;
    NSError *error = nil;
    if (![SGSavedTranslationStore() removeTrack:track language:language error:&error]) { showFailure(error); return; }
    SGLyricsForgetAITranslation(track, language); notify();
}

SGModRow *SGSavedTranslationsRow(void) {
    SGModRow *row = SGPageRow(@"Saved translations", ^UIViewController *{ return SGSavedTranslationsPage(); });
    row.value = ^NSString *{
        NSError *error = nil;
        NSArray *all = [SGSavedTranslationStore() summaries:&error];
        return error ? @"Unavailable" : [NSString stringWithFormat:@"%lu songs saved", (unsigned long)all.count];
    };
    return row;
}
