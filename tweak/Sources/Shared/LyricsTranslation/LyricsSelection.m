#import "LyricsSelection.h"
#import "Core/SGCore.h"
#import "Settings/SGModPage.h"
NSNotificationName const SGLyricsShareSelectionChangedNotification = @"Vitrine.LyricsShareSelectionChanged";
SGModRow *SGLyricsShareSelectionRow(void) {
    SGModRow *row = SGOptionRow(SGLocalized(@"Select lyrics to share"), SGLocalized(@"Hold lyrics to select multiple lines and share with Spotify."), SGKeyLyricsShareSelection);
    row.changed = ^(BOOL on) { [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsShareSelectionChangedNotification object:nil]; };
    return row;
}
