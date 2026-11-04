// The Live Activity page (App/ModSettings.x links it from the root, under either look): the preview at its top
// (SGLiveActivityPreview.m), then the switch, the view and the card's options, which the tick reads, so they
// apply at once to a card that is showing.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "Shared/Player/SleepTimer.h"
#import "LiveActivity.h"
#import "SGLiveActivityPreview.h"

static NSArray<NSString *> *viewNames(void) {
    return @[SGLocalized(@"Lyrics"), SGLocalized(@"Queue"), SGLocalized(@"Control menu")];
}

@interface SGLiveActivityPage : SGModPage
@property (nonatomic, strong) SGLiveActivityPreview *preview;
@end

@implementation SGLiveActivityPage

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.tableHeaderView = self.preview;
}

// Handed back to the table only when its size changes (SGFitNote's way: the table lays out again on every handing back).
- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    UITableView *table = self.tableView;
    CGFloat width = table.bounds.size.width;
    self.preview.layoutMargins = UIEdgeInsetsMake(0, table.layoutMargins.left, 0, table.layoutMargins.right);
    CGSize size = CGSizeMake(width, [self.preview heightForWidth:width]);
    if (CGSizeEqualToSize(self.preview.bounds.size, size)) return;
    self.preview.frame = (CGRect){CGPointZero, size};
    table.tableHeaderView = self.preview;
}

// Back from Shows' or Text size's list, the preview reads them again.
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.preview reload];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    self.preview.running = YES;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.preview.running = NO;
}

@end

// A menu row of `names` stored under `key`, which shows the preview the new choice.
static SGModRow *menuRow(NSString *title, NSString *key, NSArray<NSString *> *names, NSInteger fallback, SGLiveActivityPreview *preview) {
    __weak SGLiveActivityPreview *weakPreview = preview;
    return SGMenuRow(title, names, ^NSString *{
        NSInteger index = SGInt(key, fallback);
        return names[(NSUInteger)(index >= 0 && index < (NSInteger)names.count ? index : fallback)];
    }, ^(NSInteger index) {
        SGSetInt(key, index);
        [weakPreview reload];
    });
}

BOOL SGLiveActivityAllowedByInstall(void) {
    return [[NSBundle.mainBundle objectForInfoDictionaryKey:@"NSSupportsLiveActivities"] boolValue];
}

// At the top while the install lacks the key, saying why nothing shows and what to do.
static SGModRow *missingRow(void) {
    SGModRow *row = SGWarningRow(SGLocalized(@"Missing from this install"), SGLocalized(@"Tap for why"), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGLocalized(@"Live Activity is missing")
            message:SGLocalized(@"iOS shows a Live Activity only for an app that says it has one, and only Vitrine's IPA build writes that into Spotify. This Spotify was put together another way, such as with Vitrine's .deb injected by hand, so iOS turns the card down. Build the IPA with Vitrine to get it.")
            preferredStyle:UIAlertControllerStyleAlert];
        alert.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
        [alert addAction:[UIAlertAction actionWithTitle:SGLocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];
        [SGTopController() presentViewController:alert animated:YES completion:nil];
    });
    row.visible = ^BOOL { return !SGLiveActivityAllowedByInstall(); };
    return row;
}

UIViewController *SGLiveActivitySettingsPage(void) {
    SGLiveActivityPreview *preview = [SGLiveActivityPreview new];
    __weak SGLiveActivityPreview *weakPreview = preview;
    void (^switched)(BOOL) = ^(BOOL on) { [weakPreview reload]; };

    SGModRow *on = SGOptionRow(SGLocalized(@"Live Activity"), nil, SGKeyLiveActivity);
    on.changed = ^(BOOL value) { SGSetLiveActivityEnabled(value); };
    SGModRow *view = SGChoiceRow(SGLocalized(@"Shows"), nil, SGKeyLiveActivityView, viewNames(), SGLiveActivityLyrics);
    // The lyrics view's own rows, shown while it is picked.
    SGModRow *without = menuRow(SGLocalized(@"Without lyrics"), SGKeyLiveActivityWithoutLyrics, @[SGLocalized(@"Note"), SGLocalized(@"Track")], SGLiveActivityWithoutLyricsNote, preview);
    SGModRow *alignment = menuRow(SGLocalized(@"Alignment"), SGKeyLiveActivityAlignment, @[SGLocalized(@"Left"), SGLocalized(@"Center")], SGLiveActivityAlignCenter, preview);
    SGModRow *translation = SGOptionRow(SGLocalized(@"Translations"), SGLocalized(@"Under the line, when the lyrics have one"), SGKeyLiveActivityTranslation);
    translation.changed = switched;
    SGModRow *size = SGChoiceRow(SGLocalized(@"Text size"), nil, SGKeyLiveActivityTextSize, @[SGLocalized(@"Small"), SGLocalized(@"Medium"), SGLocalized(@"Large")], SGLiveActivityTextMedium);
    for (SGModRow *row in @[without, alignment, translation, size]) row.visible = ^BOOL { return SGInt(SGKeyLiveActivityView, SGLiveActivityLyrics) == SGLiveActivityLyrics; };
    // Every view's.
    SGModRow *artwork = SGSwitchRow(SGLocalized(@"Artwork"), SGLocalized(@"The cover beside the track's name and in the Dynamic Island"), SGKeyLiveActivityArtwork);
    artwork.changed = switched;
    SGModRow *colors = menuRow(SGLocalized(@"Colors"), SGKeyLiveActivityColors, @[@"Spotify", SGLocalized(@"Artwork"), SGLocalized(@"Plain")], SGLiveActivityColorsSpotify, preview);
    SGModRow *progress = SGSwitchRow(SGLocalized(@"Progress bar"), nil, SGKeyLiveActivityProgressBar);
    progress.changed = switched;
    // The sleep timer's own: the card's Timer tab, the Sleep Timer shortcut and its control all fade by it, card on or
    // off, and so does Spotify's own timer from the player's menu (Shared/Player/SpotifySleepTimer.m).
    NSArray<NSString *> *fades = SGSleepTimerFadeNames();
    SGModRow *fade = SGMenuRow(SGLocalized(@"Fade out"), fades, ^NSString *{ return fades[(NSUInteger)SGSleepTimerFadeChoice()]; },
                               ^(NSInteger index) { SGSetInt(SGKeySleepTimerFade, index); });
    SGLiveActivityPage *page = [[SGLiveActivityPage alloc] initWithTitle:SGLocalized(@"Live Activity") intro:nil sections:@[
        SGSection(nil, @[missingRow(), on, view, without, alignment, translation, size]),
        SGNotedSection(SGLocalized(@"Card"), @[artwork, colors, progress],
                       SGLocalized(@"Colors: Spotify puts the cover's color behind Spotify's green, Artwork takes the green from the cover too, "
                       @"and Plain is white on the lock screen's own background. "
                       @"The card also shows on a paired Apple Watch, in its Smart Stack, from iOS 18, and in CarPlay from iOS 26, "
                       @"as a smaller card of the line or the track. A tap there opens Spotify on the iPhone.")),
        SGNotedSection(SGLocalized(@"Sleep timer"), @[fade],
                       SGLocalized(@"How long the sound fades before a sleep timer pauses Spotify: the one set from the Timer tab, the Sleep Timer shortcut or Control Center, and Spotify's own from the player's ⋯ menu.")),
    ] footer:nil];
    page.preview = preview;
    return page;
}
