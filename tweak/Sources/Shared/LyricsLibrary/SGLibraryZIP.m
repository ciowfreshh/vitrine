#import "SGLibraryZIP.h"
#import "SGLibraryModel.h"
#import <zlib.h>

static const NSUInteger zipLimit = 192 * 1024 * 1024;
static const NSUInteger entryLimit = 12 * 1024 * 1024;
static const NSUInteger countLimit = 40001;

static uint16_t word(const uint8_t *p) { return p[0] | (uint16_t)p[1] << 8; }
static uint32_t longword(const uint8_t *p) { return word(p) | (uint32_t)word(p + 2) << 16; }

static void appendWord(NSMutableData *data, uint16_t n) {
    const uint8_t bytes[] = {n & 255, n >> 8};
    [data appendBytes:bytes length:sizeof(bytes)];
}

static void appendLong(NSMutableData *data, uint32_t n) {
    appendWord(data, n & 65535);
    appendWord(data, n >> 16);
}

static BOOL validName(NSString *name) {
    if ([name isEqual:@"manifest.json"]) return YES;
    return name.length == 34 && [name hasPrefix:@"tracks/"] && [name hasSuffix:@".json"] &&
           SGLibraryTrackID([name substringWithRange:NSMakeRange(7, 22)]);
}

@implementation SGLibraryZIP {
    NSData *_data;
    NSDictionary<NSString *, NSArray<NSNumber *> *> *_entries;
}

- (instancetype)initWithData:(NSData *)data error:(NSError **)error {
    if (!(self = [super init])) return nil;
    if (data.length < 22 || data.length > zipLimit) goto invalid;
    {
        const uint8_t *p = data.bytes;
        NSUInteger end = data.length - 22;
        NSUInteger minimum = end > 65535 ? end - 65535 : 0;
        while (longword(p + end) != 0x06054b50 || end + 22 + word(p + end + 20) != data.length) {
            if (end == minimum) goto invalid;
            end--;
        }
        NSUInteger size = longword(p + end + 12), start = longword(p + end + 16), count = word(p + end + 10);
        if (!count || count > countLimit || word(p + end + 4) || word(p + end + 6) ||
            word(p + end + 8) != count || start > end || size != end - start) goto invalid;
        NSMutableDictionary *entries = [NSMutableDictionary dictionaryWithCapacity:count];
        NSUInteger offset = start, total = 0;
        for (NSUInteger i = 0; i < count; i++) {
            if (end - offset < 46 || longword(p + offset) != 0x02014b50) goto invalid;
            const uint8_t *entry = p + offset;
            NSUInteger flags = word(entry + 8), method = word(entry + 10), crc = longword(entry + 16);
            NSUInteger packed = longword(entry + 20), unpacked = longword(entry + 24);
            NSUInteger nameLength = word(entry + 28), local = longword(entry + 42);
            NSUInteger entrySize = 46 + nameLength + word(entry + 30) + word(entry + 32);
            if (entrySize > end - offset || start < 30 || local > start - 30 || unpacked > entryLimit ||
                unpacked > zipLimit - total || word(entry + 34) || (flags & ~0x080eU) ||
                (method != 0 && method != Z_DEFLATED) || (method == 0 && packed != unpacked)) goto invalid;
            NSString *name = [[NSString alloc] initWithBytes:entry + 46 length:nameLength encoding:NSUTF8StringEncoding];
            BOOL directory = [name isEqual:@"tracks/"];
            if ((!directory && !validName(name)) || entries[name] || (directory && unpacked)) goto invalid;
            const uint8_t *localHeader = p + local;
            NSUInteger headerLength = 30 + nameLength + word(localHeader + 28);
            if (longword(localHeader) != 0x04034b50 || word(localHeader + 6) != flags ||
                word(localHeader + 8) != method || word(localHeader + 26) != nameLength ||
                headerLength > start - local || packed > start - local - headerLength ||
                memcmp(localHeader + 30, entry + 46, nameLength)) goto invalid;
            if (!directory) entries[name] = @[@(local + headerLength), @(packed), @(unpacked), @(method), @(crc)];
            total += unpacked;
            offset += entrySize;
        }
        if (offset != end || !entries[@"manifest.json"]) goto invalid;
        _data = data;
        _entries = [entries copy];
        return self;
    }
invalid:
    SGLibraryError(error, @"ZIP không hợp lệ, chứa tệp lạ hoặc vượt giới hạn dung lượng.");
    return nil;
}

- (NSArray<NSString *> *)names {
    return _entries.allKeys;
}

- (NSData *)dataForName:(NSString *)name error:(NSError **)error {
    NSArray<NSNumber *> *entry = _entries[name];
    if (entry) {
        NSUInteger offset = entry[0].unsignedIntegerValue, packed = entry[1].unsignedIntegerValue;
        NSUInteger size = entry[2].unsignedIntegerValue;
        const uint8_t *input = (const uint8_t *)_data.bytes + offset;
        NSData *decoded;
        if (entry[3].unsignedIntegerValue == Z_DEFLATED) {
            NSMutableData *output = [NSMutableData dataWithLength:MAX(size, 1)];
            z_stream stream = {0};
            stream.next_in = (Bytef *)input;
            stream.avail_in = (uInt)packed;
            stream.next_out = output.mutableBytes;
            stream.avail_out = (uInt)output.length;
            if (inflateInit2(&stream, -MAX_WBITS) == Z_OK) {
                int result = inflate(&stream, Z_FINISH);
                if (result == Z_STREAM_END && stream.total_out == size && stream.total_in == packed) {
                    output.length = size;
                    decoded = output;
                }
                inflateEnd(&stream);
            }
        } else {
            decoded = [_data subdataWithRange:NSMakeRange(offset, packed)];
        }
        if (decoded && crc32(0, decoded.bytes, (uInt)decoded.length) == entry[4].unsignedIntValue) return decoded;
    }
    SGLibraryError(error, @"Một tệp trong ZIP bị thiếu hoặc sai mã kiểm tra.");
    return nil;
}
@end

@implementation SGLibraryZIPWriter {
    NSMutableData *_data, *_directory;
    NSMutableSet<NSString *> *_names;
}

- (instancetype)init {
    if ((self = [super init])) {
        _data = [NSMutableData data];
        _directory = [NSMutableData data];
        _names = [NSMutableSet set];
    }
    return self;
}

- (BOOL)addData:(NSData *)data name:(NSString *)name error:(NSError **)error {
    NSData *nameData = [name dataUsingEncoding:NSUTF8StringEncoding];
    if (!validName(name) || [_names containsObject:name] || _names.count >= countLimit || !data ||
        data.length > entryLimit || _data.length + _directory.length + data.length + 200 > zipLimit) {
        SGLibraryError(error, @"Không thể thêm tệp vào ZIP vì tên hoặc dung lượng không hợp lệ.");
        return NO;
    }
    uint32_t offset = (uint32_t)_data.length, size = (uint32_t)data.length;
    uint32_t crc = (uint32_t)crc32(0, data.bytes, (uInt)data.length);
    uint16_t nameLength = (uint16_t)nameData.length;

    appendLong(_data, 0x04034b50);
    appendWord(_data, 20);
    appendWord(_data, 0);
    appendWord(_data, 0);
    appendLong(_data, 0x00210000);
    appendLong(_data, crc);
    appendLong(_data, size);
    appendLong(_data, size);
    appendWord(_data, nameLength);
    appendWord(_data, 0);
    [_data appendData:nameData];
    [_data appendData:data];

    appendLong(_directory, 0x02014b50);
    appendWord(_directory, 20);
    appendWord(_directory, 20);
    appendWord(_directory, 0);
    appendWord(_directory, 0);
    appendLong(_directory, 0x00210000);
    appendLong(_directory, crc);
    appendLong(_directory, size);
    appendLong(_directory, size);
    appendWord(_directory, nameLength);
    for (NSUInteger i = 0; i < 4; i++) appendWord(_directory, 0);
    appendLong(_directory, 0);
    appendLong(_directory, offset);
    [_directory appendData:nameData];
    [_names addObject:name];
    return YES;
}

- (NSData *)finish {
    uint32_t offset = (uint32_t)_data.length;
    [_data appendData:_directory];
    appendLong(_data, 0x06054b50);
    appendWord(_data, 0);
    appendWord(_data, 0);
    appendWord(_data, (uint16_t)_names.count);
    appendWord(_data, (uint16_t)_names.count);
    appendLong(_data, (uint32_t)_directory.length);
    appendLong(_data, offset);
    appendWord(_data, 0);
    return _data;
}
@end
