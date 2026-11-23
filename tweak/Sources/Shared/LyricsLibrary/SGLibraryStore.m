#import "SGLibraryStore.h"
#import "SGLibraryModel.h"
#import "SGLibraryZIP.h"

NSNotificationName const SGLibraryDidChange = @"syna.lyricsLibrary.changed";

@implementation SGLibraryStore {
    NSURL *_directory;
    NSMutableDictionary<NSString *, NSDictionary *> *_index;
}

- (instancetype)initWithDirectory:(NSURL *)directory {
    if ((self = [super init])) _directory = [directory copy];
    return self;
}

- (NSURL *)urlFor:(NSString *)trackID {
    if (!SGLibraryTrackID(trackID)) return nil;
    return [_directory URLByAppendingPathComponent:[trackID stringByAppendingString:@".json"]];
}

- (NSDictionary *)track:(NSString *)trackID error:(NSError **)error {
    NSURL *url = [self urlFor:trackID];
    if (!url || ![NSFileManager.defaultManager fileExistsAtPath:url.path]) return nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error];
    id object = data ? SGLibraryReadJSON(data, error) : nil;
    NSDictionary *track = object ? SGLibraryTrack(object, error) : nil;
    if (track && ![track[@"trackId"] isEqual:trackID]) {
        SGLibraryError(error, @"Định danh bài hát trong bộ nhớ không khớp.");
        return nil;
    }
    return track;
}

- (NSArray<NSDictionary *> *)summaries {
    if (!_index) {
        _index = [NSMutableDictionary dictionary];
        NSArray<NSURL *> *files = [NSFileManager.defaultManager contentsOfDirectoryAtURL:_directory
            includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
        for (NSURL *url in files) @autoreleasepool {
            NSString *trackID = url.lastPathComponent.stringByDeletingPathExtension;
            if (![url.pathExtension isEqualToString:@"json"] || !SGLibraryTrackID(trackID)) continue;
            NSDictionary *track = [self track:trackID error:nil];
            if (track) _index[trackID] = SGLibraryTrackSummary(track);
        }
    }
    return [_index.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult result = [a[@"title"] localizedStandardCompare:b[@"title"]];
        return result == NSOrderedSame ? [a[@"trackId"] compare:b[@"trackId"]] : result;
    }];
}

- (BOOL)save:(NSDictionary *)value error:(NSError **)error {
    NSDictionary *track = SGLibraryTrack(value, error);
    if (!track) return NO;
    NSData *data = SGLibraryJSON(track, error);
    if (!data || data.length > 12 * 1024 * 1024) {
        if (data) SGLibraryError(error, @"Dữ liệu bài hát vượt giới hạn dung lượng.");
        return NO;
    }
    NSURL *url = [self urlFor:track[@"trackId"]];
    if (![NSFileManager.defaultManager createDirectoryAtURL:_directory withIntermediateDirectories:YES
                                                attributes:nil error:error] ||
        ![data writeToURL:url options:NSDataWritingAtomic error:error]) return NO;
    _index[track[@"trackId"]] = SGLibraryTrackSummary(track);
    return YES;
}

- (BOOL)remove:(NSString *)trackID error:(NSError **)error {
    NSURL *url = [self urlFor:trackID];
    if (!url) {
        SGLibraryError(error, @"Định danh bài hát không hợp lệ.");
        return NO;
    }
    if ([NSFileManager.defaultManager fileExistsAtPath:url.path] &&
        ![NSFileManager.defaultManager removeItemAtURL:url error:error]) return NO;
    [_index removeObjectForKey:trackID];
    return YES;
}

- (BOOL)exportIDs:(NSArray<NSString *> *)ids toURL:(NSURL *)url error:(NSError **)error {
    SGLibraryZIPWriter *zip = [SGLibraryZIPWriter new];
    NSMutableArray *manifest = [NSMutableArray arrayWithCapacity:ids.count];
    for (NSString *trackID in [NSOrderedSet orderedSetWithArray:ids]) @autoreleasepool {
        NSDictionary *track = [self track:trackID error:error];
        if (!track) {
            if (error && !*error) SGLibraryError(error, @"Thiếu bài hát trong bộ nhớ. Hãy làm mới danh sách.");
            return NO;
        }
        NSString *name = [NSString stringWithFormat:@"tracks/%@.json", trackID];
        if (![zip addData:SGLibraryJSON(track, error) name:name error:error]) return NO;
        NSMutableDictionary *summary = [SGLibraryTrackSummary(track) mutableCopy];
        summary[@"file"] = name;
        [manifest addObject:summary];
    }
    NSData *metadata = SGLibraryJSON(@{@"format": SGLibraryFormat, @"version": @1, @"tracks": manifest}, error);
    if (![zip addData:metadata name:@"manifest.json" error:error]) return NO;
    return [[zip finish] writeToURL:url options:NSDataWritingAtomic error:error];
}

- (NSDictionary *)importURL:(NSURL *)url error:(NSError **)error {
    NSNumber *size;
    if (![url getResourceValue:&size forKey:NSURLFileSizeKey error:error]) return nil;
    BOOL isZIP = [url.pathExtension.lowercaseString isEqualToString:@"zip"];
    if (size.unsignedLongLongValue > (isZIP ? 192u : 32u) * 1024u * 1024u) {
        SGLibraryError(error, @"Tệp nhập vượt giới hạn dung lượng.");
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error];
    if (!data) return nil;
    SGLibraryZIP *zip;
    NSArray *records;
    if (isZIP) {
        zip = [[SGLibraryZIP alloc] initWithData:data error:error];
        if (!zip) return nil;
        NSData *metadata = [zip dataForName:@"manifest.json" error:error];
        if (!metadata) return nil;
        records = SGLibraryDocument(SGLibraryReadJSON(metadata, error), error);
    } else {
        records = SGLibraryDocument(SGLibraryReadJSON(data, error), error);
    }
    if (!records) return nil;

    NSMutableDictionary<NSString *, NSNumber *> *occurrences = [NSMutableDictionary dictionary];
    NSMutableSet *expectedFiles = [NSMutableSet setWithObject:@"manifest.json"];
    for (id record in records) {
        NSString *trackID = [record isKindOfClass:NSDictionary.class] ? record[@"trackId"] : nil;
        if (!SGLibraryTrackID(trackID)) continue;
        occurrences[trackID] = @(occurrences[trackID].unsignedIntegerValue + 1);
        if (zip) [expectedFiles addObject:[NSString stringWithFormat:@"tracks/%@.json", trackID]];
    }
    if (zip && ![[NSSet setWithArray:zip.names] isSubsetOfSet:expectedFiles]) {
        SGLibraryError(error, @"ZIP chứa tệp bài hát nằm ngoài manifest.");
        return nil;
    }

    NSUInteger imported = 0, translated = 0, errors = 0;
    NSMutableArray *details = [NSMutableArray array];
    for (id record in records) @autoreleasepool {
        NSError *problem;
        NSString *trackID = [record isKindOfClass:NSDictionary.class] ? record[@"trackId"] : nil;
        NSDictionary *incoming;
        if (!SGLibraryTrackID(trackID)) {
            SGLibraryError(&problem, @"Thiếu định danh Spotify hợp lệ.");
        } else if (occurrences[trackID].unsignedIntegerValue > 1) {
            SGLibraryError(&problem, @"Bài hát xuất hiện nhiều lần trong cùng tệp nhập.");
        } else if (zip) {
            NSString *name = [NSString stringWithFormat:@"tracks/%@.json", trackID];
            NSData *entry = [record[@"file"] isEqual:name] ? [zip dataForName:name error:&problem] : nil;
            incoming = entry ? SGLibraryTrack(SGLibraryReadJSON(entry, &problem), &problem) : nil;
            if (incoming && ![incoming[@"trackId"] isEqual:trackID]) incoming = nil;
            if (!incoming && !problem) SGLibraryError(&problem, @"Manifest không khớp với tệp bài hát.");
        } else {
            incoming = SGLibraryTrack(record, &problem);
        }
        NSDictionary *existing = incoming ? [self track:trackID error:&problem] : nil;
        NSDictionary *merged = incoming && !problem ? SGLibraryMerge(existing, incoming, &problem) : nil;
        if (merged && ([merged isEqual:existing] || [self save:merged error:&problem])) {
            imported++;
            if ([merged[@"status"] isEqual:@"translated"]) translated++;
        } else {
            errors++;
            if (details.count < 20) {
                [details addObject:[NSString stringWithFormat:@"%@ · %@", SGLibraryTrackID(trackID) ? trackID : @"?",
                                    [problem.domain isEqual:SGLibraryErrorDomain] ? problem.localizedDescription : @"Lỗi đọc hoặc ghi dữ liệu."]];
            }
        }
    }
    return @{@"imported": @(imported), @"translated": @(translated), @"errors": @(errors), @"details": details};
}
@end

dispatch_queue_t SGLibraryQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ queue = dispatch_queue_create("syna.lyrics-library", DISPATCH_QUEUE_SERIAL); });
    return queue;
}

SGLibraryStore *SGLibraryLocalStore(void) {
    static SGLibraryStore *store;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                              inDomains:NSUserDomainMask].firstObject;
        store = [[SGLibraryStore alloc] initWithDirectory:[support URLByAppendingPathComponent:@"Spotify SYNA/Lyrics Library" isDirectory:YES]];
    });
    return store;
}
