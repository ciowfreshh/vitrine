#import "SGTranslationPage.h"
NSURL *SGTranslationPageURL(NSString *address, NSURL *base) {
    if (![address isKindOfClass:NSString.class] || !address.length) return nil;
    NSURL *url = [NSURL URLWithString:address relativeToURL:base].absoluteURL;
    if (![url.scheme isEqual:@"https"] || url.user || url.password ||
        ![@[@"spclient.wg.spotify.com", @"api.spotify.com"] containsObject:url.host.lowercaseString] ||
        (base && ![url.host.lowercaseString isEqual:base.host.lowercaseString])) return nil;
    return url;
}
static NSString *trackIDFromGID(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSData *data = [[NSData alloc] initWithBase64EncodedString:value options:0];
    if (data.length != 16) return nil;
    unsigned char number[16]; [data getBytes:number length:16];
    const char *digits = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
    char result[23]; result[22] = 0;
    for (NSInteger position = 21; position >= 0; --position) {
        unsigned remainder = 0;
        for (NSUInteger i = 0; i < 16; ++i) { unsigned n = remainder * 256 + number[i]; number[i] = n / 62; remainder = n % 62; }
        result[position] = digits[remainder];
    }
    return [NSString stringWithUTF8String:result];
}
NSArray<NSDictionary *> *SGTranslationTracksPage(id root, NSURL *base, NSString **next, NSUInteger *scanned) {
    if (![root isKindOfClass:NSDictionary.class]) return nil;
    NSArray *pages;
    if ([root[@"pages"] isKindOfClass:NSArray.class]) pages = root[@"pages"];
    else if ([root[@"items"] isKindOfClass:NSArray.class]) pages = @[root];
    else return nil;
    NSMutableArray *result = [NSMutableArray array];
    *scanned = 0; *next = nil;
    for (id page in pages) {
        if (![page isKindOfClass:NSDictionary.class]) return nil;
        NSArray *items = page[@"tracks"] ?: page[@"items"];
        if (![items isKindOfClass:NSArray.class]) return nil;
        id after = page[@"next_page_url"] ?: page[@"next"];
        if (after && after != NSNull.null) {
            NSURL *validated = SGTranslationPageURL(after, base); if (!validated) return nil;
            *next = validated.absoluteString;
        }
        for (id entry in items) {
            ++*scanned;
            if (![entry isKindOfClass:NSDictionary.class]) continue;
            id track = entry[@"track"] ?: entry;
            if (![track isKindOfClass:NSDictionary.class]) continue;
            NSString *uri = track[@"uri"], *identifier = track[@"id"];
            if ([uri isKindOfClass:NSString.class] && [uri hasPrefix:@"spotify:track:"]) identifier = [uri substringFromIndex:14];
            if (![identifier isKindOfClass:NSString.class]) identifier = trackIDFromGID(track[@"gid"]);
            if (![identifier isKindOfClass:NSString.class] || identifier.length != 22 ||
                [identifier rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"].invertedSet].location != NSNotFound) continue;
            id metadata = track[@"metadata"];
            NSString *title = track[@"name"] ?: ([metadata isKindOfClass:NSDictionary.class] ? metadata[@"title"] : nil);
            NSString *artist = [metadata isKindOfClass:NSDictionary.class] ? metadata[@"artist_name"] : nil;
            id artists = track[@"artists"];
            if ([artists isKindOfClass:NSArray.class] && [artists count] && [artists[0] isKindOfClass:NSDictionary.class] && [artists[0][@"name"] isKindOfClass:NSString.class]) artist = artists[0][@"name"];
            NSMutableDictionary *named = [@{@"id":identifier, @"title":[title isKindOfClass:NSString.class] ? title : identifier} mutableCopy];
            if ([title isKindOfClass:NSString.class]) named[@"name"] = title;
            if ([artist isKindOfClass:NSString.class]) { named[@"artist"] = artist; named[@"title"] = [named[@"title"] stringByAppendingFormat:@" — %@", artist]; }
            [result addObject:named];
        }
    }
    return result;
}
