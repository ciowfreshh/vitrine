#import "SettingsPlacement.h"
#import <objc/runtime.h>
static char kAnchor, kShift, kBase, kInset;
static BOOL containsTitle(UIView *view, NSArray<NSString *> *titles) {
    if ([view isKindOfClass:UILabel.class] && [titles containsObject:((UILabel *)view).text]) return YES;
    for (UIView *child in view.subviews) if (containsTitle(child, titles)) return YES;
    return NO;
}
static void unshift(UICollectionView *list) {
    for (UICollectionViewCell *cell in list.visibleCells) {
        NSValue *shift = objc_getAssociatedObject(cell, &kShift);
        NSValue *base = objc_getAssociatedObject(cell, &kBase);
        if (shift && base && CGAffineTransformEqualToTransform(cell.transform, shift.CGAffineTransformValue)) cell.transform = base.CGAffineTransformValue;
        objc_setAssociatedObject(cell, &kShift, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
void SGRemoveSettingsEntry(UICollectionView *list) {
    unshift(list);
    NSNumber *applied = objc_getAssociatedObject(list, &kInset);
    if (applied) { UIEdgeInsets inset = list.contentInset; inset.bottom = MAX(0, inset.bottom - applied.doubleValue); list.contentInset = inset; }
    objc_setAssociatedObject(list, &kInset, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(list, &kAnchor, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
void SGPlaceSettingsEntry(UICollectionView *list, UIControl *row, BOOL drawer, CGFloat height) {
    unshift(list);
    NSArray *titles = drawer ? @[@"Settings and privacy", @"Settings & privacy", @"Cài đặt và quyền riêng tư"] : @[@"About", @"Giới thiệu"];
    NSIndexPath *anchor = objc_getAssociatedObject(list, &kAnchor);
    for (UICollectionViewCell *cell in list.visibleCells) if (containsTitle(cell, titles)) { anchor = [list indexPathForCell:cell]; break; }
    if (anchor && (anchor.section >= [list numberOfSections] || anchor.item >= [list numberOfItemsInSection:anchor.section])) anchor = nil;
    objc_setAssociatedObject(list, &kAnchor, anchor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    UICollectionViewLayoutAttributes *attributes = anchor ? [list.collectionViewLayout layoutAttributesForItemAtIndexPath:anchor] : nil;
    CGFloat y = attributes ? (drawer ? CGRectGetMaxY(attributes.frame) : CGRectGetMinY(attributes.frame)) : list.contentSize.height;
    for (UICollectionViewCell *cell in list.visibleCells) {
        NSIndexPath *index = [list indexPathForCell:cell];
        UICollectionViewLayoutAttributes *native = index ? [list.collectionViewLayout layoutAttributesForItemAtIndexPath:index] : nil;
        if (attributes && native && CGRectGetMinY(native.frame) >= y - 0.5) {
            objc_setAssociatedObject(cell, &kBase, [NSValue valueWithCGAffineTransform:cell.transform], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            cell.transform = CGAffineTransformTranslate(cell.transform, 0, height);
            objc_setAssociatedObject(cell, &kShift, [NSValue valueWithCGAffineTransform:cell.transform], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }
    row.hidden = list.contentSize.height <= 0;
    row.frame = CGRectMake(0, y, list.bounds.size.width, height);
    // Spotify may set a new inset. Remember the resulting value so repeated layouts do not accumulate.
    NSValue *last = objc_getAssociatedObject(row, &kInset);
    if (!last || !UIEdgeInsetsEqualToEdgeInsets(last.UIEdgeInsetsValue, list.contentInset)) {
        UIEdgeInsets inset = list.contentInset; inset.bottom += height; list.contentInset = inset;
        objc_setAssociatedObject(row, &kInset, [NSValue valueWithUIEdgeInsets:inset], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(list, &kInset, @(height), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}
