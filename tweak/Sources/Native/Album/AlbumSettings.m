#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Album.h"

UIViewController *SGAlbumSettingsPage(void) {
    NSArray<SGModSection *> *sections = @[
        SGSection(SGLocalized(@"Header"), @[
            SGOptionRow(SGLocalized(@"Artwork background"), nil, SGKeyAlbumBackdrop),
        ]),
        SGSection(SGLocalized(@"Hide in the header"), @[
            SGHideRow(SGLocalized(@"Explore (video deck)"), nil, SGHideAlbumExplore),
            SGHideRow(SGLocalized(@"Add to library"), nil, SGHideAlbumAddTo),
            SGHideRow(SGLocalized(@"Download"), nil, SGHideAlbumDownload),
            SGHideRow(SGLocalized(@"More options"), nil, SGHideAlbumMore),
        ]),
        SGNotedSection(SGLocalized(@"Hide on the page"), @[
            SGHideRow(SGLocalized(@"More by the artist"), nil, SGHideAlbumMoreBy),
            SGHideRow(SGLocalized(@"Related music videos"), nil, SGHideAlbumVideos),
            SGHideRow(SGLocalized(@"Concerts"), nil, SGHideAlbumConcerts),
            SGHideRow(SGLocalized(@"Merch"), nil, SGHideAlbumMerch),
            SGHideRow(SGLocalized(@"You might also like"), nil, SGHideAlbumYouMightLike),
        ], SGLocalized(@"Works only with Spotify in English.")),
    ];
    return [[SGModPage alloc] initWithTitle:SGLocalized(@"Album") intro:nil sections:sections footer:nil];
}
