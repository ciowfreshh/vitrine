#import <Foundation/Foundation.h>

// Formatting aliases are safe for every tag. Vietnamese's device default (vi-VN) and the
// language picker (vi) name the same translation target. Do not collapse other regions or scripts.
NS_INLINE NSString *SGTranslationLanguageTag(NSString *value) {
    return [[[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]
        stringByReplacingOccurrencesOfString:@"_" withString:@"-"] lowercaseString];
}
NS_INLINE NSString *SGTranslationLanguageIdentity(NSString *value) {
    NSString *tag = SGTranslationLanguageTag(value);
    NSArray<NSString *> *parts = [tag componentsSeparatedByString:@"-"];
    if (![parts.firstObject isEqual:@"vi"]) return tag;
    NSCharacterSet *letters = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz"];
    NSCharacterSet *digits = NSCharacterSet.decimalDigitCharacterSet;
    for (NSString *part in [parts subarrayWithRange:NSMakeRange(1, parts.count - 1)]) {
        BOOL region = (part.length == 2 && [part rangeOfCharacterFromSet:letters.invertedSet].location == NSNotFound) ||
            (part.length == 3 && [part rangeOfCharacterFromSet:digits.invertedSet].location == NSNotFound);
        if (!region && ![part isEqual:@"latn"]) return tag;
    }
    return @"vi";
}
NS_INLINE BOOL SGTranslationSameLanguage(NSString *a, NSString *b) {
    return a.length && b.length && [SGTranslationLanguageIdentity(a) isEqual:SGTranslationLanguageIdentity(b)];
}
