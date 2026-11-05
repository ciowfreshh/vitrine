#import "Core/SGLocalization.h"
#import "SGTranslationArchive.h"
#import "SGTranslationStore.h"
#import <zlib.h>

static NSError *invalid(void) {
    return [NSError errorWithDomain:SGTranslationStoreErrorDomain code:2 userInfo:@{NSLocalizedDescriptionKey:SGLocalized(@"Invalid or unsupported translation archive.")}];
}
static void u16(NSMutableData *d, uint16_t n) { uint8_t b[]={(uint8_t)n,(uint8_t)(n>>8)}; [d appendBytes:b length:2]; }
static void u32(NSMutableData *d, uint32_t n) { u16(d,(uint16_t)n); u16(d,(uint16_t)(n>>16)); }
static uint16_t r16(const uint8_t *b) { return b[0] | ((uint16_t)b[1]<<8); }
static uint32_t r32(const uint8_t *b) { return r16(b) | ((uint32_t)r16(b+2)<<16); }
static BOOL fits(NSUInteger offset, NSUInteger length, NSUInteger total) { return offset <= total && length <= total-offset; }

@implementation SGTranslationArchive
+ (BOOL)writeRecords:(NSArray<NSDictionary *> *)summaries toURL:(NSURL *)url record:(NSDictionary *(^)(NSDictionary *, NSError **))record
           progress:(void (^)(NSUInteger, NSUInteger))progress error:(NSError **)error {
    if (summaries.count > 50000) { if (error) *error=invalid(); return NO; }
    NSURL *partial = [url.URLByDeletingLastPathComponent URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSOutputStream *stream = [NSOutputStream outputStreamWithURL:partial append:NO]; [stream open];
    BOOL (^write)(NSData *) = ^BOOL(NSData *data) {
        NSUInteger offset=0;
        while (offset<data.length) { NSInteger n=[stream write:(const uint8_t *)data.bytes+offset maxLength:data.length-offset]; if (n<=0) return NO; offset+=(NSUInteger)n; }
        return YES;
    };
    NSMutableData *central=[NSMutableData data]; uint64_t offset=0; BOOL ok=YES; NSUInteger done=0;
    for (NSDictionary *summary in summaries) { @autoreleasepool {
        NSDictionary *value=record(summary,error);
        NSDictionary *clean=value ? [SGTranslationStore validatedRecord:value error:error] : nil;
        NSData *json=clean ? [NSJSONSerialization dataWithJSONObject:clean options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:error] : nil;
        if (!json) { ok=NO; break; }
        NSData *name=[[[SGTranslationStore identityForRecord:clean] stringByAppendingString:@".json"] dataUsingEncoding:NSUTF8StringEncoding];
        uint32_t crc=(uint32_t)crc32(0,json.bytes,(uInt)json.length), size=(uint32_t)json.length;
        NSMutableData *header=[NSMutableData data];
        u32(header,0x04034b50);u16(header,20);u16(header,0);u16(header,0);u16(header,0);u16(header,0);u32(header,crc);u32(header,size);u32(header,size);u16(header,(uint16_t)name.length);u16(header,0);[header appendData:name];
        if (offset+header.length+json.length+central.length+128 > UINT32_MAX || !write(header) || !write(json)) { ok=NO; break; }
        u32(central,0x02014b50);u16(central,20);u16(central,20);u16(central,0);u16(central,0);u16(central,0);u16(central,0);u32(central,crc);u32(central,size);u32(central,size);u16(central,(uint16_t)name.length);u16(central,0);u16(central,0);u16(central,0);u16(central,0);u32(central,0);u32(central,(uint32_t)offset);[central appendData:name];
        offset+=header.length+json.length; if (progress) progress(++done,summaries.count);
    }}
    NSMutableData *end=[NSMutableData data];
    u32(end,0x06054b50);u16(end,0);u16(end,0);u16(end,(uint16_t)summaries.count);u16(end,(uint16_t)summaries.count);u32(end,(uint32_t)central.length);u32(end,(uint32_t)offset);u16(end,0);
    if (ok) ok=write(central)&&write(end);
    [stream close];
    if (ok) ok=[NSFileManager.defaultManager moveItemAtURL:partial toURL:url error:error];
    if (!ok) { [NSFileManager.defaultManager removeItemAtURL:partial error:nil]; if (error && !*error) *error=stream.streamError ?: invalid(); }
    return ok;
}

+ (BOOL)readURL:(NSURL *)url consume:(BOOL (^)(id,NSError **))consume progress:(void (^)(NSUInteger,NSUInteger))progress error:(NSError **)error {
    NSNumber *size; [url getResourceValue:&size forKey:NSURLFileSizeKey error:error];
    if (!size || size.unsignedLongLongValue>1024ULL*1024*1024) { if (error) *error=invalid(); return NO; }
    NSData *data=[NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error];
    if (!data) return NO;
    if ([url.pathExtension.lowercaseString isEqual:@"json"]) {
        if (data.length>8*1024*1024) { if(error)*error=invalid(); return NO; }
        id value=[NSJSONSerialization JSONObjectWithData:data options:0 error:error];
        BOOL ok=value && consume(value,error); if (ok && progress) progress(1,1); return ok;
    }
    const uint8_t *b=data.bytes; NSUInteger n=data.length, end=NSNotFound;
    if (n>=22) for (NSUInteger i=n-22;;i--) {
        if (r32(b+i)==0x06054b50 && fits(i,22+r16(b+i+20),n) && i+22+r16(b+i+20)==n) { end=i; break; }
        if (!i || n-i>65557) break;
    }
    BOOL ok=end!=NSNotFound;
    uint16_t count=ok?r16(b+end+10):0; NSUInteger cursor=ok?r32(b+end+16):0, start=cursor;
    if (ok) ok=!r16(b+end+4)&&!r16(b+end+6)&&r16(b+end+8)==count&&count<=50000&&fits(cursor,r32(b+end+12),end)&&cursor+r32(b+end+12)==end;
    // Read central directory before processing entries, rejecting encrypted, symlink and traversal names.
    NSMutableArray *entries=[NSMutableArray array]; NSMutableSet *names=[NSMutableSet set]; uint64_t total=0;
    for (NSUInteger i=0;ok && i<count;i++) {
        if (!fits(cursor,46,end)||r32(b+cursor)!=0x02014b50) {ok=NO;break;}
        uint16_t flags=r16(b+cursor+8),method=r16(b+cursor+10),nameLength=r16(b+cursor+28),extra=r16(b+cursor+30),comment=r16(b+cursor+32);
        uint32_t compressed=r32(b+cursor+20),plain=r32(b+cursor+24),local=r32(b+cursor+42);
        NSUInteger length=46+(NSUInteger)nameLength+extra+comment;
        if (!fits(cursor,length,end)||flags&1||(method!=0&&method!=8)||plain>8*1024*1024||compressed>16*1024*1024||r16(b+cursor+34)||((r32(b+cursor+38)>>16)&0170000)==0120000) {ok=NO;break;}
        NSString *name=[[NSString alloc]initWithBytes:b+cursor+46 length:nameLength encoding:NSUTF8StringEncoding];
        if (!name.length || [name hasPrefix:@"/"] || [name containsString:@"\\"] || [name containsString:@":"] || [name.pathComponents containsObject:@".."] || [name rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location!=NSNotFound || ![name.pathExtension.lowercaseString isEqual:@"json"] || [names containsObject:name]) {ok=NO;break;}
        [names addObject:name]; total+=plain; if(total>512ULL*1024*1024){ok=NO;break;}
        if (!fits(local,30,start)||r32(b+local)!=0x04034b50 ||r16(b+local+6)!=flags ||r16(b+local+8)!=method ||r16(b+local+26)!=nameLength) {ok=NO;break;}
        NSUInteger body=(NSUInteger)local+30+r16(b+local+26)+r16(b+local+28);
        if (!fits(local+30,nameLength,start)||memcmp(b+local+30,b+cursor+46,nameLength)||!fits(body,compressed,start)) {ok=NO;break;}
        [entries addObject:@{@"offset":@(body),@"compressed":@(compressed),@"size":@(plain),@"method":@(method),@"crc":@(r32(b+cursor+16))}];
        cursor+=length;
    }
    ok=ok&&cursor==end;
    if (!ok) {if(error)*error=invalid();return NO;}
    NSUInteger done=0;
    for (NSDictionary *entry in entries) { @autoreleasepool {
        NSUInteger offset=[entry[@"offset"] unsignedIntegerValue],compressed=[entry[@"compressed"] unsignedIntegerValue],plain=[entry[@"size"] unsignedIntegerValue];
        NSMutableData *json=[NSMutableData dataWithLength:plain];
        if ([entry[@"method"] intValue]==0) {if(compressed!=plain)ok=NO;else memcpy(json.mutableBytes,b+offset,plain);}
        else {
            z_stream z={0};z.next_in=(Bytef *)(b+offset);z.avail_in=(uInt)compressed;z.next_out=json.mutableBytes;z.avail_out=(uInt)plain;
            if(inflateInit2(&z,-MAX_WBITS)!=Z_OK)ok=NO;
            else {int result=inflate(&z,Z_FINISH);ok=result==Z_STREAM_END&&z.total_out==plain&&z.total_in==compressed;inflateEnd(&z);}
        }
        if(ok)ok=(uint32_t)crc32(0,json.bytes,(uInt)plain)==[entry[@"crc"] unsignedIntValue];
        id value=ok?[NSJSONSerialization JSONObjectWithData:json options:0 error:error]:nil;
        if(!value || !consume(value,error)){if(error&&!*error)*error=invalid();return NO;}
        if(progress)progress(++done,entries.count);
    }}
    return YES;
}
@end
