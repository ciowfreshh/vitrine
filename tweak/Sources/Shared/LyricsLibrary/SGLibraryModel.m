#import "SGLibraryModel.h"
#import <CoreFoundation/CoreFoundation.h>

NSString *const SGLibraryFormat = @"spotify-syna-lyrics";
NSString *const SGLibraryErrorDomain = @"SpotifySYNA.LyricsLibrary";

void SGLibraryError(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:SGLibraryErrorDomain code:1
                                      userInfo:@{NSLocalizedDescriptionKey: message}];
}

static BOOL text(id value, NSUInteger limit) {
    return [value isKindOfClass:NSString.class] && [value length] <= limit;
}

static BOOL integer(id value, NSInteger maximum) {
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return NO;
    double number = [value doubleValue];
    return number >= 0 && number <= maximum && (double)[value integerValue] == number;
}

BOOL SGLibraryTrackID(id value) {
    if (!text(value, 22) || [value length] != 22) return NO;
    static NSCharacterSet *invalid;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        invalid = [NSCharacterSet characterSetWithCharactersInString:@"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"].invertedSet;
    });
    return [value rangeOfCharacterFromSet:invalid].location == NSNotFound;
}

static NSString *nullableText(id value) {
    return [value isKindOfClass:NSString.class] ? value : nil;
}

NSDictionary *SGLibraryTrack(id value, NSError **error) {
    if (![value isKindOfClass:NSDictionary.class]) {
        SGLibraryError(error, @"Dữ liệu bài hát phải là một đối tượng JSON.");
        return nil;
    }
    NSString *trackID = value[@"trackId"];
    NSString *uri = value[@"uri"];
    NSString *title = value[@"title"];
    NSArray *artists = value[@"artists"];
    NSString *source = value[@"source"];
    NSString *language = value[@"language"];
    NSString *status = value[@"status"];
    NSArray *lines = value[@"lines"];
    if (!SGLibraryTrackID(trackID) || ![uri isEqual:[@"spotify:track:" stringByAppendingString:trackID]] ||
        !text(title, 1000) || ![artists isKindOfClass:NSArray.class] || artists.count > 100 ||
        !text(source, 256) || !text(language, 64) ||
        ![@[@"original", @"translated", @"missing", @"error"] containsObject:status ?: NSNull.null] ||
        ![lines isKindOfClass:NSArray.class] || lines.count > 4000) {
        SGLibraryError(error, @"Thông tin bài hát hoặc định dạng lời bài hát không hợp lệ.");
        return nil;
    }
    for (id artist in artists) {
        if (!text(artist, 1000)) {
            SGLibraryError(error, @"Tên nghệ sĩ không hợp lệ.");
            return nil;
        }
    }
    if ((lines.count && !source.length) || (!lines.count && [@[@"original", @"translated"] containsObject:status])) {
        SGLibraryError(error, @"Trạng thái hoặc nguồn lời không khớp với dữ liệu.");
        return nil;
    }

    NSMutableArray *checked = [NSMutableArray arrayWithCapacity:lines.count];
    BOOL hasTranslation = NO;
    for (id item in lines) {
        NSUInteger index = checked.count;
        NSString *lineID = [NSString stringWithFormat:@"%lu", (unsigned long)index];
        if (![item isKindOfClass:NSDictionary.class] || ![item[@"id"] isEqual:lineID] ||
            !integer(item[@"index"], 3999) || [item[@"index"] unsignedIntegerValue] != index ||
            !text(item[@"text"], 16000) ||
            (item[@"translation"] && item[@"translation"] != NSNull.null && !text(item[@"translation"], 16000))) {
            SGLibraryError(error, [NSString stringWithFormat:@"Dòng %lu không hợp lệ hoặc sai thứ tự.", (unsigned long)index + 1]);
            return nil;
        }
        id start = item[@"startMs"], end = item[@"endMs"];
        BOOL untimed = start == NSNull.null && end == NSNull.null;
        if (!untimed && (!integer(start, INT32_MAX) ||
            (end != NSNull.null && (!integer(end, INT32_MAX) || [end integerValue] < [start integerValue])))) {
            SGLibraryError(error, [NSString stringWithFormat:@"Mốc thời gian dòng %lu không hợp lệ.", (unsigned long)index + 1]);
            return nil;
        }
        NSMutableDictionary *line = [@{@"id": lineID, @"index": @(index), @"text": item[@"text"],
                                        @"startMs": start, @"endMs": end} mutableCopy];
        NSString *translation = nullableText(item[@"translation"]);
        if ([translation stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) {
            line[@"translation"] = translation;
            hasTranslation = YES;
        }
        [checked addObject:[line copy]];
    }
    // Construct the record from the schema. Unknown input members can never reach disk or an export.
    return @{@"trackId": trackID, @"uri": uri, @"title": title, @"artists": [artists copy],
             @"source": source, @"language": language, @"lines": [checked copy],
             @"status": lines.count ? (hasTranslation ? @"translated" : @"original") :
                           ([status isEqual:@"error"] ? @"error" : @"missing")};
}

NSDictionary *SGLibraryMerge(NSDictionary *original, NSDictionary *incoming, NSError **error) {
    NSArray *savedLines = original[@"lines"];
    NSArray *newLines = incoming[@"lines"];
    if (!savedLines.count) return incoming;
    if (!newLines.count && [incoming[@"status"] isEqual:@"missing"]) return original;
    if (![original[@"trackId"] isEqual:incoming[@"trackId"]] || ![original[@"source"] isEqual:incoming[@"source"]] ||
        ![original[@"language"] isEqual:incoming[@"language"]] || savedLines.count != newLines.count) {
        SGLibraryError(error, @"Nguồn, ngôn ngữ hoặc số dòng đã thay đổi.");
        return nil;
    }
    NSMutableArray *merged = [NSMutableArray arrayWithCapacity:savedLines.count];
    for (NSUInteger i = 0; i < savedLines.count; i++) {
        NSDictionary *oldLine = savedLines[i], *newLine = newLines[i];
        for (NSString *key in @[@"id", @"text", @"startMs", @"endMs"]) {
            if (![oldLine[key] isEqual:newLine[key]]) {
                SGLibraryError(error, [NSString stringWithFormat:@"Nội dung gốc hoặc mốc thời gian dòng %lu đã thay đổi.",
                                       (unsigned long)i + 1]);
                return nil;
            }
        }
        NSMutableDictionary *line = [oldLine mutableCopy];
        if (newLine[@"translation"]) line[@"translation"] = newLine[@"translation"];
        [merged addObject:line];
    }
    NSMutableDictionary *result = [original mutableCopy];
    result[@"lines"] = merged;
    return SGLibraryTrack(result, error);
}

NSDictionary *SGLibraryTrackSummary(NSDictionary *track) {
    return [track dictionaryWithValuesForKeys:@[@"trackId", @"uri", @"title", @"artists", @"source", @"language", @"status"]];
}

NSData *SGLibraryJSON(id object, NSError **error) {
    return [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes error:error];
}

id SGLibraryReadJSON(NSData *data, NSError **error) {
    if (!data.length) {
        SGLibraryError(error, @"Tệp JSON trống.");
        return nil;
    }
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
}

NSArray *SGLibraryDocument(id object, NSError **error) {
    if ([object isKindOfClass:NSDictionary.class]) {
        if (object[@"trackId"]) return @[object];
        if ([object[@"format"] isEqual:SGLibraryFormat] && integer(object[@"version"], 1) &&
            [object[@"version"] integerValue] == 1 && [object[@"tracks"] isKindOfClass:NSArray.class] &&
            [object[@"tracks"] count] <= 40000) return object[@"tracks"];
    }
    SGLibraryError(error, @"JSON phải chứa một bài hoặc danh sách bài theo định dạng Spotify SYNA phiên bản 1.");
    return nil;
}
