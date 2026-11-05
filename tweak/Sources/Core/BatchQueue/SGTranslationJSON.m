#import "SGTranslationJSON.h"
NSArray *SGTranslationJSONLines(NSString *text) {
    if (!text.length) return nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:[text dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (!parsed) {
        NSRange open = [text rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"[{"]];
        NSRange close = [text rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"]}"] options:NSBackwardsSearch];
        if (open.location != NSNotFound && close.location != NSNotFound && close.location > open.location) {
            NSString *inner = [text substringWithRange:NSMakeRange(open.location, close.location - open.location + 1)];
            parsed = [NSJSONSerialization JSONObjectWithData:[inner dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        }
    }
    if ([parsed isKindOfClass:NSDictionary.class]) parsed = parsed[@"lines"];
    return [parsed isKindOfClass:NSArray.class] ? parsed : nil;
}
NSArray<NSString *> *SGTranslationValidateLines(NSString *text, NSUInteger count, SGTranslationFailure *failure) {
    NSArray *lines = SGTranslationJSONLines(text);
    if (!lines) { if (failure) *failure = SGTranslationJSON; return nil; }
    if (lines.count != count) { if (failure) *failure = SGTranslationLineCount; return nil; }
    for (id line in lines) if (![line isKindOfClass:NSString.class]) { if (failure) *failure = SGTranslationJSON; return nil; }
    return lines;
}
