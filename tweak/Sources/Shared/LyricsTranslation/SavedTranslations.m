// Persistent JSON per song/language under Application Support/SYNA/Translations.
// Existing cache files are copied once; no deletion or automatic limit is applied.
#import "Core/SGCore.h"
#import "Core/SGSYNA.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Lyrics/Lyrics.h"
#import "LyricsTranslation.h"

// Translations remain until explicitly deleted. No automatic eviction cap.

static NSURL *folder(void) {
    // Migrate every legacy file once, without deleting its original or replacing newer saved copies.
    static NSURL *savedDirectory;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSURL *support = [fm URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject;
        savedDirectory = [[support URLByAppendingPathComponent:@"SYNA" isDirectory:YES] URLByAppendingPathComponent:@"Translations" isDirectory:YES];
        [fm createDirectoryAtURL:savedDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        NSURL *caches = [fm URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
        NSURL *old = [[caches URLByAppendingPathComponent:@"Vitrine" isDirectory:YES] URLByAppendingPathComponent:@"Translations" isDirectory:YES];
        NSArray<NSURL *> *legacy = [fm contentsOfDirectoryAtURL:old includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
        for (NSURL *file in legacy) {
            if (![file.pathExtension.lowercaseString isEqualToString:@"json"]) continue;
            NSURL *destination = [savedDirectory URLByAppendingPathComponent:file.lastPathComponent];
            if (![fm fileExistsAtPath:destination.path]) [fm copyItemAtURL:file toURL:destination error:nil];
        }
    });
    return savedDirectory;
}

static NSURL *fileFor(NSString *track, NSString *language) {
    NSCharacterSet *unsafe = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"].invertedSet;
    NSString *tag = [[language componentsSeparatedByCharactersInSet:unsafe] componentsJoinedByString:@"_"];
    return [folder() URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@.json", track, tag]];
}

static NSArray<NSURL *> *files(void) {
    return [NSFileManager.defaultManager contentsOfDirectoryAtURL:folder() includingPropertiesForKeys:@[NSURLContentModificationDateKey, NSURLFileSizeKey]
                                                          options:NSDirectoryEnumerationSkipsHiddenFiles error:nil] ?: @[];
}

NSDictionary<NSString *, NSString *> *SGSavedTranslationLines(id json, SGTranslationSource **source) {
    if (![json isKindOfClass:NSDictionary.class]) return nil;
    id lines = json[@"lines"];
    if (![lines isKindOfClass:NSDictionary.class]) {
        *source = [SGTranslationSource by:nil model:nil made:nil];   // saved before sources were kept
        return json;
    }
    id by = json[@"by"], model = json[@"model"], made = json[@"made"];
    *source = [SGTranslationSource by:[by isKindOfClass:NSString.class] ? by : nil model:[model isKindOfClass:NSString.class] ? model : nil
                                 made:[made isKindOfClass:NSNumber.class] ? [NSDate dateWithTimeIntervalSince1970:[made doubleValue]] : nil];
    return lines;
}

SGTranslationSource *SGLyricsSyncSavedTranslation(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines) {
    if (!track.length || !language.length || !lines.count) return nil;
    NSData *data = [NSData dataWithContentsOfURL:fileFor(track, language)];
    SGTranslationSource *source = nil;
    NSDictionary *saved = SGSavedTranslationLines(data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil, &source);
    BOOL shown = NO;
    for (SGKaraokeLine *line in lines) {
        id translation = saved[SGKaraokeLineText(line) ?: @""];
        BOOL has = [translation isKindOfClass:NSString.class] && [translation length];
        if (line.translationMade && !has) {
            line.translation = nil;
            line.translationMade = NO;
        } else if (!line.translation.length && has) {
            line.translation = translation;
            line.translationMade = YES;
        }
        shown |= line.translationMade;
    }
    // A file none of these lines matched (lyrics from another source) made nothing that shows.
    return shown ? source : nil;
}

// One at a time, in the order asked: a song is saved after every batch, and an older write must not land last.
static dispatch_queue_t writes(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("syna.translations", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

SGTranslationSource *SGLyricsSaveTranslation(NSString *track, NSString *language, NSArray<SGKaraokeLine *> *lines, SGTranslationSource *source) {
    if (!track.length || !language.length) return nil;
    NSMutableDictionary<NSString *, NSString *> *saved = [NSMutableDictionary dictionary];
    for (SGKaraokeLine *line in lines) {
        NSString *text = SGKaraokeLineText(line);
        if (text.length && line.translation.length) saved[text] = line.translation;
    }
    if (!saved.count) return nil;
    // The source of the last translation asked: a song finished by a second translator names the second.
    NSDate *now = [NSDate date];
    NSMutableDictionary *file = [@{@"lines": saved, @"made": @(floor(now.timeIntervalSince1970))} mutableCopy];
    if (source.by) file[@"by"] = source.by;
    if (source.model) file[@"model"] = source.model;
    NSData *data = [NSJSONSerialization dataWithJSONObject:file options:0 error:nil];
    dispatch_async(writes(), ^{
        [NSFileManager.defaultManager createDirectoryAtURL:folder() withIntermediateDirectories:YES attributes:nil error:nil];
        [data writeToURL:fileFor(track, language) atomically:YES];
        // No implicit pruning: files are removed only by user action.
    });
    return [SGTranslationSource by:source.by model:source.model made:now];
}

BOOL SGLyricsHasSavedTranslation(NSString *track, NSString *language) {
    if (!track.length || !language.length) return NO;
    return [NSFileManager.defaultManager fileExistsAtPath:fileFor(track, language).path];
}

// After any write still queued, so it cannot bring a file back.
static void deleteQueued(NSURL *url, NSString *what) {
    dispatch_async(writes(), ^{
        [NSFileManager.defaultManager removeItemAtURL:url error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            SGLog(@"translation: %@ deleted", what);
            [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationsDidChangeNotification object:nil];
        });
    });
}

void SGLyricsDeleteSavedTranslation(NSString *track, NSString *language) {
    if (!track.length || !language.length) return;
    SGLyricsForgetAITranslation(track, language);
    deleteQueued(fileFor(track, language), [NSString stringWithFormat:@"%@ in %@", track, language]);
}

static NSString *summary(void) {
    NSArray<NSURL *> *all = files();
    if (!all.count) return SGSYNALocalize(@"None");
    long long bytes = 0;
    for (NSURL *file in all) {
        NSNumber *size;
        [file getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
        bytes += size.longLongValue;
    }
    return [NSString stringWithFormat:@"%lu · %@", (unsigned long)all.count,
            [NSByteCountFormatter stringFromByteCount:bytes countStyle:NSByteCountFormatterCountStyleFile]];
}

SGModRow *SGSavedTranslationsRow(void) {
    return SGStatActionRow(@"Saved translations", @"Songs translated on this iPhone or by an AI translator come back translated",
                           ^NSString *{ return summary(); }, ^{
        if (!files().count) return;
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGSYNALocalize(@"Delete saved translations?")
            message:SGSYNAVietnamese() ? @"Mọi bản dịch đã lưu sẽ bị xóa; bạn cần dịch lại khi sử dụng."
                                     : @"Saved translations will be deleted; you will need to translate songs again." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:SGSYNALocalize(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            SGLyricsForgetAITranslation(nil, nil);
            deleteQueued(folder(), @"saved translations");
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:SGSYNALocalize(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    });
}
