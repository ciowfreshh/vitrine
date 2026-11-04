// The now playing bar's rows of the redesign, the Mini player section of the Player page
// (Redesigned/Player/PlayerSettings.m puts them there).
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Redesigned/Navbar/Navbar.h"
#import "NowPlayingBar.h"

NSArray<SGModRow *> *SGRNowPlayingBarRows(void) {
    // The tab bar reads the switch as each scroll goes; a bar minimized when it goes off grows back at once.
    SGModRow *minimize = SGSwitchRow(SGLocalized(@"Apple Music style"), SGLocalized(@"Between two tabs as a page scrolls down"), SGRKeyNavbarMinimize);
    minimize.changed = ^(BOOL on) {
        if (!on) SGRSetTabBarMinimized(NO, NO);
        SGRRefreshTabBar();
    };
    SGModRow *inlineConnect = SGOptionRow(SGLocalized(@"Device button"), SGLocalized(@"Kept on the bar between the tabs"), SGRKeyBarInlineConnect);
    inlineConnect.waitsOn = SGRKeyNavbarMinimize;
    return @[
        minimize,
        inlineConnect,
        SGHideRow(SGLocalized(@"Hide the device button"), SGLocalized(@"On the full now playing bar"), SGRHideBarConnect),
        // Spotify's own flag for the bar's save button, forced off: Spotify leaves the button out.
        SGKillRow(SGLocalized(@"Hide the like button"), @"ios-feature-nowplayingbar.add_button"),
    ];
}
