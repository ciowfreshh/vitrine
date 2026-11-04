// The redesign's Artists page: Apple Music's logo in place of the name on an artist's page, and what the redesign
// takes off the page.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Artist.h"

UIViewController *SGRArtistSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:SGLocalized(@"Artists") intro:SGLocalized(SGRestartNote) sections:@[
        SGNotedSection(@"Apple Music", @[
            SGSwitchRow(SGLocalized(@"Artist logos"), SGLocalized(@"In place of the name on an artist's page"), SGRKeyArtistLogo),
        ], SGLocalized(@"Only the artist's name is sent to Apple Music.")),
        SGSection(SGLocalized(@"Hide on an artist's page"), @[
            SGSwitchRow(SGLocalized(@"Videos"), SGLocalized(@"In the Music list, and in the Video tab"), SGRKeyArtistHideVideos),
            SGSwitchRow(SGLocalized(@"Music, Video and Merch tabs"), SGLocalized(@"Without them the Music list is the page"), SGRKeyArtistHideTabs),
            SGHideRow(SGLocalized(@"Artist pick"), nil, SGRKeyArtistHidePick),
            SGHideRow(SGLocalized(@"Release countdown"), SGLocalized(@"The pre-save of an upcoming release"), SGRKeyArtistHideCountdown),
            SGHideRow(SGLocalized(@"About"), nil, SGRKeyArtistHideAbout),
        ]),
    ] footer:nil];
}
