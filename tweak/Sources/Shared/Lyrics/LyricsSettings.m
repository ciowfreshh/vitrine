// The Lyrics page's parts; App/Pages.m assembles the page.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Lyrics.h"
#import "Shared/LocalFiles/LocalLyrics.h"
#import "Shared/LockScreenLyrics/LockScreenLyrics.h"
#import "Shared/LyricsSources/LyricsSources.h"

SGModSection *SGLyricsSourcesSection(BOOL namingSource) {
    SGModRow *sources = SGPageRow(SGLocalized(@"Sources"), ^UIViewController *{ return SGLyricsSourcesPage(); });
    sources.value = ^NSString *{
        // The first one asked and how many follow it, short enough to sit beside the title.
        NSArray<NSString *> *order = SGLyricsOrder();
        if (!order.count) return SGLocalized(@"Off");
        NSString *first = SGLyricsProviderFor(order.firstObject).name;
        return order.count == 1 ? first : [NSString stringWithFormat:@"%@ +%lu", first, (unsigned long)order.count - 1];
    };
    SGModRow *imported = SGPageRow(SGLocalized(@"Imported LRC files"), ^UIViewController *{ return SGImportedLRCPage(); });
    imported.value = ^NSString *{
        NSUInteger count = SGImportedLRCFiles().count;
        return count ? @(count).stringValue : SGLocalized(@"None");
    };
    SGModRow *words = SGOptionRow(SGLocalized(@"Prefer word-by-word timing"), SGLocalized(@"Asks down the order past lines timed by the line"), SGKeyLyricsPreferWordTiming);
    NSMutableArray<SGModRow *> *rows = [NSMutableArray arrayWithObjects:sources, words, imported,
        SGSwitchRow(SGLocalized(@"Lyrics for every track"), SGLocalized(@"Even where Spotify has none"), SGKeyLyricsAllTracks), SGSpicyLyricsKeyRow(), nil];
    // Spicy Lyrics' terms ask for its credit wherever its lines show (Shared/LyricsSources/SpicyLyrics.m), so the switch
    // says so, or its credit under the lyrics reads as the switch not working (issue #20).
    if (namingSource) [rows addObject:SGOptionRow(SGLocalized(@"Show source"), SGLocalized(@"Spicy Lyrics is always credited after the last line: its terms ask for it"), SGKeyLyricsCredit)];
    if (SGEeveeLyricsOn()) {
        [rows addObject:SGOptionRow(SGLocalized(@"Use these sources anyway"), SGLocalized(@"Only if EeveeSpotify's lyrics are really off"), SGKeyLyricsBesideEevee)];
        return SGNotedSection(SGLocalized(@"Sources"), rows, SGLocalized(@"EeveeSpotify's lyrics are on, so it answers Spotify's lyrics and these sources stay "
                                                @"off: both answering froze Spotify after launch. Turn its lyrics off in its own "
                                                @"settings to use these."));
    }
    return SGSection(SGLocalized(@"Sources"), rows);
}

SGModRow *SGLockScreenLyricsRow(void) {
    return SGOptionRow(SGLocalized(@"Lock screen lyrics"), SGLocalized(@"Current line in place of the artist"), SGKeyLockScreenLyrics);
}

SGModRow *SGLockScreenTranslationRow(void) {
    SGModRow *row = SGOptionRow(SGLocalized(@"Lock screen translation"), SGLocalized(@"The line's translation in its place, when the lyrics have one"), SGKeyLockScreenTranslation);
    row.waitsOn = SGKeyLockScreenLyrics;
    return row;
}

SGModRow *SGLyricsTranslationLanguageRow(void) {
    SGModRow *row = SGChoiceRow(SGLocalized(@"Translation language"), nil, SGKeyLyricsTranslationLanguage, SGLyricsTranslationLanguageNames(), 0);
    row.choiceFooter = SGLocalized(@"A language brings Musixmatch's community translations to lyrics that have none, "
                       @"which sends Musixmatch each song's ID. Any shows the first translation the lyrics come with. "
                       @"It is also the language the lyrics' translate menu translates into, offered only for songs in another one; "
                       @"with Any, the iPhone's own language.");
    return row;
}

// Only the redesign's lyrics view draws it, and every one there is redrawn as the switch flips.
SGModRow *SGLyricsRomanisedRow(void) {
    SGModRow *row = SGOptionRow(SGLocalized(@"Romanized lyrics"), SGLocalized(@"Lines in other alphabets, again in Latin letters"), SGKeyLyricsRomanised);
    row.changed = ^(BOOL on) {
        [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsRomanisedDidChangeNotification object:nil];
    };
    return row;
}

SGModRow *SGLyricsRomanisedReplaceRow(void) {
    SGModRow *row = SGOptionRow(SGLocalized(@"In place of original"), SGLocalized(@"Show the Latin letters instead of the original script"), SGKeyLyricsRomanisedReplace);
    row.waitsOn = SGKeyLyricsRomanised;
    row.changed = ^(BOOL on) {
        [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsRomanisedDidChangeNotification object:nil];
    };
    return row;
}

// Only the redesign's lyrics view sweeps words.
SGModRow *SGLyricsWordTimingRow(void) {
    return SGOptionRow(SGLocalized(@"Simulate word timing"), nil, SGKeyLyricsSimulateWords);
}

// Read wherever lines are timed, so it applies as the thumb moves.
SGModRow *SGLyricsDelayRow(void) {
    return SGSliderRow(SGLocalized(@"Delay"), nil, 0, 1000, 25, ^double { return SGKaraokeDelayMs(); },
                       ^(double value) { SGSetInt(SGKeyLyricsDelay, lround(value)); },
                       ^NSString *(double value) { return [NSString stringWithFormat:@"%ld ms", lround(value)]; });
}
