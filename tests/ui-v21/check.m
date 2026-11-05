#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "Redesigned/Lyrics/SGRKaraokeView.h"
#import "Shared/LyricsTranslation/LyricsSelection.h"
#import "App/SettingsPlacement.h"
#import "Core/SGPrefs.h"
static void verify(BOOL ok, NSString *name) { if (!ok) { NSLog(@"V21 FAIL: %@", name); exit(1); } NSLog(@"V21 PASS: %@", name); }
static void invoke(id target, NSString *selector, id argument) { ((void (*)(id, SEL, id))objc_msgSend)(target, NSSelectorFromString(selector), argument); }
@interface SGV21Hold : UILongPressGestureRecognizer
@property CGPoint point;
@end
@implementation SGV21Hold
- (UIGestureRecognizerState)state { return UIGestureRecognizerStateBegan; }
- (CGPoint)locationInView:(UIView *)view { return _point; }
@end
@interface SGV21Tap : UITapGestureRecognizer
@property CGPoint point;
@end
@implementation SGV21Tap
- (CGPoint)locationInView:(UIView *)view { return _point; }
@end
@interface SGV21DataSource : NSObject <UICollectionViewDataSource>
@property (nonatomic, copy) NSArray<NSString *> *titles;
@end
@implementation SGV21DataSource
- (NSInteger)collectionView:(UICollectionView *)view numberOfItemsInSection:(NSInteger)section { return _titles.count; }
- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)view cellForItemAtIndexPath:(NSIndexPath *)path {
    UICollectionViewCell *cell = [view dequeueReusableCellWithReuseIdentifier:@"native" forIndexPath:path];
    for (UIView *child in cell.contentView.subviews) [child removeFromSuperview];
    UILabel *label = [[UILabel alloc] initWithFrame:cell.contentView.bounds]; label.text = _titles[path.item]; [cell.contentView addSubview:label]; return cell;
}
@end
static void checkSettings(void) {
    for (NSArray *titles in @[@[@"Media quality", @"About"], @[@"Chất lượng nội dung nghe nhìn", @"Giới thiệu"], @[@"Your plan", @"Settings and privacy"]]) {
        BOOL drawer = titles.count && [titles.lastObject isEqual:@"Settings and privacy"];
        UICollectionViewFlowLayout *layout = [UICollectionViewFlowLayout new]; layout.itemSize = CGSizeMake(390, 56); layout.minimumLineSpacing = 0;
        UICollectionView *list = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 0, 390, 600) collectionViewLayout:layout];
        SGV21DataSource *source = [SGV21DataSource new]; source.titles = titles; list.dataSource = source;
        [list registerClass:UICollectionViewCell.class forCellWithReuseIdentifier:@"native"];
        UIWindowScene *scene = (id)UIApplication.sharedApplication.connectedScenes.anyObject;
        [scene.windows.firstObject.rootViewController.view addSubview:list]; [list layoutIfNeeded];
        UIControl *row = [UIControl new]; [list addSubview:row];
        SGPlaceSettingsEntry(list, row, drawer, 56); CGFloat inset = list.contentInset.bottom;
        SGPlaceSettingsEntry(list, row, drawer, 56);
        verify(list.contentInset.top == 0 && inset == 56 && list.contentInset.bottom == 56, @"entry layout has no accumulating insets");
        UICollectionViewCell *anchor = [list cellForItemAtIndexPath:[NSIndexPath indexPathForItem:1 inSection:0]];
        if (drawer) verify(fabs(row.frame.origin.y - CGRectGetMaxY(anchor.frame)) < 0.5, @"drawer entry immediately follows Settings and privacy");
        else verify(fabs(CGRectGetMaxY(row.frame) - CGRectGetMinY(anchor.frame)) < 0.5, @"English/Vietnamese entry precedes About with no overlap");
        SGRemoveSettingsEntry(list); verify(list.contentInset.bottom == 0 && CGAffineTransformIsIdentity(anchor.transform), @"entry removal restores native layout");
        [list removeFromSuperview];
    }
}
void SGV21UIChecks(SGRKaraokeView *view) {
    checkSettings();
    NSDictionary<NSNumber *, UIView *> *shown = [view valueForKey:@"shown"];
    NSArray<NSNumber *> *indexes = [shown.allKeys sortedArrayUsingSelector:@selector(compare:)];
    verify(indexes.count >= 2, @"real lyric renderer has multiple visible lines");
    UIView *first = shown[indexes[0]], *second = shown[indexes[1]];
    UIScrollView *scroll = [view valueForKey:@"scroll"];
    NSNumber *before = [view valueForKey:@"seekAt"];
    SGSetEnabled(SGKeyLyricsShareSelection, YES);
    SGV21Hold *hold = [SGV21Hold new]; hold.point = first.center;
    invoke(view, @"held:", hold);
    NSIndexSet *selected = [view valueForKey:@"selected"];
    verify(selected.count == 1 && [selected containsIndex:[indexes[0] unsignedIntegerValue]], @"long press selects exactly the held line");
    verify(first.layer.cornerRadius == 12 && first.backgroundColor != UIColor.clearColor && second.alpha < first.alpha, @"selected line is rounded and dark; other lines dim");
    SGV21Tap *tap = [SGV21Tap new]; tap.point = [scroll convertPoint:second.center toView:view]; invoke(view, @"tapped:", tap);
    verify([[view valueForKey:@"selected"] count] == 2, @"tap adds another line"); invoke(view, @"tapped:", tap);
    verify([[view valueForKey:@"selected"] count] == 1, @"tap deselects a line");
    CGPoint offset = scroll.contentOffset; ((void (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"followSong"));
    verify(CGPointEqualToPoint(offset, scroll.contentOffset), @"selection prevents automatic follow scrolling");
    verify([[view valueForKey:@"seekAt"] isEqual:before], @"selection never issues a player seek");
    view.extrasHidden = YES; id mic = [view valueForKey:@"sing"];
    verify([[mic valueForKey:@"tucked"] boolValue] && ![mic isUserInteractionEnabled], @"auto-hidden microphone cannot intercept taps");
    view.extrasHidden = NO;
    verify(![[mic valueForKey:@"tucked"] boolValue] && [mic isUserInteractionEnabled], @"microphone returns with controls");
    SGSetEnabled(SGKeyLyricsShareSelection, NO);
    [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsShareSelectionChangedNotification object:nil];
    verify([view valueForKey:@"selected"] == nil, @"turning switch off immediately cancels selection");
    verify([[view valueForKey:@"tops"] count] > 0 && [[view valueForKey:@"shown"] count] > 0, @"cancellation preserves measured lyrics and restores visible line views");
    SGSetEnabled(SGKeyLyricsShareSelection, YES);
    UIView *replacement = ((id (*)(id, SEL, NSInteger))objc_msgSend)(view, NSSelectorFromString(@"viewForLine:"), indexes[0].integerValue);
    invoke(view, @"toggleSelectedView:", replacement);
    verify([[view valueForKey:@"selected"] count] == 1, @"selection re-enters after cancellation");
    ((void (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"continueSelection"));
    verify(UIPasteboard.generalPasteboard.string.length > 0 && [view valueForKey:@"selected"] == nil, @"copy action copies original lyrics and restores playback without an unavailable share alert");
    invoke(view, @"toggleSelectedView:", ((id (*)(id, SEL, NSInteger))objc_msgSend)(view, NSSelectorFromString(@"viewForLine:"), indexes[0].integerValue));
    ((void (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"dropLines"));
    verify([view valueForKey:@"selected"] == nil, @"track replacement clears old selection");
    ((void (*)(id, SEL))objc_msgSend)(view, NSSelectorFromString(@"tick")); [view layoutIfNeeded];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        UIView *preview = ((id (*)(id, SEL, NSInteger))objc_msgSend)(view, NSSelectorFromString(@"viewForLine:"), indexes[0].integerValue);
        verify(preview != nil, @"track replacement rebuilds real line views before preview");
        invoke(view, @"toggleSelectedView:", preview); [view layoutIfNeeded];
        NSLog(@"V21 UI COMPLETE: UIKit simulator, mocked song/player; native Spotify and real iPhone untested");
    });
}
