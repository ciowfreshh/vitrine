#import "Core/SGLocalization.h"
#import "Settings/SGModPage.h"
#import "Playlist.h"

UIViewController *SGPlaylistSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:SGLocalized(@"Playlists") intro:nil sections:@[
        SGSection(SGLocalized(@"Header"), @[
            SGOptionRow(SGLocalized(@"Artwork background"), nil, SGKeyPlaylistBackdrop),
        ]),
        SGSection(SGLocalized(@"Hide in the playlist header"), @[
            SGHideRow(SGLocalized(@"Cover artwork"), nil, SGHidePlaylistArtwork),
            SGHideRow(SGLocalized(@"Description"), nil, SGHidePlaylistDescription),
            SGHideRow(SGLocalized(@"Creator and collaborators"), nil, SGHidePlaylistCreator),
            SGHideRow(SGLocalized(@"Length and saves"), nil, SGHidePlaylistLength),
        ]),
        SGSection(SGLocalized(@"Hide playlist buttons"), @[
            SGHideRow(@"Video", nil, SGHidePlaylistVideo),
            SGHideRow(SGLocalized(@"Add to library"), nil, SGHidePlaylistAddTo),
            SGHideRow(SGLocalized(@"Download"), nil, SGHidePlaylistDownload),
            SGHideRow(SGLocalized(@"Share"), nil, SGHidePlaylistShare),
            SGHideRow(SGLocalized(@"More"), nil, SGHidePlaylistMore),
        ]),
        SGSection(SGLocalized(@"Hide above the tracks"), @[
            SGHideRow(SGLocalized(@"Curation pills"), nil, SGHidePlaylistPills),
            SGHideRow(SGLocalized(@"Find and sort bar"), nil, SGHidePlaylistFind),
        ]),
    ] footer:nil];
}
