#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "NowPlayingBar.h"

UIViewController *SGNowPlayingBarSettingsPage(void) {
    return [[SGModPage alloc] initWithTitle:SGLocalized(@"Now playing bar") intro:SGLocalized(SGRestartNote) sections:@[
        SGSection(nil, @[
            SGHideRow(SGLocalized(@"Hide the device button"), nil, SGHideBarConnect),
        ]),
        SGSection(SGLocalized(@"Spotify's flags"), @[
            SGFlagRow(SGLocalized(@"Two lines of track info"), @"ios-feature-nowplayingbar.two_lines_information_unit"),
            SGFlagRow(SGLocalized(@"Save button"), @"ios-feature-nowplayingbar.add_button"),
            SGFlagRow(SGLocalized(@"Queue badge"), @"ios-feature-nowplayingbar.queue_badge"),
            SGFlagRow(SGLocalized(@"Hold and drag to resize"), @"ios-feature-nowplayingbar.hold_and_drag_to_resize"),
            SGFlagRow(SGLocalized(@"Video in the mini player"), @"ios-feature-nowplaying.video_in_miniplayer"),
            SGFlagRow(SGLocalized(@"Bar to cover art animation"), @"ios-feature-nowplaying.bartocoverart_animation_enabled"),
            SGFlagRow(SGLocalized(@"Mini player transition animations"), @"ios-feature-nowplaying.miniplayer_transition_animations"),
        ]),
    ] footer:nil];
}
