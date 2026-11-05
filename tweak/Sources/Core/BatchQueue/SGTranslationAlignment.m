#import "SGTranslationAlignment.h"
#import <NaturalLanguage/NaturalLanguage.h>

NSString *SGTranslationLineKey(NSString *text) {
    if (![text isKindOfClass:NSString.class]) return @"";
    NSString *folded = [[text precomposedStringWithCanonicalMapping] lowercaseStringWithLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    NSMutableCharacterSet *letters = [NSCharacterSet.alphanumericCharacterSet mutableCopy];
    [letters formUnionWithCharacterSet:NSCharacterSet.nonBaseCharacterSet];
    return [[folded componentsSeparatedByCharactersInSet:letters.invertedSet] componentsJoinedByString:@""];
}
BOOL SGTranslationLineNeedsText(NSString *text) {
    return [text isKindOfClass:NSString.class] && [text rangeOfCharacterFromSet:NSCharacterSet.alphanumericCharacterSet].location != NSNotFound;
}
NSIndexSet *SGTranslationMissingLines(NSArray<NSString *> *originals, NSArray *translations) {
    NSMutableIndexSet *missing = [NSMutableIndexSet indexSet];
    for (NSUInteger i = 0; i < originals.count; ++i) {
        if (SGTranslationLineNeedsText(originals[i]) && (i >= translations.count || !SGTranslationLineNeedsText(translations[i]))) [missing addIndex:i];
    }
    return missing;
}
NSIndexSet *SGTranslationUnchangedForeignLines(NSArray<NSString *> *originals, NSArray *translations, NSString *target) {
    NSMutableIndexSet *unchanged = [NSMutableIndexSet indexSet];
    NLLanguageRecognizer *recognizer = [NLLanguageRecognizer new];
    NSString *code = [[target componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"-_"]] firstObject].lowercaseString;
    for (NSUInteger i = 0; i < originals.count && i < translations.count; ++i) {
        NSString *key = SGTranslationLineKey(originals[i]);
        if (key.length < 16 || ![key isEqual:SGTranslationLineKey(translations[i])]) continue;
        [recognizer reset]; [recognizer processString:originals[i]];
        NSDictionary *hypotheses = [recognizer languageHypothesesWithMaximum:1];
        NSString *language = hypotheses.allKeys.firstObject;
        if (language.length && ![language isEqual:code] && [hypotheses[language] doubleValue] >= 0.9) [unchanged addIndex:i];
    }
    return unchanged;
}
NSDictionary *SGTranslationMergeLines(NSDictionary *existing, NSDictionary *incoming) {
    NSMutableDictionary *merged = [NSMutableDictionary dictionary];
    for (id key in existing) if ([key isKindOfClass:NSString.class] && [existing[key] isKindOfClass:NSString.class]) merged[key] = existing[key];
    for (id key in incoming) if ([key isKindOfClass:NSString.class] && [incoming[key] isKindOfClass:NSString.class] &&
        SGTranslationLineNeedsText(incoming[key])) merged[key] = incoming[key];
    // Keep original spellings for old exports/providers while updating their typography aliases.
    // This prevents a repaired curly-apostrophe line conflicting with its old straight-apostrophe copy.
    NSMutableDictionary *updates = [NSMutableDictionary dictionary];
    for (NSString *key in incoming) if (SGTranslationLineNeedsText(incoming[key])) updates[SGTranslationLineKey(key)] = incoming[key];
    for (NSString *key in merged.allKeys) if (updates[SGTranslationLineKey(key)]) merged[key] = updates[SGTranslationLineKey(key)];
    return merged;
}
NSArray<NSString *> *SGTranslationResolveLines(NSDictionary<NSString *, NSString *> *saved, NSArray<NSString *> *originals) {
    NSMutableDictionary<NSString *, NSString *> *byKey = [NSMutableDictionary dictionary];
    NSMutableSet *ambiguous = [NSMutableSet set];
    for (NSString *text in saved) {
        NSString *key = SGTranslationLineKey(text), *value = saved[text];
        if (!key.length || !SGTranslationLineNeedsText(value)) continue;
        if (byKey[key] && ![byKey[key] isEqual:value]) [ambiguous addObject:key];
        byKey[key] = value;
    }
    for (NSString *key in ambiguous) [byKey removeObjectForKey:key];
    // Bounded exact concatenation only: e.g. two Spotify rows becoming one TTML row. Never split a
    // translation by character count, match by index/time alone, or guess the meaning of another line.
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *prefixes = [NSMutableDictionary dictionary];
    for (NSString *key in byKey) if (key.length >= 2) {
        NSString *first = [key substringToIndex:1];
        if (!prefixes[first]) prefixes[first] = [NSMutableArray array];
        [prefixes[first] addObject:key];
    }
    NSMutableArray *resolved = [NSMutableArray arrayWithCapacity:originals.count];
    for (NSString *original in originals) {
        NSString *direct = saved[original], *key = SGTranslationLineKey(original), *value = byKey[key];
        if (SGTranslationLineNeedsText(direct)) { [resolved addObject:direct]; continue; }
        if (value) { [resolved addObject:value]; continue; }
        if (!key.length || key.length > 4096 || byKey.count > 4000) { [resolved addObject:@""]; continue; }
        NSUInteger length = key.length;
        NSMutableArray<NSNumber *> *ways = [NSMutableArray arrayWithCapacity:length + 1];
        NSMutableArray *paths = [NSMutableArray arrayWithCapacity:length + 1];
        for (NSUInteger i = 0; i <= length; ++i) { [ways addObject:@0]; [paths addObject:NSNull.null]; }
        ways[0] = @1; paths[0] = @[];
        for (NSUInteger i = 0; i < length; ++i) {
            if (!ways[i].unsignedIntegerValue) continue;
            NSArray *candidates = prefixes[[key substringWithRange:NSMakeRange(i, 1)]];
            for (NSString *piece in candidates) {
                if (i + piece.length > length || [key compare:piece options:0 range:NSMakeRange(i, piece.length)] != NSOrderedSame) continue;
                NSUInteger end = i + piece.length;
                ways[end] = @(MIN(2, ways[end].unsignedIntegerValue + ways[i].unsignedIntegerValue));
                if (ways[end].unsignedIntegerValue == 1) paths[end] = [(NSArray *)paths[i] arrayByAddingObject:byKey[piece]];
                else paths[end] = NSNull.null;
            }
        }
        [resolved addObject:ways[length].unsignedIntegerValue == 1 ? [(NSArray *)paths[length] componentsJoinedByString:@" "] : @""];
    }
    return resolved;
}
