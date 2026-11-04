// What the lock screen fills the screen with, the lyrics' style and whether the downloads run in Low Data
// Mode. iOS 26 and up only.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "AnimatedArtwork.h"

SGLockArtwork SGLockScreenArtwork(void) {
    if (@available(iOS 26.0, *)) {
        // The old switch's YES and NO read as Moving artwork and Off, the enum's first two.
        static dispatch_once_t once;
        dispatch_once(&once, ^{ SGMigrateKey(SGKeyLockScreenMotion, SGKeyLockScreenArtwork); });
        return (SGLockArtwork)SGInt(SGKeyLockScreenArtwork, SGLockArtworkOff);
    }
    return SGLockArtworkOff;
}

NSArray *SGLockScreenMotionRows(void) {
    if (@available(iOS 26.0, *)) {
        SGLockScreenArtwork();   // moves the old switch over before the row reads the new key
        SGModRow *style = SGChoiceRow(SGLocalized(@"Lyrics style"), SGLocalized(@"Still draws each line once; Animated breathes the cover behind it. "
                                                       @"With moving artwork, for songs that have none"),
                                      SGKeyLockScreenLyricsStyle, @[SGLocalized(@"Still"), SGLocalized(@"Animated")], 0);
        style.visible = ^BOOL { return SGLockArtworkShowsLyrics(SGLockScreenArtwork()); };
        SGModRow *lowData = SGOptionRow(SGLocalized(@"Download in Low Data Mode"), SGLocalized(@"Moving artwork, up to about 7 MB a song"), SGKeyMotionLowData);
        lowData.visible = ^BOOL {
            SGLockArtwork artwork = SGLockScreenArtwork();
            return artwork == SGLockArtworkMotion || artwork == SGLockArtworkEverySong || artwork == SGLockArtworkMotionLyrics;
        };
        SGModRow *sources = SGMotionSourcesRow();
        sources.visible = lowData.visible;
        SGModRow *star = SGOptionRow(SGLocalized(@"Switch with the star"), SGLocalized(@"The lock screen widget's star swaps the moving artwork for the lyrics "
                                                             @"and back. It takes the place of Spotify's like and dislike buttons"),
                                     SGKeyLockScreenStar);
        star.visible = ^BOOL { return SGLockScreenArtwork() != SGLockArtworkOff; };
        return @[
            SGChoiceRow(SGLocalized(@"Full-screen artwork"), SGLocalized(@"The Canvas or Apple Music's animated cover, or the lyrics a line at a time. "
                                                 @"Every song puts the cover over a moving blur of it where a song has neither. "
                                                 @"Moving artwork with lyrics puts the lines over the Canvas or animated cover"),
                        SGKeyLockScreenArtwork, @[SGLocalized(@"Off"), SGLocalized(@"Moving artwork"), SGLocalized(@"Lyrics"), SGLocalized(@"Every song"), SGLocalized(@"Moving artwork with lyrics")],
                        SGLockArtworkOff),
            style,
            star,
            sources,
            lowData,
        ];
    }
    return @[SGLockScreenArtworkNeedsRow()];
}

// Below iOS 26 the section stays, with one row that says why there is nothing to pick.
SGModRow *SGLockScreenArtworkNeedsRow(void) {
    return SGStatActionRow(SGLocalized(@"Full-screen artwork"), nil, ^NSString *{ return SGLocalized(@"Needs iOS 26"); }, ^{
        NSString *message = [NSString stringWithFormat:SGLocalized(@"This iPhone has iOS %@. The lock screen takes moving artwork "
                                                       @"from apps from iOS 26 on, so the Canvas and Apple Music's animated "
                                                       @"covers can show there once the iPhone is updated."), UIDevice.currentDevice.systemVersion];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGLocalized(@"Needs iOS 26") message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:SGLocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    });
}
