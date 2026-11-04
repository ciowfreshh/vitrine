#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Home.h"
#import "Native/Playlist/Playlist.h"
#import "Native/Artist/Artist.h"
#import "Native/Album/Album.h"

static SGModRow *choiceRow(NSString *title, NSString *subtitle, SGHomeChoice choice) {
    return SGChoiceRow(title, subtitle, SGHomeChoiceKey(choice), SGHomeChoiceNames(choice),
                       SGHomeChoiceDefault(choice));
}

UIViewController *SGHomeGradientPage(void) {
    return [[SGModPage alloc] initWithTitle:SGLocalized(@"Gradient")
                                      intro:SGLocalized(@"Turning it on or off applies after you restart Spotify.")
                                   sections:@[
        SGSection(SGLocalized(@"Gradient"), @[
            SGOptionRow(SGLocalized(@"Show"), nil, SGKeyHomeGradient),
            choiceRow(SGLocalized(@"Color"), nil, SGHomeChoiceTint),
            choiceRow(SGLocalized(@"Strength"), nil, SGHomeChoiceStrength),
            choiceRow(SGLocalized(@"Height"), nil, SGHomeChoiceHeight),
        ]),
    ] footer:nil];
}

static UIViewController *libraryPage(void) {
    return [[SGModPage alloc] initWithTitle:SGLocalized(@"Library") intro:nil sections:@[
        SGSection(SGLocalized(@"Library"), @[
            SGFlagRow(SGLocalized(@"Denser rows"), @"ios-feature-yourlibaryx.denser_rows_enabled"),
            SGFlagRow(SGLocalized(@"Sort playlists by recently updated"), @"ios-feature-yourlibaryx.recently_updated_playlists_sort_enabled"),
            SGFlagRow(SGLocalized(@"Sort artists by recently updated"), @"ios-feature-yourlibaryx.recently_updated_artists_sort_enabled"),
            SGFlagRow(SGLocalized(@"Recents"), @"ios-feature-yourlibaryx.recents_enabled"),
            SGFlagRow(SGLocalized(@"Recents sort order"), @"ios-feature-yourlibaryx.recents_sort_order_enabled"),
            SGFlagRow(SGLocalized(@"Library settings"), @"ios-feature-yourlibaryx.library_settings_enabled"),
            SGFlagRow(SGLocalized(@"Library Pro"), @"ios-feature-yourlibaryx.your_library_pro_enabled"),
        ]),
    ] footer:nil];
}

UIViewController *SGHomeSettingsPage(void) {
    // The row reads its own state out, so the section says which color is set without being opened.
    SGModRow *gradient = SGPageRow(SGLocalized(@"Gradient"), ^UIViewController *{ return SGHomeGradientPage(); });
    gradient.value = ^NSString *{
        if (!SGFlag(SGKeyHomeGradient, NO)) return SGLocalized(@"Off");
        return SGHomeChoiceNames(SGHomeChoiceTint)[(NSUInteger)SGHomeChoiceValue(SGHomeChoiceTint)];
    };

    NSArray<SGModSection *> *sections = @[
        SGSection(nil, @[
            SGWithSymbol(SGPageRow(SGLocalized(@"Playlists"), ^UIViewController *{ return SGPlaylistSettingsPage(); }), @"music.note.list"),
            SGWithSymbol(SGPageRow(SGLocalized(@"Library"), ^UIViewController *{ return libraryPage(); }), @"books.vertical"),
            SGWithSymbol(SGPageRow(SGLocalized(@"Album"), ^UIViewController *{ return SGAlbumSettingsPage(); }), @"square.stack"),
            SGWithSymbol(SGPageRow(SGLocalized(@"Artist"), ^UIViewController *{ return SGArtistSettingsPage(); }), @"music.mic"),
        ]),
        SGSection(SGLocalized(@"Home"), @[
            SGWithSymbol(gradient, @"rectangle.tophalf.inset.filled"),
            SGFlagRow(SGLocalized(@"Pull to refresh"), @"ios-home-evopage-impl.pull_to_refresh_enabled"),
        ]),
        SGSection(SGLocalized(@"Hide on Home"), @[
            SGHideRow(SGLocalized(@"Filter pills"), nil, SGHideHomePills),
            SGHideRow(SGLocalized(@"Shortcuts grid"), nil, SGHideHomeShortcuts),
            SGHideRow(SGLocalized(@"Promo cards"), nil, SGHideHomePromo),
            SGHideRow(SGLocalized(@"Preview cards"), nil, SGHideHomePreviews),
            SGHideRow(SGLocalized(@"DJ card"), nil, SGHideHomeDJ),
            SGKillRow(SGLocalized(@"DJ button"), @"ios-home-evopage-impl.idj_show_dj_button"),
            SGKillRow(SGLocalized(@"DJ beta badge"), @"ios-home-evopage-impl.dj_mdc_beta_badge_enabled"),
        ]),
    ];
    return [[SGModPage alloc] initWithTitle:SGLocalized(@"Home & Library") intro:nil sections:sections footer:nil];
}
