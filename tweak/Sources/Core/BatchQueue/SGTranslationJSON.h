#import <Foundation/Foundation.h>
#import "SGTranslationQueue.h"
NSArray *SGTranslationJSONLines(NSString *text);
NSArray<NSString *> *SGTranslationValidateLines(NSString *text, NSUInteger count, SGTranslationFailure *failure);
