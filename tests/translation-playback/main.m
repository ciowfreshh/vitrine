// Runs the production persistence + playback matcher, with no API or Spotify account.
#import "Core/SGCore.h"
#import "Core/TranslationStore/SGTranslationStore.h"
#import "Core/BatchQueue/SGTranslationAlignment.h"
#import "Settings/SGModPage.h"
#import "Shared/Lyrics/Lyrics.h"
#import "Shared/LyricsTranslation/LyricsTranslation.h"
#import "Shared/LyricsTranslation/TranslationLibrary.h"

NSNotificationName const SGLyricsTranslationsDidChangeNotification = @"translation-test-change";
UIViewController *SGTopController(void) { return nil; }
UIViewController *SGSavedTranslationsPage(void) { return nil; }
SGModRow *SGPageRow(NSString *title, UIViewController *(^page)(void)) { return nil; }
NSString *SGLyricsSongName(NSString *track) { return @"Synthetic regression song"; }
void SGLyricsForgetAITranslation(NSString *track, NSString *language) {}
@implementation SGTranslationSource
+ (instancetype)by:(NSString *)by model:(NSString *)model made:(NSDate *)made {
    SGTranslationSource *value = [self new]; [value setValue:by forKey:@"by"]; [value setValue:model forKey:@"model"]; [value setValue:made forKey:@"made"]; return value;
}
- (NSString *)name { return @"Test source"; }
- (BOOL)deletable { return YES; }
@end
static NSUInteger checks;
static void check(BOOL ok, NSString *message) { if (!ok) { NSLog(@"PLAYBACK FAIL: %@", message); exit(1); } ++checks; NSLog(@"PLAYBACK PASS: %@", message); }
static SGKaraokeLine *line(NSString *original, NSString *translation) {
    SGKaraokeWord *word = [SGKaraokeWord new]; word.text = original;
    SGKaraokeLine *value = [SGKaraokeLine new]; value.words = @[word]; value.translation = translation; value.translationMade = translation.length > 0; return value;
}
int main(void) { @autoreleasepool {
    NSString *track = [@"regression-" stringByAppendingString:NSUUID.UUID.UUIDString];
    SGTranslationSource *ai = [SGTranslationSource by:@"openai" model:@"test-no-network" made:nil];
    NSArray *original = @[line(@"Don't leave the light", @"Đừng tắt ngọn đèn"), line(@"Follow the quiet road", @"Theo con đường vắng"), line(@"Across the river", @"Qua bên kia sông")];
    check(SGLyricsSaveTranslation(track, @"vi", original, ai) != nil, @"production save commits a whole song");
    NSArray *shown = @[line(@"DON’T leave the light!", @"native community text"), line(@"Follow the quiet road\nAcross the river", nil)];
    ((SGKaraokeLine *)shown[0]).translationMade = NO;
    check(SGLyricsSyncSavedTranslation(track, @"vi", shown) != nil, @"production playback reads durable AI record");
    check([((SGKaraokeLine *)shown[0]).translation isEqual:@"Đừng tắt ngọn đèn"], @"typography mismatch resolves and AI overrides community text");
    check([((SGKaraokeLine *)shown[1]).translation isEqual:@"Theo con đường vắng Qua bên kia sông"], @"two saved rows align to a joined display row without an API");
    check(SGLyricsSavedTranslationMissing(track, @"vi", shown) == 0, @"queue and playback agree on full coverage");
    check(SGLyricsSaveTranslation(track, @"vi", @[line(@"A new verse", @"Một khổ thơ mới")], ai) != nil, @"partial source progress can be committed");
    check(SGLyricsSavedTranslationMissing(track, @"vi", original) == 0, @"partial save preserves every older translated line");
    NSDictionary *record = [SGSavedTranslationStore() recordForTrack:track language:@"vi" error:nil];
    check([record[@"originals"] isEqual:@[@"A new verse"]] && [record[@"lines"] count] == 4, @"ordered source metadata survives store validation with legacy variants");
    check(SGLyricsHasSavedTranslation(track, @"vi") && SGLyricsSavedTranslationMissing(track, @"vi", @[line(@"An actually missing verse", nil)]) == 1, @"record existence cannot masquerade as complete lyrics");
    check(SGLyricsSavedTranslationMissing(track, @"en", original) == 3, @"another target language never borrows Vietnamese translations");
    check(SGTranslationResolveLines(@{@"má":@"mother", @"ma":@"ghost"}, @[@"má", @"ma"]).count == 2 &&
        ![SGTranslationLineKey(@"má") isEqual:SGTranslationLineKey(@"ma")], @"accent differences remain distinct");
    check([SGTranslationResolveLines(@{@"A b":@"one", @"a-b":@"another"}, @[@"A, B!"])[0] isEqual:@""], @"ambiguous normalized translations are not guessed");
    check([SGTranslationMergeLines(@{@"Don't leave":@"old"}, @{@"DON’T leave!":@"new"})[@"Don't leave"] isEqual:@"new"], @"an explicit repair updates equivalent typography aliases without deleting keys");
    check(SGTranslationMissingLines(@[@"Real lyrics", @"♪", @""], @[@"  ", @"", @""]).count == 1, @"empty AI translations fail even when array counts match");
    check(SGTranslationUnchangedForeignLines(@[@"I will always remember the beautiful moments we shared together"], @[@"I will always remember the beautiful moments we shared together"], @"vi").count == 1, @"unchanged confidently foreign verse is not a finished translation");
    check(SGTranslationUnchangedForeignLines(@[@"Tôi sẽ luôn ghi nhớ những ngày tháng đẹp đẽ bên nhau", @"Yeah", @"Rose"], @[@"Tôi sẽ luôn ghi nhớ những ngày tháng đẹp đẽ bên nhau", @"Yeah", @"Rose"], @"vi").count == 0, @"target-language verses, short ad-libs and names stay valid");
    check([SGTranslationResolveLines(@{@"one two":@"x"}, @[@"one", @"two"])[0] isEqual:@""], @"a saved sentence is never arbitrarily split by character count");
    NSString *regional = [track stringByAppendingString:@"-regional"];
    NSDictionary *legacy = @{@"type":@"vitrine.translation", @"schemaVersion":@1, @"track":regional, @"language":@"vi-VN", @"by":@"openai", @"model":@"test-no-network", @"made":@123,
        @"lines":@{@"Hold the lantern":@"Giữ ngọn đèn", @"Walk across the bridge":@"Đi qua cây cầu"}};
    check([SGSavedTranslationStore() putRecord:legacy replace:YES didWrite:NULL error:nil], @"create legacy regional record without original row metadata");
    NSArray *regionalShown = @[line(@"Hold the lantern, walk across the bridge!", @"community text")];
    ((SGKaraokeLine *)regionalShown[0]).translationMade = NO;
    check(SGLyricsSyncSavedTranslation(regional, @"vi", regionalShown) != nil && [((SGKaraokeLine *)regionalShown[0]).translation isEqual:@"Giữ ngọn đèn Đi qua cây cầu"], @"legacy vi-VN record displays in vi with joined source rows");
    check(SGLyricsHasSavedTranslation(regional, @"vi") && SGLyricsSavedTranslationMissing(regional, @"vi", regionalShown)==0, @"queue detects regional saved coverage instead of spending another AI request");
    check([[SGSavedTranslationStore() recordForTrack:regional language:@"vi-VN" error:nil] isEqual:legacy] && ![SGSavedTranslationStore() recordForTrack:regional language:@"vi" error:nil], @"playback compatibility does not rewrite or duplicate a legacy record");
    check(SGLyricsSaveTranslation(regional, @"vi", @[line(@"New words", @"Lời mới")], ai) != nil, @"incremental save through vi can supplement vi-VN");
    check([[[SGSavedTranslationStore() recordForTrack:regional language:@"vi-VN" error:nil] objectForKey:@"lines"] count]==3 && ![SGSavedTranslationStore() recordForTrack:regional language:@"vi" error:nil], @"incremental save keeps the original language identity and all older pairs");
    NSString *base = [track stringByAppendingString:@"-base"];
    check(SGLyricsSaveTranslation(base, @"vi", original, ai) != nil && SGLyricsSavedTranslationMissing(base, @"vi-VN", original)==0, @"base-language saves remain available after switching to device locale");
    check(SGLyricsSavedTranslationMissing(regional, @"en", regionalShown)==1, @"regional fallback never crosses translation languages");
    SGLyricsDeleteSavedTranslation(regional, @"vi");
    check(!SGLyricsHasSavedTranslation(regional, @"vi-VN"), @"explicit delete removes the matching regional translation");
    SGLyricsDeleteSavedTranslation(base, @"vi-VN");
    check(!SGLyricsHasSavedTranslation(base, @"vi"), @"explicit regional delete cannot resurrect a base-language saved record");
    SGLyricsDeleteSavedTranslation(track, @"vi");
    SGLyricsSyncSavedTranslation(track, @"vi", shown);
    check(!((SGKaraokeLine *)shown[0]).translationMade && !((SGKaraokeLine *)shown[0]).translation.length, @"deletion still removes made translations from playback");
    NSLog(@"PLAYBACK COMPLETE: %lu checks; synthetic lyrics, production store and matcher; no AI or iPhone", (unsigned long)checks);
} return 0; }
