// The redesign's Albums page: Apple Music's animated covers on album pages, whether their downloads run in Low
// Data Mode, and what the redesign takes off the page.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Shared/AnimatedArtwork/AnimatedArtwork.h"
#import "Album.h"

UIViewController *SGRAlbumSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:SGLocalized(@"Albums") intro:SGLocalized(SGRestartNote) sections:@[
        SGNotedSection(@"Apple Music", @[
            SGSwitchRow(SGLocalized(@"Animated covers"), SGLocalized(@"At the top of an album that has one, about 5 MB each"), SGRKeyAlbumMotion),
            SGOptionRow(SGLocalized(@"Download in Low Data Mode"), nil, SGKeyMotionLowData),
        ], SGLocalized(@"Only the album's name is sent to Apple Music. A cover stays still in Low Power Mode.")),
        SGSection(SGLocalized(@"Hide on an album's page"), @[
            SGSwitchRow(SGLocalized(@"Repeated track artists"), SGLocalized(@"The artist under a track when it is the album's own"), SGRKeyAlbumHideTrackArtists),
        ]),
        SGNotedSection(SGLocalized(@"Hide under an album's tracks"), @[
            SGSwitchRow(SGLocalized(@"More by the artist"), nil, SGRKeyAlbumHideMoreBy),
            SGSwitchRow(SGLocalized(@"Related music videos"), nil, SGRKeyAlbumHideVideos),
            SGSwitchRow(SGLocalized(@"Concerts"), nil, SGRKeyAlbumHideConcerts),
            SGSwitchRow(SGLocalized(@"Merch"), nil, SGRKeyAlbumHideMerch),
            SGSwitchRow(SGLocalized(@"You might also like"), nil, SGRKeyAlbumHideYouMightLike),
            SGSwitchRow(SGLocalized(@"Everything else"), SGLocalized(@"Any other section Spotify sends"), SGRKeyAlbumHideOther),
        ], SGLocalized(@"Sections are told apart by their English names. With Spotify in another language, Everything else "
           @"covers them all.")),
    ] footer:nil];
}
