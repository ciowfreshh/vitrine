#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "AdBlock.h"
#import "Shared/Privacy/Privacy.h"

NSString *const SGFakePremiumWarning = @"This is the part of EeveeSpotify Spotify's takedown went after, and it has not been tested here. It can end in a forced logout or worse for the account. A Premium account gains nothing from it.";

// Every switch here forces a flag Spotify ships on to off, so the titles name the blocking: on stops
// the thing, off is Spotify's own value. Hide ads and Hide upsells already force the first two
// sections off, which locks those rows.
static UIViewController *adFlagsPage(void) {
    return [[SGModPage alloc] initWithTitle:SGLocalized(@"Ad and upsell flags") intro:SGLocalized(SGRestartNote) sections:@[
        SGNotedSection(SGLocalized(@"Ads"), @[
            SGKillRow(SGLocalized(@"Block the ad when the app opens"), @"ios-feature-adonappopen.enabled"),
            SGKillRow(SGLocalized(@"Block its CTA card"), @"ios-feature-adonappopen.cta_card_enabled"),
        ], SGLocalized(@"Locked while Hide ads is on.")),
        SGNotedSection(SGLocalized(@"Upsells"), @[
            SGKillRow(SGLocalized(@"Hide the shuffle toggle upsell"), @"ios-feature-shuffletoggleupsell.is_enabled_pt2"),
            SGKillRow(SGLocalized(@"Hide the shuffle upsell in the video player"), @"ios-feature-nowplaying-modes.video_first_shuffle_upsell_enabled"),
        ], SGLocalized(@"Locked while Hide upsells is on.")),
        SGSection(SGLocalized(@"Reduce interventions"), @[
            SGFlagRow(SGLocalized(@"Reduce interventions"), @"ios-messaging-reduceinterventions-impl.enabled"),
        ]),
        SGSection(SGLocalized(@"Tooltips"), @[
            SGKillRow(SGLocalized(@"Hide the smart shuffle helper"), @"ios-messaging-reduceinterventions-impl.enable_message_smart_shuffle_helper_tooltip"),
            SGKillRow(SGLocalized(@"Hide the data saver tip"), @"ios-feature-nowplayingbar.data_saver_tooltip"),
            SGKillRow(SGLocalized(@"Hide the player suggestions upsell"), @"ios-messaging-reduceinterventions-impl.enable_message_reinvent_free_n_p_v_suggestions_upsell"),
            SGKillRow(SGLocalized(@"Hide the AI playlist creation tip"), @"ios-messaging-reduceinterventions-impl.enable_message_your_library_ai_playlist_creation_tooltip"),
            SGKillRow(SGLocalized(@"Hide the watch feed explorer tip"), @"ios-messaging-reduceinterventions-impl.enable_message_watch_feed_entity_explorer_tooltip"),
            SGKillRow(SGLocalized(@"Hide the account switching tip"), @"ios-messaging-reduceinterventions-impl.enable_message_account_switching_tooltip"),
            SGKillRow(SGLocalized(@"Hide the concert notifications tip"), @"ios-messaging-reduceinterventions-impl.enable_message_live_events_concert_notifications_tooltip"),
            SGKillRow(SGLocalized(@"Hide the live event tip"), @"ios-messaging-reduceinterventions-impl.enable_message_live_events_event_entity_safe_tooltip"),
            SGKillRow(SGLocalized(@"Hide the live event venue tip"), @"ios-messaging-reduceinterventions-impl.enable_message_live_events_event_entity_venuename_header_tooltip"),
            SGKillRow(SGLocalized(@"Hide the Puffin nudge"), @"ios-messaging-reduceinterventions-impl.enable_message_puffin_nudge_end_optimization"),
        ]),
    ] footer:nil];
}

// The switches first and what they have stopped last, so the counters bury no setting.
UIViewController *SGAdsSettingsPage(void) {
    NSMutableArray<SGModRow *> *counts = [NSMutableArray array];
    for (NSString *label in SGAdBlockLabels()) {
        [counts addObject:SGStatRow(SGLocalized(label), ^NSString *{
            NSUInteger checked = SGAdBlockChecked(label);
            return checked == NSNotFound ? @(SGAdBlockCount(label)).stringValue
                : [NSString stringWithFormat:SGLocalized(@"%lu of %lu"), (unsigned long)SGAdBlockCount(label), (unsigned long)checked];
        })];
    }
    [counts addObject:SGStatRow(SGLocalized(@"Total"), ^NSString *{
        return @(SGAdBlockCount(nil)).stringValue;
    })];
    [counts addObject:SGActionRow(SGLocalized(@"Reset the counters"), nil, ^{ SGResetAdBlock(); })];

    SGModRow *fakePremium = SGOptionRow(SGLocalized(@"Spoof Premium"), nil, SGKeyFakePremium);
    fakePremium.warning = SGLocalized(SGFakePremiumWarning);

    // The redesign's Search keeps only its category cards, so the video carousel switch is the native look's.
    NSMutableArray<SGModRow *> *ads = [NSMutableArray arrayWithObjects:
        SGWithSymbol(SGOptionRow(SGLocalized(@"Hide ads"), nil, SGKeyHideAds), @"speaker.slash"),
        SGWithSymbol(SGOptionRow(SGLocalized(@"Hide upsells"), nil, SGKeyHideUpsells), @"hand.raised"), nil];
    if (!SGRedesignedUIStored()) [ads addObject:SGWithSymbol(SGOptionRow(SGLocalized(@"Hide the video carousel in Search"), nil, SGKeyHideSearchVideos), @"play.rectangle.on.rectangle")];
    [ads addObject:SGWithSymbol(SGPageRow(SGLocalized(@"Ad and upsell flags"), ^UIViewController *{ return adFlagsPage(); }), @"flag")];

    return [[SGModPage alloc] initWithTitle:SGLocalized(@"Premium, ads & privacy") intro:SGLocalized(SGRestartNote) sections:@[
        SGNotedSection(SGLocalized(@"Ads"), ads, SGLocalized(@"Audio ads between songs need Spoof Premium.")),
        SGNotedSection(@"Premium", @[
            SGWithSymbol(fakePremium, @"crown"),
        ], SGLocalized(@"Free accounts only.")),
        SGPrivacySection(),
        SGNotedSection(SGLocalized(@"Ads blocked so far"), counts,
                       SGLocalized(@"\"3 of 214\" is 3 stopped of 214 checked. 0 of 0 means Spotify never asked, so that part does nothing on this version.")),
        SGPrivacyCountersSection(),
    ] footer:nil];
}
