// The native player's settings: Spotify's own player screen and the parts of it to hide, and the queue
// and devices flags. The Player page that holds them is App/Pages.m's.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "NowPlaying.h"

NSArray<SGModSection *> *SGNativePlayerScreenSections(void) {
    return @[
        SGSection(SGLocalized(@"Player screen"), @[
            SGOptionRow(SGLocalized(@"Artwork background"), nil, SGKeyPlayerBackdrop),
            SGOptionRow(SGLocalized(@"Glass header buttons"), nil, SGKeyPlayer),
            SGKillRow(SGLocalized(@"Disable Canvas"), @"ios-feature-canvas.canvas_enabled"),
            SGFlagRow(SGLocalized(@"Sheet style player"), @"ios-feature-nowplaying.sheet_style_npv"),
            SGFlagRow(SGLocalized(@"Redesigned header"), @"ios-feature-nowplaying.new_redesign_header_with_context_menu_enabled"),
            SGFlagRow(SGLocalized(@"New progress slider"), @"ios-feature-encoreexperiments.new_npv_slider_enabled"),
            SGFlagRow(SGLocalized(@"Expand the sticky header on tap"), @"ios-feature-nowplaying.expand_sticky_header_on_tap"),
        ]),
        SGSection(SGLocalized(@"Hide cards below the player"), @[
            SGHideRow(SGLocalized(@"Lyrics"), nil, SGHideLyricsCard),
            SGHideRow(SGLocalized(@"About the artist"), nil, SGHideAboutArtist),
            SGHideRow(SGLocalized(@"Related videos"), nil, SGHideRelatedVideos),
            SGHideRow(@"SongDNA", nil, SGHideSongDNA),
            SGHideRow(SGLocalized(@"Live events"), nil, SGHideLiveEvents),
            SGHideRow(SGLocalized(@"Explore the artist"), nil, SGHideExploreArtist),
            SGHideRow(SGLocalized(@"Credits"), nil, SGHideCredits),
            SGHideRow(SGLocalized(@"Merch"), nil, SGHideMerch),
            SGHideRow(SGLocalized(@"Recommendations"), nil, SGHideRecommendations),
        ]),
        SGSection(SGLocalized(@"Hide on the player"), @[
            SGHideRow(SGLocalized(@"Lyrics preview"), nil, SGHideLyricsInline),
            SGHideRow(SGLocalized(@"Shuffle"), nil, SGHideShuffle),
            SGHideRow(SGLocalized(@"Repeat"), nil, SGHideRepeat),
            SGHideRow(SGLocalized(@"Add to playlist"), nil, SGHideAddTo),
            SGHideRow(SGLocalized(@"Queue"), nil, SGHideQueue),
            SGHideRow(SGLocalized(@"Share"), nil, SGHideShare),
            SGHideRow(SGLocalized(@"Connect to a device"), nil, SGHideConnect),
        ]),
    ];
}

SGModRow *SGGlassLyricsRow(void) {
    return SGOptionRow(SGLocalized(@"Glass lyrics"), nil, SGKeyLyricsCard);
}

UIViewController *SGQueueSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:SGLocalized(@"Queue & devices") intro:SGLocalized(SGRestartNote) sections:@[
        SGSection(SGLocalized(@"Bottom sheets"), @[
            SGFlagRow(SGLocalized(@"Queue as a bottom sheet"), @"ios-feature-nowplaying.bottom_sheet_queue_enabled"),
            SGFlagRow(SGLocalized(@"Connect as a bottom sheet"), @"ios-feature-nowplaying-elements.enable_connect_bottom_sheet"),
            SGFlagRow(SGLocalized(@"Connect sheet from the video switcher"), @"ios-playbackcontrol-audiovideoswitcher-impl.enable_connect_bottom_sheet"),
        ]),
        SGSection(SGLocalized(@"Queue"), @[
            SGFlagRow(SGLocalized(@"Queue flip transition"), @"ios-feature-nowplaying.queue_flip_transition_enabled"),
            SGFlagRow(SGLocalized(@"Play next in the context menu"), @"ios-feature-queue.is_play_next_context_menu_enabled"),
        ]),
    ] footer:nil];
}
