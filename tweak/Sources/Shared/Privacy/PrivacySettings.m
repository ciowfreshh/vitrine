#import "Core/SGLocalization.h"
#import "Settings/SGModPage.h"
#import "Privacy.h"

SGModSection *SGPrivacySection(void) {
    return SGSection(SGLocalized(@"Privacy"), @[
        SGWithSymbol(SGSwitchRow(SGLocalized(@"Block telemetry"), SGLocalized(@"Spotify's own events still go out, since Recents is built from them"), SGKeyBlockTelemetry), @"antenna.radiowaves.left.and.right.slash"),
        SGWithSymbol(SGSwitchRow(SGLocalized(@"Clean shared links"), SGLocalized(@"Takes the tracking (si, utm) off the links you copy or share"), SGKeyCleanLinks), @"link"),
    ]);
}

SGModSection *SGPrivacyCountersSection(void) {
    NSMutableArray<SGModRow *> *counts = [NSMutableArray array];
    for (NSString *label in SGBlockedLabels()) {
        [counts addObject:SGStatRow(label, ^NSString *{
            return @(SGBlockedCount(label)).stringValue;
        })];
    }
    [counts addObject:SGStatRow(SGLocalized(@"Total"), ^NSString *{
        return @(SGBlockedCount(nil)).stringValue;
    })];
    [counts addObject:SGActionRow(SGLocalized(@"Reset the telemetry counters"), nil, ^{ SGResetBlocked(); })];
    return SGSection(SGLocalized(@"Telemetry blocked so far"), counts);
}
