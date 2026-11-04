#import "SGTranslationStore.h"
#import <sqlite3.h>
#import <TargetConditionals.h>
#import <math.h>
#import <CommonCrypto/CommonDigest.h>

NSString *const SGTranslationStoreErrorDomain = @"Vitrine.TranslationStore";
static NSError *problem(NSString *message) {
    return [NSError errorWithDomain:SGTranslationStoreErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey:message}];
}
static BOOL text(id value, NSUInteger limit) {
    return [value isKindOfClass:NSString.class] && [value length] > 0 && [value length] <= limit;
}

@implementation SGTranslationStore {
    NSURL *_url, *_legacy;
    sqlite3 *_db;
    dispatch_queue_t _queue;
    NSError *_openError;
}

+ (NSDictionary *)validatedRecord:(id)value error:(NSError **)error {
    NSString *reason = nil;
    if (![value isKindOfClass:NSDictionary.class]) reason = @"Invalid translation record.";
    else if (![value[@"type"] isEqual:@"vitrine.translation"] || ![value[@"schemaVersion"] isEqual:@1]) reason = @"Unsupported translation file version.";
    else if (!text(value[@"track"], 1024) || !text(value[@"language"], 64)) reason = @"Missing track or translation language.";
    else if ([value[@"track"] rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound ||
             [value[@"language"] rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) reason = @"Invalid translation identity.";
    id lines = reason ? nil : value[@"lines"];
    if (!reason && (![lines isKindOfClass:NSDictionary.class] || ![lines count] || [lines count] > 100000)) reason = @"Invalid translation lines.";
    if (!reason) for (id key in lines) {
        if (!text(key, 65536) || ![lines[key] isKindOfClass:NSString.class] || [lines[key] length] > 65536) {
            reason = @"Invalid translation lines."; break;
        }
    }
    for (NSString *key in @[@"by", @"model", @"title", @"artist"]) {
        if (!reason && value[key] && !text(value[key], 4096)) reason = @"Invalid translation metadata.";
    }
    if (!reason && value[@"made"] && (![value[@"made"] isKindOfClass:NSNumber.class] || !isfinite([value[@"made"] doubleValue]) || [value[@"made"] doubleValue] < 0)) reason = @"Invalid translation date.";
    if (reason) { if (error) *error = problem(reason); return nil; }
    NSMutableDictionary *clean = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"type", @"schemaVersion", @"track", @"language", @"lines", @"by", @"model", @"made", @"title", @"artist"]) {
        if (value[key]) clean[key] = value[key];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:clean options:0 error:error];
    if (!data || data.length > 8 * 1024 * 1024) { if (error) *error = problem(@"Translation file is too large."); return nil; }
    return clean;
}

+ (NSString *)identityForRecord:(NSDictionary *)record {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@[record[@"track"], record[@"language"]] options:0 error:nil];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *name = [NSMutableString string];
    for (NSUInteger i=0; i<sizeof(digest); i++) [name appendFormat:@"%02x", digest[i]];
    return name;
}

- (instancetype)initWithURL:(NSURL *)url legacyDirectory:(NSURL *)legacy {
    if (!(self = [super init])) return nil;
    _url = url; _legacy = legacy;
    _queue = dispatch_queue_create("vitrine.translations.database", DISPATCH_QUEUE_SERIAL);
    dispatch_sync(_queue, ^{ [self open]; });
    return self;
}

- (void)dealloc { if (_db) sqlite3_close(_db); }

- (BOOL)sql:(const char *)sql error:(NSError **)error {
    if (sqlite3_exec(_db, sql, NULL, NULL, NULL) == SQLITE_OK) return YES;
    if (error) *error = problem(@"Could not write translations. Check available storage.");
    return NO;
}

- (void)open {
    NSFileManager *fm = NSFileManager.defaultManager;
    if (![fm createDirectoryAtURL:_url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:&_openError]) return;
    if (sqlite3_open_v2(_url.path.UTF8String, &_db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, NULL) != SQLITE_OK) {
        _openError = problem(@"Could not open saved translations."); return;
    }
    sqlite3_busy_timeout(_db, 10000);
    if (![self sql:"PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS translations (track TEXT NOT NULL, language TEXT NOT NULL, json BLOB NOT NULL, title TEXT, artist TEXT, made REAL, bytes INTEGER NOT NULL, PRIMARY KEY(track,language));" error:&_openError]) return;
    // No eviction. Application Support participates in device backups. Files are protected after first unlock.
#if TARGET_OS_IPHONE
    [fm setAttributes:@{NSFileProtectionKey:NSFileProtectionCompleteUntilFirstUserAuthentication} ofItemAtPath:_url.path error:nil];
#endif
    [self migrateLegacy];
}

- (BOOL)ready:(NSError **)error {
    if (!_openError) return YES;
    if (error) *error = _openError;
    return NO;
}

- (BOOL)put:(NSDictionary *)record replace:(BOOL)replace didWrite:(BOOL *)didWrite error:(NSError **)error {
    if (didWrite) *didWrite = NO;
    if (![self ready:error]) return NO;
    NSDictionary *clean = [SGTranslationStore validatedRecord:record error:error];
    if (!clean) return NO;
    NSData *json = [NSJSONSerialization dataWithJSONObject:clean options:NSJSONWritingSortedKeys error:error];
    sqlite3_stmt *stmt = NULL;
    const char *sql = replace ? "INSERT OR REPLACE INTO translations VALUES(?,?,?,?,?,?,?)" : "INSERT OR IGNORE INTO translations VALUES(?,?,?,?,?,?,?)";
    if (sqlite3_prepare_v2(_db, sql, -1, &stmt, NULL) != SQLITE_OK) { if (error) *error = problem(@"Could not open saved translations."); return NO; }
    sqlite3_bind_text(stmt, 1, [clean[@"track"] UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 2, [clean[@"language"] UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_blob(stmt, 3, json.bytes, (int)json.length, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 4, [clean[@"title"] UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 5, [clean[@"artist"] UTF8String], -1, SQLITE_TRANSIENT);
    sqlite3_bind_double(stmt, 6, [clean[@"made"] doubleValue]);
    sqlite3_bind_int64(stmt, 7, (sqlite3_int64)json.length);
    BOOL ok = sqlite3_step(stmt) == SQLITE_DONE;
    if (ok && didWrite) *didWrite = sqlite3_changes(_db) > 0;
    sqlite3_finalize(stmt);
    if (!ok && error) *error = problem(@"Could not write translations. Check available storage.");
    return ok;
}

- (BOOL)putRecord:(NSDictionary *)record replace:(BOOL)replace didWrite:(BOOL *)didWrite error:(NSError **)error {
    __block BOOL ok, wrote = NO; __block NSError *failure = nil;
    dispatch_sync(_queue, ^{ ok = [self put:record replace:replace didWrite:&wrote error:&failure]; });
    if (didWrite) *didWrite = wrote;
    if (error) *error = failure;
    return ok;
}

- (void)migrateLegacy {
    if (!_legacy) return;
    // Each file is removed only after SQLite durably commits it. A crash retries the remainder.
    for (NSURL *url in [NSFileManager.defaultManager contentsOfDirectoryAtURL:_legacy includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil]) {
        if (![url.pathExtension isEqual:@"json"]) continue;
        NSString *stem = url.lastPathComponent.stringByDeletingPathExtension;
        NSString *language = stem.pathExtension, *track = stem.stringByDeletingPathExtension;
        NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:nil];
        if (!data || data.length > 8 * 1024 * 1024 || !language.length || !track.length) continue;
        id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![value isKindOfClass:NSDictionary.class]) continue;
        NSMutableDictionary *record = [@{@"schemaVersion":@1, @"type":@"vitrine.translation", @"track":track, @"language":language} mutableCopy];
        if ([value[@"lines"] isKindOfClass:NSDictionary.class]) {
            for (NSString *key in @[@"lines", @"by", @"model", @"made"]) if (value[key]) record[key] = value[key];
        } else record[@"lines"] = value;
        if ([self put:record replace:NO didWrite:NULL error:nil]) [NSFileManager.defaultManager removeItemAtURL:url error:nil];
    }
}

- (NSDictionary *)recordForTrack:(NSString *)track language:(NSString *)language error:(NSError **)error {
    __block NSDictionary *record = nil; __block NSError *failure = nil;
    dispatch_sync(_queue, ^{
        if (![self ready:&failure]) return;
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, "SELECT json FROM translations WHERE track=? AND language=?", -1, &stmt, NULL) != SQLITE_OK) { failure = problem(@"Could not read saved translations."); return; }
        sqlite3_bind_text(stmt, 1, track.UTF8String, -1, SQLITE_TRANSIENT);
        sqlite3_bind_text(stmt, 2, language.UTF8String, -1, SQLITE_TRANSIENT);
        int result = sqlite3_step(stmt);
        if (result == SQLITE_ROW) {
            NSData *data = [NSData dataWithBytes:sqlite3_column_blob(stmt,0) length:(NSUInteger)sqlite3_column_bytes(stmt,0)];
            record = [NSJSONSerialization JSONObjectWithData:data options:0 error:&failure];
        } else if (result != SQLITE_DONE) failure = problem(@"Could not read saved translations.");
        sqlite3_finalize(stmt);
    });
    if (error) *error = failure;
    return record;
}

- (NSArray<NSDictionary *> *)summaries:(NSError **)error {
    __block NSMutableArray *rows = [NSMutableArray array]; __block NSError *failure = nil;
    dispatch_sync(_queue, ^{
        if (![self ready:&failure]) return;
        sqlite3_stmt *stmt = NULL;
        if (sqlite3_prepare_v2(self->_db, "SELECT track,language,title,artist,made,bytes FROM translations ORDER BY made DESC,track,language", -1, &stmt, NULL) != SQLITE_OK) { failure = problem(@"Could not read saved translations."); return; }
        int result;
        while ((result = sqlite3_step(stmt)) == SQLITE_ROW) {
            NSMutableDictionary *row = [NSMutableDictionary dictionary];
            NSArray *keys = @[@"track",@"language",@"title",@"artist"];
            for (int i=0;i<4;i++) { const char *value = (const char *)sqlite3_column_text(stmt,i); if (value) row[keys[(NSUInteger)i]] = @(value); }
            row[@"made"] = @(sqlite3_column_double(stmt,4)); row[@"bytes"] = @(sqlite3_column_int64(stmt,5));
            [rows addObject:row];
        }
        if (result != SQLITE_DONE) failure = problem(@"Could not read saved translations.");
        sqlite3_finalize(stmt);
    });
    if (error) *error = failure;
    return rows;
}

- (BOOL)removeTrack:(NSString *)track language:(NSString *)language error:(NSError **)error {
    __block BOOL ok = NO; __block NSError *failure = nil;
    dispatch_sync(_queue, ^{
        if (![self ready:&failure]) return;
        sqlite3_stmt *stmt = NULL;
        const char *sql = track ? "DELETE FROM translations WHERE track=? AND language=?" : "DELETE FROM translations";
        if (sqlite3_prepare_v2(self->_db, sql, -1, &stmt, NULL) != SQLITE_OK) { failure = problem(@"Could not delete saved translations."); return; }
        if (track) { sqlite3_bind_text(stmt,1,track.UTF8String,-1,SQLITE_TRANSIENT); sqlite3_bind_text(stmt,2,language.UTF8String,-1,SQLITE_TRANSIENT); }
        ok = sqlite3_step(stmt) == SQLITE_DONE; sqlite3_finalize(stmt);
        if (!ok) failure = problem(@"Could not delete saved translations.");
    });
    if (error) *error = failure;
    return ok;
}
@end
