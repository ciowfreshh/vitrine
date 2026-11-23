// Translations kept on disk, whichever way they were made: one small JSON file a song and language in
// Application Support/Vitrine/Translations, with a fallback for translations made by an older build.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Lyrics/Lyrics.h"
#import "LyricsTranslation.h"

static NSURL *folder(NSSearchPathDirectory directory) {
    NSURL *root = [NSFileManager.defaultManager URLsForDirectory:directory inDomains:NSUserDomainMask].firstObject;
    return [root URLByAppendingPathComponent:@"Vitrine/Translations" isDirectory:YES];
}

static NSURL *fileFor(NSString *track, NSString *language, NSSearchPathDirectory directory) {
    NSCharacterSet *unsafe = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"].invertedSet;
    NSString *tag = [[language componentsSeparatedByCharactersInSet:unsafe] componentsJoinedByString:@"_"];
    return [folder(directory) URLByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@.json", track, tag]];
}

static NSArray<NSURL *> *files(void) {
    return [NSFileManager.defaultManager contentsOfDirectoryAtURL:folder(NSApplicationSupportDirectory) includingPropertiesForKeys:@[NSURLContentModificationDateKey, NSURLFileSizeKey]
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
    NSData *data = [NSData dataWithContentsOfURL:fileFor(track, language, NSApplicationSupportDirectory)];
    if (!data) data = [NSData dataWithContentsOfURL:fileFor(track, language, NSCachesDirectory)];
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
    dispatch_once(&once, ^{ queue = dispatch_queue_create("vitrine.translations", DISPATCH_QUEUE_SERIAL); });
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
        [NSFileManager.defaultManager createDirectoryAtURL:folder(NSApplicationSupportDirectory) withIntermediateDirectories:YES attributes:nil error:nil];
        [data writeToURL:fileFor(track, language, NSApplicationSupportDirectory) atomically:YES];
    });
    return [SGTranslationSource by:source.by model:source.model made:now];
}

BOOL SGLyricsHasSavedTranslation(NSString *track, NSString *language) {
    if (!track.length || !language.length) return NO;
    return [NSFileManager.defaultManager fileExistsAtPath:fileFor(track, language, NSApplicationSupportDirectory).path] ||
           [NSFileManager.defaultManager fileExistsAtPath:fileFor(track, language, NSCachesDirectory).path];
}

// After any write still queued, so it cannot bring a file back.
static void deleteQueued(NSArray<NSURL *> *urls, NSString *what) {
    dispatch_async(writes(), ^{
        for (NSURL *url in urls) [NSFileManager.defaultManager removeItemAtURL:url error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            SGLog(@"translation: %@ deleted", what);
            [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationsDidChangeNotification object:nil];
        });
    });
}

void SGLyricsDeleteSavedTranslation(NSString *track, NSString *language) {
    if (!track.length || !language.length) return;
    SGLyricsForgetAITranslation(track, language);
    deleteQueued(@[fileFor(track, language, NSApplicationSupportDirectory), fileFor(track, language, NSCachesDirectory)], [NSString stringWithFormat:@"%@ bằng %@", track, language]);
}

static NSString *summary(void) {
    NSArray<NSURL *> *all = files();
    if (!all.count) return @"None";
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
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Xóa các bản dịch đã lưu?"
            message:@"Các bài này sẽ được dịch lại khi bạn yêu cầu." preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Xóa" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            SGLyricsForgetAITranslation(nil, nil);
            deleteQueued(@[folder(NSApplicationSupportDirectory), folder(NSCachesDirectory)], @"saved translations");
        }]];
        [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    });
}
