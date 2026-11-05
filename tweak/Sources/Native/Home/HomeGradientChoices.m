// What the Gradient page offers and what the hooks read back, one entry per setting: the names, the
// key it is stored under and the index it falls back to. HomeGradient.x carries the numbers behind
// the names, in the same order as the names themselves.
#import "Core/SGCore.h"
#import "Home.h"

static NSDictionary *choiceDef(SGHomeChoice choice) {
    static NSDictionary<NSNumber *, NSDictionary *> *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{
            // Eight rotations of the green the wash was born as, at the same depth and saturation
            // around the wheel, so each of them sits behind white text the way the green does.
            @(SGHomeChoiceTint): @{
                @"key": @"spotifyglass.homeGradientTint",
                @"default": @0,
                @"names": @[SGLocalized(@"Spotify green"), SGLocalized(@"Teal"), SGLocalized(@"Blue"), SGLocalized(@"Indigo"), SGLocalized(@"Purple"), SGLocalized(@"Pink"),
                            SGLocalized(@"Red"), SGLocalized(@"Amber")],
            },
            @(SGHomeChoiceStrength): @{
                @"key": @"spotifyglass.homeGradientStrength",
                @"default": @1,
                @"names": @[SGLocalized(@"Subtle"), SGLocalized(@"Medium"), SGLocalized(@"Bold")],
            },
            @(SGHomeChoiceHeight): @{
                @"key": @"spotifyglass.homeGradientHeight",
                @"default": @1,
                @"names": @[SGLocalized(@"Short"), SGLocalized(@"Medium"), SGLocalized(@"Tall"), SGLocalized(@"The whole screen")],
            },
        };
    });
    return table[@(choice)] ?: table[@(SGHomeChoiceTint)];
}

NSArray<NSString *> *SGHomeChoiceNames(SGHomeChoice choice) {
    return choiceDef(choice)[@"names"];
}

NSString *SGHomeChoiceKey(SGHomeChoice choice) {
    return choiceDef(choice)[@"key"];
}

NSInteger SGHomeChoiceDefault(SGHomeChoice choice) {
    return [choiceDef(choice)[@"default"] integerValue];
}

NSInteger SGHomeChoiceValue(SGHomeChoice choice) {
    NSDictionary *def = choiceDef(choice);
    NSInteger fallback = [def[@"default"] integerValue];
    NSInteger index = SGInt(def[@"key"], fallback);
    return index >= 0 && index < (NSInteger)[def[@"names"] count] ? index : fallback;
}
