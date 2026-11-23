#import "Core/SGCore.h"
#import "Settings/SGPageStyle.h"
#import "About.h"
#import "App/Onboarding/Onboarding.h"
#import "Shared/AutoMix/AutoMix.h"
#import "Shared/Lossless/LosslessQuality.h"
#import "Shared/LyricsSources/LyricsSources.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"

// Every key of the mod's is under one prefix, so a reset is a sweep of the defaults with the stock
// marker of SGPrefs.h left behind; the hooks read them at launch, so it ends in a restart.
static void resetAll(void) {
    // Spotify's own settings that AutoMix and Lossless changed go back first, while the keys that hold them are there.
    SGAutoMixApply(NO);
    SGLosslessLowerQuality(NO);
    NSUserDefaults *store = NSUserDefaults.standardUserDefaults;
    NSUInteger removed = 0;
    for (NSString *key in [store persistentDomainForName:NSBundle.mainBundle.bundleIdentifier].allKeys) {
        if (![key hasPrefix:@"spotifyglass."]) continue;
        [store removeObjectForKey:key];
        removed++;
    }
    [store setBool:YES forKey:SGKeyStock];
    SGLog(@"reset: removed %lu keys", (unsigned long)removed);
    SGRestartSpotify();
}

static void confirmReset(void) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Đặt lại tất cả cài đặt?"
                                                                  message:@"Tắt các tùy chọn của Vitrine, xóa cờ đã ghi đè và bố cục thanh thẻ. Spotify sẽ mở lại với cài đặt gốc của Vitrine và giữ cài đặt Spotify của bạn."
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Đặt lại và khởi động lại" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) { resetAll(); }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

// Reset all leaves the Keychain alone, so a key outlives a reset; this takes every item Vitrine keeps there.
static void confirmClearKeychain(void) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Xóa dữ liệu Keychain?"
                                                                  message:@"Xóa khóa Gemini, khóa API tương thích OpenAI, khóa Anthropic, địa chỉ máy chủ tương thích OpenAI và khóa Spicy Lyrics khỏi iPhone này. Các cài đặt khác được giữ lại."
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Xóa dữ liệu Keychain" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        SGAIForgetKeys();
        SGSpicyLyricsForgetKey();
        SGLog(@"reset: keychain cleared");
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [SGTopController() presentViewController:alert animated:YES completion:nil];
}

static SGModRow *withSymbol(SGModRow *row, NSString *symbol) {
    row.symbol = symbol;
    return row;
}

// Which build this is, whether GitHub has a newer release, and where to reach the mod: without these
// rows a build that is already installed has no way of telling its user that anything moved on.
UIViewController *SGAboutPage(void) {
    SGModRow *reset = withSymbol(SGActionRow(@"Reset all settings", nil, ^{ confirmReset(); }), @"trash");
    reset.color = SGRed();
    SGModRow *clearKeys = withSymbol(SGActionRow(@"Clear Keychain", nil, ^{ confirmClearKeychain(); }), @"key");
    clearKeys.color = SGRed();
    NSString *spotify = SGSpotifyVersion();
    if ([SGSpotifyLikelyWorksVersions containsObject:spotify]) spotify = [spotify stringByAppendingString:@", likely works"];
    else if (![SGSpotifySupportedVersions containsObject:spotify]) spotify = [NSString stringWithFormat:@"%@, dành cho %@", spotify, SGSpotifyMadeFor];
    // The row reads out where the build stands and opens the changelog of everything newer than it.
    SGModRow *updates = SGPageRow(@"Updates", ^UIViewController *{ return SGUpdatePage(); });
    updates.value = ^NSString *{ return SGUpdateStatus(); };
    // A release build can opt into betas; a beta build starts opted in. Either way a check follows at
    // once, since the stored list only holds what counted at the last one.
    SGModRow *betas = SGSwitchRow(@"Include betas", @"Offer test builds ahead of each release", SGKeyUpdateBetas);
    betas.defaultOn = SGBuildIsBeta();
    betas.changed = ^(BOOL on) { SGCheckForUpdate(YES); };
    NSMutableArray<SGModRow *> *links = [NSMutableArray array];
    if (SGRepoURL) [links addObject:withSymbol(SGLinkRow(@"GitHub", nil, SGRepoURL), @"chevron.left.forwardslash.chevron.right")];
    [links addObjectsFromArray:@[
        withSymbol(SGPageRow(@"Licenses", ^UIViewController *{ return SGLicensesPage(); }), @"doc.text"),
        withSymbol(SGActionRow(@"Welcome tour", nil, ^{ SGShowOnboarding(); }), @"map"),
    ]];
    if (SGWhatsNewChanges().count) [links insertObject:withSymbol(SGActionRow(@"What's New", nil, ^{ SGShowWhatsNew(); }), @"sparkles") atIndex:links.count - 1];
    NSMutableArray<SGModRow *> *build = [NSMutableArray arrayWithObjects:updates, betas,
        SGStatRow(@"Version", ^NSString *{ return @(SG_VERSION); }),
        SGStatRow(@"Spotify", ^NSString *{ return spotify; }), nil];
    SGModRow *signedUntil = SGSigningExpiryRow();
    if (signedUntil) [build addObject:signedUntil];
    return [[SGModPage alloc] initWithTitle:@"Giới thiệu bản mod" intro:nil sections:@[
        SGSection(nil, build),
        SGSection(nil, links),
        SGSection(nil, @[
            withSymbol(SGActionRow(@"Export settings", nil, ^{ SGExportSettings(); }), @"square.and.arrow.up"),
            withSymbol(SGActionRow(@"Import settings", nil, ^{ SGImportSettings(); }), @"square.and.arrow.down"),
            withSymbol(SGActionRow(@"Share diagnostics", @"For a bug report: versions, ad counts, this launch's log and Spotify's config. Song names can show.",
                                   ^{ SGShareDiagnostics(); }), @"stethoscope"),
        ]),
        SGSection(nil, @[clearKeys, reset]),
    ] footer:nil];
}
