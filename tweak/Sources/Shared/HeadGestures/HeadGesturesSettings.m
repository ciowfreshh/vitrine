// The AirPods gestures page: the switch, a pull-down of what each gesture does, then fitting them to the
// user: the teaching sheet, the sensitivity, Try it, which listens a few seconds and names what it picked up
// in its own row without doing anything to the song, and Forget.
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
#import "Settings/SGPageStyle.h"
#import "HeadGestures.h"

// Long enough to get the AirPods' attention and make a slow double nod.
static const double kTrySeconds = 6;

// SGHeadAction's names, in its order.
static NSArray<NSString *> *actionNames(void) {
    return @[SGLocalized(@"Nothing"), SGLocalized(@"Back 15 seconds"), SGLocalized(@"Forward 15 seconds"), SGLocalized(@"Play or pause"), SGLocalized(@"Next track"), SGLocalized(@"Previous track"),
             SGLocalized(@"Shuffle"), SGLocalized(@"Repeat"), SGLocalized(@"Like")];
}

static void say(NSString *title, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGLocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

static BOOL headTracking(void) {
    if (SGHeadGesturesAvailable()) return YES;
    say(SGLocalized(@"No head tracking"), SGLocalized(@"This iPhone cannot read the motion of headphones."));
    return NO;
}

static NSString *learnedValue(void) {
    BOOL nod = SGInt(SGKeyHeadNod, 0) > 0, shake = SGInt(SGKeyHeadShake, 0) > 0;
    return nod && shake ? SGLocalized(@"Learned") : nod ? SGLocalized(@"Nod learned") : shake ? SGLocalized(@"Shake learned") : @"";
}

static BOOL anythingLearned(void) {
    return SGInt(SGKeyHeadNod, 0) > 0 || SGInt(SGKeyHeadShake, 0) > 0;
}

// Both learned sizes back to the defaults, asked first; `done` runs once they are.
static void forget(void (^done)(void)) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:SGLocalized(@"Forget your nod and shake?")
        message:SGLocalized(@"Both go back to the default sizes. You can teach them again.") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGLocalized(@"Forget") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        SGSetInt(SGKeyHeadNod, 0);
        SGSetInt(SGKeyHeadShake, 0);
        SGHeadGesturesSettingsChanged();
        done();
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:SGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

static SGModRow *actionRow(NSString *title, SGHeadGesture gesture) {
    return SGMenuRow(title, actionNames(), ^NSString *{ return actionNames()[(NSUInteger)SGHeadGestureAction(gesture)]; },
                     ^(NSInteger index) { SGSetHeadGestureAction(gesture, index); });
}

UIViewController *SGHeadGesturesSettingsPage(void) {
    SGModRow *toggle = SGOptionRow(SGLocalized(@"Head gestures"), SGLocalized(@"Nod twice or shake your head to control the music"), SGKeyHeadGestures);
    toggle.changed = ^(BOOL on) { SGHeadGesturesSettingsChanged(); };

    SGModRow *nodAction = SGWithSymbol(actionRow(SGLocalized(@"Nod twice"), SGHeadGestureDoubleNod), @"arrow.up.and.down");
    SGModRow *shakeAction = SGWithSymbol(actionRow(SGLocalized(@"Shake your head"), SGHeadGestureShake), @"arrow.left.and.right");
    SGModRow *chime = SGWithSymbol(SGSwitchRow(SGLocalized(@"Chime on activation"), nil, SGKeyHeadChime), @"bell");

    __block __weak SGModPage *page;
    SGModRow *teach = SGStatActionRow(SGLocalized(@"Teach your gestures"), SGLocalized(@"Five of each, one after each tone"), ^NSString *{ return learnedValue(); }, ^{
        if (!headTracking()) return;
        SGPresentHeadGesturesTeaching(page, ^{ [page refreshVisibility]; });
    });

    SGModRow *sensitivity = SGSliderRow(SGLocalized(@"Sensitivity"), SGLocalized(@"Higher counts a smaller move"),
        SGHeadSensitivityMin, SGHeadSensitivityMax, SGHeadSensitivityStep,
        ^double { return MAX(SGHeadSensitivityMin, MIN(SGHeadSensitivityMax, SGInt(SGKeyHeadSensitivity, 100))); },
        ^(double value) {
            SGSetInt(SGKeyHeadSensitivity, lround(value));
            SGHeadGesturesSettingsChanged();
        },
        ^NSString *(double value) { return [NSString stringWithFormat:@"%ld%%", lround(value)]; });

    // What the last try picked up, read out on its row until the next; a new page starts blank.
    __block NSString *tried = @"";
    __block BOOL trying = NO;
    SGModRow *tryRow = SGStatActionRow(SGLocalized(@"Try it"), SGLocalized(@"Listens after the tone and says what it picked up"), ^NSString *{ return tried; }, ^{
        if (trying || !headTracking()) return;
        trying = YES;
        tried = SGLocalized(@"Listening…");
        [page.tableView reloadData];
        SGHeadGesturesCue(SGHeadCueReady);
        SGHeadGesturesTry(kTrySeconds, ^(SGHeadGesture gesture, BOOL heard) {
            trying = NO;
            tried = gesture == SGHeadGestureDoubleNod ? SGLocalized(@"Nod twice") : gesture == SGHeadGestureShake ? SGLocalized(@"Head shake") : heard ? SGLocalized(@"Nothing") : SGLocalized(@"No motion");
            SGHeadGesturesCue(gesture != SGHeadGestureNone ? SGHeadCueWorked : SGHeadCueFailed);
            NSString *spoken = gesture != SGHeadGestureNone ? [SGLocalized(@"Picked up: ") stringByAppendingString:tried]
                             : heard ? SGLocalized(@"Picked up nothing. Try a bigger move, or raise Sensitivity.")
                                     : SGLocalized(@"No motion came. Put in AirPods that track head motion.");
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, spoken);
            [page.tableView reloadData];
        });
    });

    SGModRow *forgetRow = SGActionRow(SGLocalized(@"Forget what it learned"), nil, ^{ forget(^{ [page refreshVisibility]; }); });
    forgetRow.color = SGRed();
    forgetRow.visible = ^BOOL { return anythingLearned(); };
    for (SGModRow *row in @[nodAction, shakeAction, chime, teach, sensitivity, tryRow, forgetRow]) row.waitsOn = SGKeyHeadGestures;

    SGModPage *shown = [[SGModPage alloc] initWithTitle:SGLocalized(@"AirPods gestures") intro:nil sections:@[
        SGSection(nil, @[SGWithSymbol(toggle, @"airpods.pro")]),
        SGNotedSection(SGLocalized(@"Gestures"), @[nodAction, shakeAction, chime],
            SGLocalized(@"They work while Spotify plays through headphones that track head motion: AirPods Pro, AirPods (3rd "
            "generation and later), AirPods Max and some Beats. Set to Play or pause, they listen with a song paused too. With the chime on, a "
            "tone in the music confirms each, a rising pair when it worked and a low one when it did not, with the "
            "iPhone on silent too. iOS asks once for Motion & Fitness access, which is how Spotify reads the movement.")),
        SGNotedSection(SGLocalized(@"Fit to you"), @[teach, sensitivity, tryRow, forgetRow],
            SGLocalized(@"Teaching sets how big a move counts from five of your own. Sensitivity scales that for both. Try it does "
            "nothing to the music, so you can tune it while a song plays.")),
    ] footer:nil];
    page = shown;
    return shown;
}
