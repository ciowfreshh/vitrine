#import "LyricsSelection.h"
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
NSNotificationName const SGLyricsShareSelectionChangedNotification = @"Vitrine.LyricsShareSelectionChanged";
SGModRow *SGLyricsShareSelectionRow(void) {
    SGModRow *row = SGOptionRow(SGLocalized(@"Select and copy lyrics"), SGLocalized(@"Hold lyrics to select and copy original text. Spotify image sharing is unavailable in this build."), SGKeyLyricsShareSelection);
    row.changed = ^(BOOL on) { [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsShareSelectionChangedNotification object:nil]; };
    return row;
}
