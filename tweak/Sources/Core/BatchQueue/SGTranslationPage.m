#import "SGTranslationPage.h"
NSURL *SGTranslationPageURL(NSString *address, NSURL *base) {
    if (![address isKindOfClass:NSString.class] || !address.length) return nil;
    NSURL *url = [NSURL URLWithString:address relativeToURL:base].absoluteURL;
    if (![url.scheme isEqual:@"https"] || url.user || url.password ||
        ![@[@"spclient.wg.spotify.com", @"api.spotify.com"] containsObject:url.host.lowercaseString] ||
        (base && ![url.host.lowercaseString isEqual:base.host.lowercaseString])) return nil;
    return url;
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
            if (![identifier isKindOfClass:NSString.class] || identifier.length != 22 ||
                [identifier rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"].invertedSet].location != NSNotFound) continue;
            id metadata = track[@"metadata"];
            NSString *title = track[@"name"] ?: ([metadata isKindOfClass:NSDictionary.class] ? metadata[@"title"] : nil);
            NSString *artist = [metadata isKindOfClass:NSDictionary.class] ? metadata[@"artist_name"] : nil;
            if ([title isKindOfClass:NSString.class] && [artist isKindOfClass:NSString.class]) title = [title stringByAppendingFormat:@" — %@", artist];
            [result addObject:@{@"id":identifier, @"title":[title isKindOfClass:NSString.class] ? title : identifier}];
        }
    }
    return result;
}
