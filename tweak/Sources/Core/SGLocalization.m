#import "SGLocalization.h"

NSString *SGUILanguage(void) {
    NSString *manual=[NSUserDefaults.standardUserDefaults stringForKey:SGKeyUILanguage];
    if ([manual isEqual:@"en"] || [manual isEqual:@"vi"]) return manual;
    return [NSLocale.preferredLanguages.firstObject.lowercaseString hasPrefix:@"vi"] ? @"vi" : @"en";
}
NSLocale *SGUILocale(void) { return [NSLocale localeWithLocaleIdentifier:SGUILanguage()]; }
NSString *SGLocalized(NSString *english) {
    if (!english || ![SGUILanguage() isEqual:@"vi"]) return english;
    static NSDictionary<NSString *,NSString *> *catalog;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ catalog = @{
#include "SGUICatalog.inc"
    }; });
    return catalog[english] ?: english;
}
NSString *SGLocalizedError(NSError *error) {
    if(!error)return SGLocalized(@"Could not complete the operation. Please try again.");
    NSString *message=SGLocalized(error.localizedDescription);
    if(![message isEqual:error.localizedDescription] || [SGUILanguage() isEqual:@"en"])return message;
    // Framework and server messages may use a different language from Vitrine. Show a translated fallback.
    return [NSString stringWithFormat:@"%@ (%ld)",SGLocalized(@"Could not complete the operation. Please try again."),(long)error.code];
}

NSString *SGLocalizedContext(NSString *english, NSString *context) {
    NSString *key=[NSString stringWithFormat:@"%@|%@",english,context];
    NSString *result=SGLocalized(key);
    return [result isEqual:key] ? english : result;
}
