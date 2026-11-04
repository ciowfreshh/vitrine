#import "Core/SGLocalization.h"
// Labs: Spotify's flags for features it built and did not ship; every row forces one flag.
#import "Settings/SGModPage.h"
#import "Flags.h"

static int compareKey(const void *key, const void *def) {
    return strcmp(key, ((const SGFlagDef *)def)->key);
}

// Only the rows for flags this Spotify has: the table comes from the IPA the build is for, and a flag
// it lacks would force nothing. A section left empty goes too.
static NSArray<SGModSection *> *known(NSArray<SGModSection *> *sections) {
    NSMutableArray<SGModSection *> *kept = [NSMutableArray array];
    for (SGModSection *section in sections) {
        NSIndexSet *rows = [section.rows indexesOfObjectsPassingTest:^BOOL(SGModRow *row, NSUInteger i, BOOL *stop) {
            return !row.flag || bsearch(row.key.UTF8String, SGFlagTable, SGFlagCount, sizeof *SGFlagTable, compareKey);
        }];
        if (!rows.count) continue;
        section.rows = [section.rows objectsAtIndexes:rows];
        [kept addObject:section];
    }
    return kept;
}

static UIViewController *martiniPage(void) {
    return [[SGModPage alloc] initWithTitle:@"AI Chat (Martini)" intro:SGLocalized(SGRestartNote) sections:known(@[
        SGSection(SGLocalized(@"On Home"), @[
            SGFlagRow(SGLocalized(@"Chat entry point"), @"ios-home-evopage-impl.interactive_entrypoint_enabled"),
            SGFlagRow(SGLocalized(@"Martini behind it"), @"ios-home-evopage-impl.interactive_entrypoint_martini_enabled"),
            SGFlagRow(SGLocalized(@"Floating chat"), @"ios-home-evopage-impl.interactive_entrypoint_floating_chat_enabled"),
            SGFlagRow(SGLocalized(@"Microphone"), @"ios-home-evopage-impl.interactive_entrypoint_mic_enabled"),
            SGFlagRow(SGLocalized(@"Glowing pill"), @"ios-home-evopage-impl.interactive_entrypoint_pill_glow_enabled"),
        ]),
        SGSection(SGLocalized(@"The chat"), @[
            SGFlagRow(SGLocalized(@"Intent pills"), @"ios-martini-floatingchat-impl.intent_pills_enabled"),
            SGFlagRow(SGLocalized(@"Thinking states"), @"ios-martini-floatingchat-impl.thinking_states_enabled"),
            SGFlagRow(SGLocalized(@"Voice recording"), @"ios-martini-floatingchat-impl.voice_recording_enabled"),
        ]),
        SGSection(SGLocalized(@"In the player"), @[
            SGFlagRow(SGLocalized(@"Chat entry point"), @"ios-martini-npvcardprovider-impl.floating_chat_entry_point_enabled"),
            SGFlagRow(SGLocalized(@"Agent button"), @"ios-martini-npvcardprovider-impl.npv_agent_button_enabled"),
        ]),
    ]) footer:nil];
}

UIViewController *SGLabsPage(void) {
    return [[SGModPage alloc] initWithTitle:SGLocalized(@"Labs") intro:SGLocalized(@"Unreleased features; some do nothing on your version. Changes apply after you restart Spotify.") sections:known(@[
        SGSection(nil, @[
            SGWithSymbol(SGPageRow(@"AI Chat (Martini)", ^UIViewController *{ return martiniPage(); }), @"bubble.left.and.bubble.right"),
        ]),
        SGSection(SGLocalized(@"Library"), @[
            SGFlagRow(SGLocalized(@"Local files from the Files app"), @"ios-feature-localfiles.documents_enabled"),
        ]),
        SGSection(SGLocalized(@"Home screen widget"), @[
            SGFlagRow(SGLocalized(@"Progress bar"), @"ios-widgets-widgetremoteconfig-impl.progress_bar_enabled"),
        ]),
        SGNotedSection(SGLocalized(@"Sleep timer"), @[
            SGFlagRow(SGLocalized(@"Fade out"), @"ios-feature-sleeptimer.enable_fade_out"),
            SGFlagRow(SGLocalized(@"One minute option"), @"ios-feature-sleeptimer.enable_one_minute_option"),
            SGFlagRow(SGLocalized(@"Options sheet"), @"ios-feature-sleeptimer.use_options_sheet"),
        ], SGLocalized(@"Options sheet is always on in Redesigned UI.")),
        SGSection(@"DJ", @[
            SGFlagRow(SGLocalized(@"Auto mix"), @"ios-playlistcuration-mats.auto_mix_enabled_for_dj"),
            SGFlagRow(SGLocalized(@"Auto mix in the context menu"), @"ios-playlistcuration-mats.dj_auto_mix_context_menu_enabled"),
        ]),
        SGSection(SGLocalized(@"Player"), @[
            SGFlagRow(SGLocalized(@"Snake on the cover art"), @"ios-feature-cover-art-snake.enabled"),
        ]),
        SGSection(SGLocalized(@"Podcast comments"), @[
            SGFlagRow(SGLocalized(@"Comments card"), @"ios-feature-comments.enable_comments_card"),
            SGFlagRow(SGLocalized(@"Pinned comments"), @"ios-feature-comments.enable_pinned_comments"),
            SGFlagRow(SGLocalized(@"Several reactions"), @"ios-feature-comments.enable_multi_reactions"),
        ]),
    ]) footer:nil];
}
