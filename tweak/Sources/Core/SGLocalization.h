#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
#define SGKeyUILanguage @"spotifyglass.interfaceLanguage"
// Exact, explicit UI keys only. Never pass song titles, lyrics, API payloads or identifiers here.
NSString *SGUILanguage(void);
NSLocale *SGUILocale(void);
NSString *SGLocalized(NSString *english);
NSString *SGLocalizedContext(NSString *english, NSString *context);
NSString *SGLocalizedError(NSError * _Nullable error);
NS_ASSUME_NONNULL_END
