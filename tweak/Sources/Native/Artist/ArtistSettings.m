#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Artist.h"

UIViewController *SGArtistSettingsPage(void) {
    NSArray<SGModSection *> *sections = @[
        SGSection(SGLocalized(@"Photo"), @[
            SGOptionRow(SGLocalized(@"Fade into a blur"), nil, SGKeyArtistPhotoFade),
        ]),
        SGSection(SGLocalized(@"Hide in the header"), @[
            SGHideRow(SGLocalized(@"Explore (video deck)"), nil, SGHideArtistExplore),
            SGHideRow(SGLocalized(@"Follow"), nil, SGHideArtistFollow),
            SGHideRow(SGLocalized(@"More options"), nil, SGHideArtistMore),
            SGHideRow(SGLocalized(@"Shuffle"), nil, SGHideArtistShuffle),
            SGHideRow(SGLocalized(@"Verified badge"), nil, SGHideArtistVerified),
            SGHideRow(SGLocalized(@"Monthly listeners"), nil, SGHideArtistListeners),
        ]),
        SGSection(SGLocalized(@"Tabs"), @[
            SGHideRow(SGLocalized(@"Hide the tab bar"), nil, SGHideArtistTabBar),
        ]),
        SGNotedSection(SGLocalized(@"Hide on the page"), @[
            SGHideRow(SGLocalized(@"Songs you liked"), nil, SGHideArtistLikedSongs),
            SGHideRow(SGLocalized(@"Popular"), nil, SGHideArtistPopular),
            SGHideRow(SGLocalized(@"Artist pick"), nil, SGHideArtistPick),
            SGHideRow(SGLocalized(@"Popular releases"), nil, SGHideArtistReleases),
            SGHideRow(SGLocalized(@"Featuring"), nil, SGHideArtistFeaturing),
            SGHideRow(SGLocalized(@"Music videos"), nil, SGHideArtistVideos),
            SGHideRow(SGLocalized(@"About"), nil, SGHideArtistAbout),
            SGHideRow(SGLocalized(@"Artist playlists"), nil, SGHideArtistPlaylists),
            SGHideRow(SGLocalized(@"Fans also like"), nil, SGHideArtistFansAlsoLike),
            SGHideRow(SGLocalized(@"Appears on"), nil, SGHideArtistAppearsOn),
            SGHideRow(SGLocalized(@"Discovered on"), nil, SGHideArtistDiscoveredOn),
        ], SGLocalized(@"Works only with Spotify in English.")),
        SGSection(SGLocalized(@"Spotify's own"), @[
            SGFlagRow(SGLocalized(@"Share button in the header"), @"ios-creator-impl.share_in_action_row_enabled_artist"),
            SGFlagRow(SGLocalized(@"More options in the navigation bar"), @"ios-creator-impl.context_menu_in_navigation_bar_enabled_artist"),
            SGFlagRow(SGLocalized(@"Top collaborators"), @"ios-creator-impl.is_top_collaborators_enabled"),
            SGFlagRow(SGLocalized(@"Artist facts"), @"ios-creator-impl.is_artist_facts_enabled"),
        ]),
    ];
    return [[SGModPage alloc] initWithTitle:SGLocalized(@"Artist") intro:nil sections:sections footer:nil];
}
