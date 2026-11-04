#import "Core/SGCore.h"
#import "Core/SGSYNA.h"
#import "Settings/SGPageStyle.h"
#import "Onboarding.h"
#import "App/About/About.h"
#import "App/Pages.h"
#import "Shared/AdBlock/AdBlock.h"

static const CGFloat kMargin = 24;
static const CGFloat kCardRadius = 22;

#pragma mark - glass

// A view whose glass pane follows its bounds; the panes in SGGlass.m are laid out by their hosts.
@interface SGGlassView : UIView
@property (nonatomic) CGFloat radius;
@property (nonatomic) BOOL capsule;
@end

@implementation SGGlassView
static char kPaneKey;
- (void)layoutSubviews {
    [super layoutSubviews];
    UIVisualEffectView *pane = SGGlassFor(self, &kPaneKey);
    pane.frame = self.bounds;
    SGShapeGlass(pane, self.radius, self.capsule);
}
@end

UIButton *SGOnboardingButton(NSString *title) {
    UIButtonConfiguration *config;
    if (@available(iOS 26.0, *)) config = [UIButtonConfiguration prominentGlassButtonConfiguration];
    else config = [UIButtonConfiguration filledButtonConfiguration];
    config.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    config.baseBackgroundColor = [UIColor colorWithRed:0.21 green:1 blue:0.36 alpha:1];
    config.baseForegroundColor = UIColor.blackColor;
    config.contentInsets = NSDirectionalEdgeInsetsMake(15, 20, 15, 20);
    config.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]}];
    UIButton *button = [UIButton buttonWithConfiguration:config primaryAction:nil];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    return button;
}

#pragma mark - the choice

// A card's row: a symbol on a dim square, a name over a line of small gray text, and an accessory at the end.
static UIStackView *cardRow(NSString *symbol, NSString *title, NSString *subtitle, UIView *accessory) {
    UIImageView *icon = SGSymbolView(symbol, 17, UIImageSymbolWeightSemibold, 36);
    icon.tintColor = UIColor.whiteColor;
    icon.backgroundColor = [UIColor colorWithWhite:1 alpha:0.10];
    icon.layer.cornerRadius = 10;
    icon.layer.cornerCurve = kCACornerCurveContinuous;

    UILabel *name = [UILabel new];
    name.text = title;
    name.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    name.textColor = UIColor.whiteColor;
    UILabel *line = [UILabel new];
    line.text = subtitle;
    line.font = [UIFont systemFontOfSize:13];
    line.textColor = SGGrey();
    line.numberOfLines = 0;
    UIStackView *text = [[UIStackView alloc] initWithArrangedSubviews:@[name, line]];
    text.axis = UILayoutConstraintAxisVertical;
    text.spacing = 2;

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:accessory ? @[icon, text, accessory] : @[icon, text]];
    row.alignment = accessory ? UIStackViewAlignmentCenter : UIStackViewAlignmentTop;
    row.spacing = 14;
    [text setContentHuggingPriority:UILayoutPriorityDefaultLow - 1 forAxis:UILayoutConstraintAxisHorizontal];
    [text setContentCompressionResistancePriority:UILayoutPriorityDefaultHigh - 1 forAxis:UILayoutConstraintAxisHorizontal];
    [NSLayoutConstraint activateConstraints:@[
        [icon.widthAnchor constraintEqualToConstant:36],
        [icon.heightAnchor constraintEqualToConstant:36],
    ]];
    return row;
}

// A glass card of rows, in the look cards' shape, that only points somewhere: the tips at the end of the tour.
static UIView *tipsCard(NSArray<UIView *> *rows) {
    SGGlassView *card = [SGGlassView new];
    card.radius = kCardRadius;
    card.clipsToBounds = YES;
    card.layer.cornerRadius = kCardRadius;
    card.layer.cornerCurve = kCACornerCurveContinuous;
    UIStackView *column = [[UIStackView alloc] initWithArrangedSubviews:rows];
    column.axis = UILayoutConstraintAxisVertical;
    column.spacing = 16;
    column.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:column];
    [NSLayoutConstraint activateConstraints:@[
        [column.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16],
        [column.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16],
        [column.topAnchor constraintEqualToAnchor:card.topAnchor constant:16],
        [column.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16],
    ]];
    return card;
}

// One of the two looks, as a glass card: symbol, name, a line on what it brings, and a check
// when it is the one picked. With an accessory instead, the card is a row for it (the ads switch).
@interface SGLookCard : UIControl
- (instancetype)initWithSymbol:(NSString *)symbol title:(NSString *)title subtitle:(NSString *)subtitle;
- (instancetype)initWithSymbol:(NSString *)symbol title:(NSString *)title subtitle:(NSString *)subtitle accessory:(UIView *)accessory;
@end

@implementation SGLookCard {
    SGGlassView *_glass;
    UIImageView *_check;
}

- (instancetype)initWithSymbol:(NSString *)symbol title:(NSString *)title subtitle:(NSString *)subtitle {
    return [self initWithSymbol:symbol title:title subtitle:subtitle accessory:nil];
}

- (instancetype)initWithSymbol:(NSString *)symbol title:(NSString *)title subtitle:(NSString *)subtitle accessory:(UIView *)accessory {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    if (!accessory) _check = SGSymbolView(@"circle", 22, UIImageSymbolWeightRegular, 26);
    UIStackView *row = cardRow(symbol, title, subtitle, accessory ?: _check);
    row.userInteractionEnabled = NO;
    row.translatesAutoresizingMaskIntoConstraints = NO;

    _glass = [SGGlassView new];
    _glass.radius = kCardRadius;
    _glass.userInteractionEnabled = NO;
    _glass.translatesAutoresizingMaskIntoConstraints = NO;
    self.clipsToBounds = YES;
    self.layer.cornerRadius = kCardRadius;
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.borderColor = [UIColor colorWithRed:0.21 green:1 blue:0.36 alpha:1].CGColor;
    [self addSubview:_glass];
    [self addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [_glass.topAnchor constraintEqualToAnchor:self.topAnchor],
        [_glass.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [_glass.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [_glass.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [row.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [row.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [row.topAnchor constraintEqualToAnchor:self.topAnchor constant:16],
        [row.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-16],
    ]];
    return self;
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    _check.image = [UIImage systemImageNamed:selected ? @"checkmark.circle.fill" : @"circle"
                           withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightRegular]];
    _check.tintColor = selected ? [UIColor colorWithRed:0.21 green:1 blue:0.36 alpha:1] : SGGrey();
    self.layer.borderWidth = selected ? 2 : 0.7;
    self.backgroundColor = selected ? [UIColor colorWithRed:0.03 green:0.16 blue:0.07 alpha:0.7]
                                    : [UIColor colorWithWhite:0.12 alpha:0.55];
}

- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.6 : 1;
}

@end

#pragma mark - the logo

// Vector traced from the user's SYNA organic brand mark. Used ONLY on the onboarding page.
@interface SGTourLogo : UIView
- (void)prepare;
- (void)landThen:(void (^)(void))landed;
@end
@implementation SGTourLogo {
    CAShapeLayer *_symbol;
    UILabel *_wordmark;
    UILabel *_domain;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = @"SYNA, syna.lol";
    self.accessibilityTraits = UIAccessibilityTraitImage;
    _symbol = [CAShapeLayer layer];
    _symbol.fillColor = UIColor.whiteColor.CGColor;
    _symbol.fillRule = kCAFillRuleEvenOdd;
    [self.layer addSublayer:_symbol];
    _wordmark = [UILabel new];
    _wordmark.text = @"S Y N A";
    _wordmark.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBlack];
    _wordmark.textColor = UIColor.whiteColor;
    _wordmark.adjustsFontSizeToFitWidth = YES;
    [self addSubview:_wordmark];
    _domain = [UILabel new];
    _domain.text = @"s y n a . l o l";
    _domain.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    _domain.textColor = [UIColor colorWithWhite:0.85 alpha:1];
    [self addSubview:_domain];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat scale = MIN(78.0 / 336.0, (self.bounds.size.height - 8.0) / 310.0);
    const CGFloat outer[][2] = {
        {182,34},{149,35},{131,45},{120,58},{114,74},{114,92},
        {132,134},{133,150},{128,170},{105,200},{54,228},{41,243},
        {35,258},{34,281},{43,306},{62,327},{83,338},{113,342},
        {150,329},{172,308},{203,255},{229,234},{249,228},{266,228},
        {308,247},{332,250},{353,241},{370,216},{370,194},{355,171},
        {336,163},{294,162},{262,144},{236,111},{211,55},{197,41}
    };
    const CGFloat hole[][2] = {
        {199,145},{245,185},{247,201},{240,209},{175,238},{163,237},
        {154,230},{151,222},{161,184},{175,153},{183,146}
    };
    UIBezierPath *shape = [UIBezierPath bezierPath];
    for (NSUInteger n = 0; n < sizeof(outer)/sizeof(outer[0]); n++) {
        CGPoint point = CGPointMake(4 + (outer[n][0]-34)*scale, 4+(outer[n][1]-34)*scale);
        if (n == 0) [shape moveToPoint:point]; else [shape addLineToPoint:point];
    }
    [shape closePath];
    for (NSUInteger n = 0; n < sizeof(hole)/sizeof(hole[0]); n++) {
        CGPoint point = CGPointMake(4 + (hole[n][0]-34)*scale, 4+(hole[n][1]-34)*scale);
        if (n == 0) [shape moveToPoint:point]; else [shape addLineToPoint:point];
    }
    [shape closePath];
    _symbol.path = shape.CGPath;
    _wordmark.frame = CGRectMake(92, 12, MAX(40, self.bounds.size.width-92), 40);
    _domain.frame = CGRectMake(94, 51, MAX(40, self.bounds.size.width-94), 25);
}
- (void)prepare {
    self.alpha = 0;
    if (!UIAccessibilityIsReduceMotionEnabled()) self.transform = CGAffineTransformMakeTranslation(0, 12);
}
- (void)landThen:(void (^)(void))landed {
    BOOL reduce = UIAccessibilityIsReduceMotionEnabled();
    [UIView animateWithDuration:reduce ? 0.20 : 0.55 delay:0
        usingSpringWithDamping:0.86 initialSpringVelocity:0
        options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.alpha = 1;
        self.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) { if (landed) landed(); }];
}
@end

#pragma mark - the tour

// One page, the two choices worth making now under Vitrine's logo: the redesign or Spotify's own look, and
// Spotify without its ads. Everything else waits in Mod Settings; a card of pointers names what people miss there.
@interface SGOnboardingController : UIViewController
@end

// A symbol and a line of small gray text, the note under a card.
static UIStackView *noteLine(UIImageView *icon, UILabel *text) {
    text.font = [UIFont systemFontOfSize:13];
    text.textColor = SGGrey();
    text.numberOfLines = 0;
    [text setContentHuggingPriority:UILayoutPriorityDefaultLow - 1 forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *line = [[UIStackView alloc] initWithArrangedSubviews:@[icon, text]];
    line.alignment = UIStackViewAlignmentTop;
    line.spacing = 10;
    return line;
}

// The three switches at the top of the Premium, ads & privacy page, which the No ads card sets together.
static NSArray<NSString *> *adKeys(void) {
    return @[SGKeyHideAds, SGKeyHideUpsells, SGKeyFakePremium];
}

static BOOL adFree(void) {
    for (NSString *key in adKeys()) if (!SGHidden(key)) return NO;
    return YES;
}

@implementation SGOnboardingController {
    SGTourLogo *_logo;
    SGLookCard *_redesigned, *_legacy, *_adsCard;
    UISwitch *_ads;
    UIStackView *_column;
    UIView *_splitTip;   // the redesign's; the lyrics tip's line changes with the look too
    UILabel *_lyricsTip;
    UIView *_note;
    UIImageView *_noteIcon;
    UILabel *_noteText;
    UIButton *_report;
    UIButton *_primary;
    NSArray<UIView *> *_page;   // what comes in under the logo, in order
    BOOL _landed;
}

- (instancetype)init {
    if (!(self = [super initWithNibName:nil bundle:nil])) return nil;
    self.modalPresentationStyle = UIModalPresentationOverFullScreen;
    self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    // Its text is white, and the glass under it would take the system's appearance, light in light mode.
    SGPresentDark(self);
    return self;
}

// Under the cards: what the picked look leaves out, or below iOS 26 what the redesign risks there.
- (UIView *)noteView {
    _noteIcon = SGSymbolView(@"info.circle.fill", 15, UIImageSymbolWeightSemibold, 22);
    _noteText = [UILabel new];
    UIStackView *line = noteLine(_noteIcon, _noteText);

    UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
    config.contentInsets = NSDirectionalEdgeInsetsMake(4, 32, 4, 0);
    config.baseForegroundColor = SGGreen();
    config.attributedTitle = [[NSAttributedString alloc] initWithString:@"Report a bug" attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]}];
    _report = [UIButton buttonWithConfiguration:config primaryAction:[UIAction actionWithHandler:^(UIAction *action) {
        SGOpenURL([SGRepoURL stringByAppendingString:@"/issues"]);
    }]];
    _report.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;

    UIStackView *note = [[UIStackView alloc] initWithArrangedSubviews:@[line, _report]];
    note.axis = UILayoutConstraintAxisVertical;
    note.alignment = UIStackViewAlignmentLeading;
    note.spacing = 2;
    note.layoutMargins = UIEdgeInsetsMake(4, 4, 0, 4);
    note.layoutMarginsRelativeArrangement = YES;
    return note;
}

// The redesign is the look Vitrine is built around, so picking it needs no note on iOS 26. Legacy is
// told what it goes without; below 26 the redesign is told it is untested, with the way to report it.
- (void)updateNote {
    BOOL untested = _redesigned.selected && !SGRedesignAvailable();
    if (untested) {
        _noteIcon.image = [UIImage systemImageNamed:@"exclamationmark.triangle.fill"];
        _noteIcon.tintColor = UIColor.systemYellowColor;
        _noteText.text = SGRedesignUntestedWarning();
    } else {
        _noteIcon.image = [UIImage systemImageNamed:@"info.circle.fill"];
        _noteIcon.tintColor = SGGrey();
        _noteText.text = @"Apple Music style lyrics, the redesigned player and the glass tab bar come with the redesign only.";
    }
    _report.hidden = !untested || !SGRepoURL;
    _note.hidden = _redesigned.selected && !untested;
    // The ads card stands apart from the look's cards and its note, whichever of those comes last.
    [_column setCustomSpacing:_note.hidden ? 32 : 12 afterView:_legacy];
    // The tips of the picked look: Split Tabs is the redesign's bar's, and the lyrics preview the redesign's page's.
    _splitTip.hidden = !_redesigned.selected;
    _lyricsTip.text = [(_redesigned.selected ? @"A live preview of the look, the sources in order, and lyrics even where Spotify has none."
                                             : @"The sources in order, and lyrics even where Spotify has none.")
                       stringByAppendingString:@"\nMod Settings > Lyrics"];
}

// What people miss in Mod Settings, as pointers only: the tour has no way into a page but holding Home.
- (UIView *)tipsView {
    UIStackView *split = cardRow(@"rectangle.split.2x1", @"Split Tabs",
                                 @"Any tab, Queue for one, on a bar of its own at the trailing end.\nMod Settings > Tab bar > Split Tabs", nil);
    _splitTip = split;
    UIStackView *lyrics = cardRow(@"quote.bubble", @"Lyrics", @"", nil);
    // The row's text stack is its last arranged view, the gray line that stack's; updateNote writes the look's.
    _lyricsTip = (UILabel *)((UIStackView *)lyrics.arrangedSubviews.lastObject).arrangedSubviews.lastObject;
    BOOL liveActivity = NO;
    if (@available(iOS 17.0, *)) liveActivity = YES;
    UIStackView *airPods = cardRow(@"airpods.pro", liveActivity ? @"AirPods gestures, Live Activity" : @"AirPods gestures",
                                   liveActivity ? @"Nod twice or shake your head to control the music, with a chime; and the track on the "
                                                  @"lock screen. Either look.\nMod Settings > AirPods gestures, Live Activity"
                                                : @"Nod twice or shake your head to control the music, with a chime. Either look."
                                                  @"\nMod Settings > AirPods gestures", nil);
    return tipsCard(@[split, lyrics, airPods]);
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.blackColor;

    _logo = [SGTourLogo new];
    _logo.translatesAutoresizingMaskIntoConstraints = NO;
    // The column stretches its children to its width; the logo keeps its square inside a strip.
    UIView *strip = [UIView new];
    [strip addSubview:_logo];

    BOOL glass = SGRedesignAvailable();
    UILabel *heading = [UILabel new];
    heading.text = SGSYNALocalize(@"Pick your look.");
    heading.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
    heading.textColor = UIColor.whiteColor;
    heading.numberOfLines = 0;

    NSString *redesign = glass ? @"Looks like Apple Music. Better lyrics, Live Activity."
                               : [NSString stringWithFormat:@"Looks like Apple Music. Untested on iOS %@.", UIDevice.currentDevice.systemVersion];
    _redesigned = [[SGLookCard alloc] initWithSymbol:@"sparkles" title:SGSYNALocalize(@"Redesigned") subtitle:SGSYNALocalize(redesign)];
    _legacy = [[SGLookCard alloc] initWithSymbol:@"slider.horizontal.3" title:SGSYNALocalize(@"Legacy") subtitle:SGSYNALocalize(@"More options, still looks like Spotify.")];
    for (SGLookCard *card in @[_redesigned, _legacy]) [card addTarget:self action:@selector(picked:) forControlEvents:UIControlEventTouchUpInside];
    // The first launch offers the redesign where it is at home; below iOS 26 it waits to be asked for.
    // The tour again from the Mod page shows the stored look.
    BOOL redesigned = SGFlag(SGKeyOnboardingSeen, NO) ? SGRedesignedUIStored() : glass;
    _redesigned.selected = redesigned;
    _legacy.selected = !redesigned;
    _note = [self noteView];

    // Spotify without its ads: one switch for Hide ads, Hide upsells and Spoof Premium. Off leaves each as it
    // is; the tour again shows on only while all three are. They are read at launch, so on ends in a restart.
    _ads = [UISwitch new];
    _ads.onTintColor = [UIColor colorWithRed:0.21 green:1 blue:0.36 alpha:1];
    _ads.on = adFree();
    _adsCard = [[SGLookCard alloc] initWithSymbol:@"speaker.slash" title:SGSYNALocalize(@"No ads")
                                         subtitle:SGSYNALocalize(@"No ads, no Premium upsells, and Premium spoofed.") accessory:_ads];
    [_adsCard addTarget:self action:@selector(toggleAds) forControlEvents:UIControlEventTouchUpInside];
    _adsCard.isAccessibilityElement = YES;
    _adsCard.accessibilityLabel = @"No ads";
    _adsCard.accessibilityHint = @"No ads, no Premium upsells, and Premium spoofed.";
    _adsCard.accessibilityValue = _ads.on ? @"On" : @"Off";
    if (@available(iOS 17.0, *)) _adsCard.accessibilityTraits = UIAccessibilityTraitToggleButton;
    else _adsCard.accessibilityTraits = UIAccessibilityTraitButton;
    UILabel *adsText = [UILabel new];
    adsText.text = @"Three switches of Premium, ads & privacy, applied at the restart; off leaves each as it is. Spoof Premium is "
                   @"untested and can end in a forced logout; a Premium account gains nothing from it. Offline, audio quality and "
                   @"sessions stay the server's.";
    UIStackView *adsNote = noteLine(SGSymbolView(@"info.circle.fill", 15, UIImageSymbolWeightSemibold, 22), adsText);
    adsNote.arrangedSubviews.firstObject.tintColor = SGGrey();
    adsNote.layoutMargins = UIEdgeInsetsMake(4, 4, 0, 4);
    adsNote.layoutMarginsRelativeArrangement = YES;

    UILabel *tipsHeading = [UILabel new];
    tipsHeading.text = SGSYNALocalize(@"Easy to miss");
    tipsHeading.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    tipsHeading.textColor = UIColor.whiteColor;
    UIView *tips = [self tipsView];

    _column = [[UIStackView alloc] initWithArrangedSubviews:@[strip, heading, _redesigned, _legacy, _note, _adsCard, adsNote, tipsHeading, tips]];
    UIStackView *column = _column;
    column.axis = UILayoutConstraintAxisVertical;
    column.spacing = 12;
    [column setCustomSpacing:28 afterView:strip];
    [column setCustomSpacing:24 afterView:heading];
    [column setCustomSpacing:32 afterView:_note];
    [column setCustomSpacing:32 afterView:adsNote];
    column.translatesAutoresizingMaskIntoConstraints = NO;
    [self updateNote];

    UIScrollView *scroll = [UIScrollView new];
    scroll.alwaysBounceVertical = YES;
    scroll.showsVerticalScrollIndicator = NO;
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:column];
    [self.view addSubview:scroll];

    _primary = SGOnboardingButton(SGSYNALocalize(@"Start listening"));
    [_primary addTarget:self action:@selector(finish) forControlEvents:UIControlEventTouchUpInside];
    UILabel *footer = [UILabel new];
    footer.text = SGSYNALocalize(@"Hold Home to open settings.");
    footer.font = [UIFont systemFontOfSize:13];
    footer.textColor = SGGrey();
    footer.textAlignment = NSTextAlignmentCenter;
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_primary];
    [self.view addSubview:footer];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    UILayoutGuide *frame = scroll.frameLayoutGuide, *content = scroll.contentLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:_primary.topAnchor constant:-12],
        [column.topAnchor constraintEqualToAnchor:content.topAnchor constant:48],
        [column.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-24],
        [column.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:kMargin],
        [column.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-kMargin],
        [column.widthAnchor constraintEqualToAnchor:frame.widthAnchor constant:-2 * kMargin],
        [_logo.leadingAnchor constraintEqualToAnchor:strip.leadingAnchor],
        [_logo.topAnchor constraintEqualToAnchor:strip.topAnchor],
        [_logo.bottomAnchor constraintEqualToAnchor:strip.bottomAnchor],
        [_logo.widthAnchor constraintEqualToConstant:270],
        [_logo.heightAnchor constraintEqualToConstant:92],
        [_primary.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:kMargin],
        [_primary.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-kMargin],
        [_primary.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-12],
        [footer.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:kMargin],
        [footer.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-kMargin],
        [footer.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],
    ]];
    [self refresh];

    // The tour opens on the logo alone; the page waits under it until the reeds land.
    _page = @[heading, _redesigned, _legacy, _note, _adsCard, adsNote, tipsHeading, tips, _primary, footer];
    [_logo prepare];
    BOOL reduce = UIAccessibilityIsReduceMotionEnabled();
    for (UIView *view in _page) {
        view.alpha = 0;
        if (!reduce) view.transform = CGAffineTransformMakeTranslation(0, 16);
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_landed) return;
    _landed = YES;
    NSArray<UIView *> *page = _page;
    [_logo landThen:^{
        // A strong ease out, critically damped, 40 ms between the parts. Under Reduce Motion the page
        // only fades, as nothing was moved out of place.
        for (NSUInteger i = 0; i < page.count; i++) {
            UIViewPropertyAnimator *animator = [[UIViewPropertyAnimator alloc] initWithDuration:0.45 dampingRatio:1 animations:^{
                page[i].alpha = 1;
                page[i].transform = CGAffineTransformIdentity;
            }];
            [animator startAnimationAfterDelay:i * 0.04];
        }
    }];
}

- (void)picked:(SGLookCard *)card {
    _redesigned.selected = card == _redesigned;
    _legacy.selected = card == _legacy;
    [UIView animateWithDuration:0.25 animations:^{
        [self updateNote];
        self->_note.alpha = self->_note.hidden ? 0 : 1;
        [self.view layoutIfNeeded];
    }];
    [self refresh];
}

- (void)toggleAds {
    [_ads setOn:!_ads.on animated:YES];
    _adsCard.accessibilityValue = _ads.on ? @"On" : @"Off";
    [self refresh];
}

// The look and the ad switches are read at launch, so a choice that differs from the running one ends the
// tour in a restart.
- (BOOL)needsRestart {
    return _redesigned.selected != SGRedesignedUI() || (_ads.on && !adFree());
}

- (void)refresh {
    UIButtonConfiguration *config = _primary.configuration;
    NSString *title = SGSYNALocalize(self.needsRestart ? @"Restart Spotify" : @"Start listening");
    config.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{NSFontAttributeName: [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold]}];
    _primary.configuration = config;
}

// Below iOS 26 the note above the button has said what the redesign risks there, so picking it and
// going on is the warning accepted (SGSetRedesignedUI stores that).
- (void)finish {
    SGSetEnabled(SGKeyOnboardingSeen, YES);
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:SGKeySYNAWelcomeSeen];
    SGSetRedesignedUI(_redesigned.selected);
    if (_ads.on) for (NSString *key in adKeys()) SGSetEnabled(key, YES);
    if (self.needsRestart) {
        SGRestartSpotify();
        return;
    }
    [self dismissViewControllerAnimated:YES completion:^{ SGShowSigningFixIfPending(); }];
}

@end

#pragma mark - entry

static __weak SGOnboardingController *sg_tour;

BOOL SGOnboardingShowing(void) {
    return sg_tour != nil || SGWhatsNewShowing();
}

void SGShowOnboarding(void) {
    if (sg_tour) return;
    UIViewController *top = SGTopController();
    // Presenting from an alert lands nowhere; the tour waits for it to go.
    if (!top || [top isKindOfClass:UIAlertController.class]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ SGShowOnboarding(); });
        return;
    }
    SGOnboardingController *tour = [SGOnboardingController new];
    sg_tour = tour;
    [top presentViewController:tour animated:YES completion:nil];
}
