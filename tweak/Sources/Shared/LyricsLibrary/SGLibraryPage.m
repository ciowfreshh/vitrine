#import "SGLyricsLibrary.h"
#import "SGLibraryScan.h"
#import "SGLibraryStore.h"
#import "Settings/SGPage.h"
#import "Shared/Lyrics/Lyrics.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static NSString *const sourceKey = @"spotifyglass.synaLibrary.authorizedSource";

static NSString *statusTitle(NSString *status) {
    if ([status isEqual:@"translated"]) return @"Đã dịch";
    if ([status isEqual:@"original"]) return @"Có lời gốc";
    if ([status isEqual:@"error"]) return @"Lỗi tải";
    return @"Chưa có lời";
}

@interface SGLibraryPage : SGPage <UISearchResultsUpdating, UIDocumentPickerDelegate>
@end

@implementation SGLibraryPage {
    NSArray<NSDictionary *> *_all, *_visible;
    NSMutableSet<NSString *> *_selected;
    UISearchController *_search;
    UILabel *_status;
    UIBarButtonItem *_actions;
    NSString *_filter;
    NSURL *_export;
    NSUInteger _refresh, _searchRevision;
    BOOL _busy;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Thư viện lời bài hát";
    _selected = [NSMutableSet set];
    _search = [[UISearchController alloc] initWithSearchResultsController:nil];
    _search.obscuresBackgroundDuringPresentation = NO;
    _search.searchResultsUpdater = self;
    _search.searchBar.placeholder = @"Tìm bài hát hoặc nghệ sĩ";
    self.definesPresentationContext = YES;
    self.navigationItem.searchController = _search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    _actions = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"ellipsis.circle"] menu:nil];
    _actions.accessibilityLabel = @"Tác vụ thư viện";
    self.navigationItem.rightBarButtonItem = _actions;
    _status = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, self.tableView.bounds.size.width, 82)];
    _status.textAlignment = NSTextAlignmentCenter;
    _status.numberOfLines = 0;
    _status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    _status.adjustsFontForContentSizeCategory = YES;
    _status.textColor = UIColor.secondaryLabelColor;
    self.tableView.tableHeaderView = _status;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(libraryChanged:) name:SGLibraryDidChange object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(scanChanged:) name:SGLibraryScanDidChange object:nil];
    [self updateStatus];
    [self refresh];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    SGDressPageBar(self);
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    SGDressPageBar(self);
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    SGUndressPageBar(self);
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView { SGPlacePageBar(self); }

- (void)libraryChanged:(NSNotification *)notification { [self refresh]; }
- (void)scanChanged:(NSNotification *)notification { [self updateStatus]; }

- (void)updateStatus {
    SGLibraryScanner *scanner = SGLibraryScanner.shared;
    _status.text = [NSString stringWithFormat:@"%lu bài · %lu đã chọn\n%@", (unsigned long)_all.count,
                    (unsigned long)_selected.count, scanner.progress ?: @"Quét Bài hát đã thích để bắt đầu."];
    [self updateMenu];
}

- (void)refresh {
    NSUInteger revision = ++_refresh;
    dispatch_async(SGLibraryQueue(), ^{
        NSArray *results = [SGLibraryLocalStore() summaries];
        NSSet *ids = [NSSet setWithArray:[results valueForKey:@"trackId"]];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (revision != self->_refresh) return;
            self->_all = results;
            [self->_selected intersectSet:ids];
            [self applyFilter];
            [self updateStatus];
        });
    });
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self applyFilter]; }

- (void)applyFilter {
    NSString *query = [_search.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *filter = _filter;
    NSArray *all = _all;
    NSUInteger revision = ++_searchRevision;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSMutableArray *results = [NSMutableArray array];
        for (NSDictionary *track in all) {
            if (filter && ![track[@"status"] isEqual:filter]) continue;
            if (query.length) {
                NSString *title = track[@"title"];
                NSString *artists = [track[@"artists"] componentsJoinedByString:@" · "];
                if (![title localizedStandardContainsString:query] && ![artists localizedStandardContainsString:query] &&
                    ![track[@"trackId"] localizedStandardContainsString:query]) continue;
            }
            [results addObject:track];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (revision != self->_searchRevision) return;
            self->_visible = results;
            [self.tableView reloadData];
        });
    });
}

- (UIAction *)action:(NSString *)title symbol:(NSString *)symbol selector:(SEL)selector disabled:(BOOL)disabled {
    __weak typeof(self) weakSelf = self;
    UIAction *action = [UIAction actionWithTitle:title image:[UIImage systemImageNamed:symbol] identifier:nil handler:^(__kindof UIAction *item) {
        [weakSelf performSelector:selector withObject:nil afterDelay:0];
    }];
    action.attributes = disabled ? UIMenuElementAttributesDisabled : 0;
    return action;
}

- (void)updateMenu {
    __weak typeof(self) weakSelf = self;
    NSMutableArray *filters = [NSMutableArray array];
    for (NSString *value in @[@"all", @"original", @"translated", @"missing", @"error"]) {
        BOOL all = [value isEqual:@"all"];
        UIAction *action = [UIAction actionWithTitle:all ? @"Mọi trạng thái" : statusTitle(value)
            image:nil identifier:nil handler:^(__kindof UIAction *item) {
                SGLibraryPage *page = weakSelf;
                if (!page) return;
                page->_filter = all ? nil : value;
                [page applyFilter];
                [page updateMenu];
            }];
        action.state = (all ? !_filter : [_filter isEqual:value]) ? UIMenuElementStateOn : UIMenuElementStateOff;
        [filters addObject:action];
    }
    BOOL scan = SGLibraryScanner.shared.isRunning;
    _actions.menu = [UIMenu menuWithChildren:@[
        [self action:scan ? @"Tạm dừng" : (SGLibraryScanner.shared.progress ? @"Quét tiếp / quét lại" : @"Quét Bài hát đã thích")
               symbol:scan ? @"pause.circle" : @"heart" selector:@selector(scan) disabled:_busy],
        [self action:@"Nguồn lời được cấp phép" symbol:@"link" selector:@selector(editSource) disabled:scan || _busy],
        [self action:@"Lời của bài đang phát" symbol:@"music.note" selector:@selector(showPlaying) disabled:NO],
        [UIMenu menuWithTitle:@"Lọc theo trạng thái" image:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"]
                   identifier:nil options:0 children:filters],
        [self action:@"Chọn tất cả" symbol:@"checkmark.circle" selector:@selector(selectAll) disabled:!_all.count],
        [self action:@"Bỏ chọn tất cả" symbol:@"circle" selector:@selector(clearSelection) disabled:!_selected.count],
        [self action:@"Xuất mục đã chọn" symbol:@"square.and.arrow.up" selector:@selector(exportSelected) disabled:!_selected.count || _busy],
        [self action:@"Xuất tất cả" symbol:@"square.and.arrow.up.on.square" selector:@selector(exportAll) disabled:!_all.count || _busy],
        [self action:@"Nhập JSON hoặc ZIP" symbol:@"square.and.arrow.down" selector:@selector(pickImport) disabled:_busy],
        [self action:@"Xóa lời lưu của mục đã chọn" symbol:@"trash" selector:@selector(confirmDelete) disabled:!_selected.count || _busy || scan],
    ]];
}

- (void)scan {
    SGLibraryScanner *scanner = SGLibraryScanner.shared;
    if (scanner.isRunning) [scanner pause];
    else {
        NSString *address = [NSUserDefaults.standardUserDefaults stringForKey:sourceKey];
        [scanner startWithSource:address.length ? [NSURL URLWithString:address] : nil];
    }
}

- (void)alert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showPlaying { SGShowPage(self, SGLibraryPlayingLyricsPage()); }

- (void)editSource {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Nguồn lời được cấp phép"
        message:@"Nhập địa chỉ HTTPS của kho lời mà bạn có quyền tải và xuất. Kho trả một tệp <Spotify track ID>.json theo định dạng Thư viện cho mỗi bài. Bỏ trống để chỉ dùng JSON hoặc ZIP nhập từ Tệp."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.text = [NSUserDefaults.standardUserDefaults stringForKey:sourceKey];
        field.placeholder = @"https://";
        field.keyboardType = UIKeyboardTypeURL;
        field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Lưu" style:UIAlertActionStyleDefault handler:^(__kindof UIAlertAction *action) {
        NSString *address = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSURLComponents *parts = [NSURLComponents componentsWithString:address ?: @""];
        if (address.length && (![parts.scheme.lowercaseString isEqual:@"https"] || !parts.host.length ||
                               parts.user || parts.password || parts.query || parts.fragment || !parts.URL)) {
            [self alert:@"Địa chỉ không hợp lệ" message:@"Dùng một địa chỉ HTTPS đầy đủ, không kèm thông tin xác thực."];
            return;
        }
        if (address.length) [NSUserDefaults.standardUserDefaults setObject:parts.URL.absoluteString forKey:sourceKey];
        else [NSUserDefaults.standardUserDefaults removeObjectForKey:sourceKey];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)selectAll {
    [_selected addObjectsFromArray:[_all valueForKey:@"trackId"]];
    [self.tableView reloadData];
    [self updateStatus];
}

- (void)clearSelection {
    [_selected removeAllObjects];
    [self.tableView reloadData];
    [self updateStatus];
}

- (void)exportSelected { [self exportIDs:_selected.allObjects]; }
- (void)exportAll { [self exportIDs:[_all valueForKey:@"trackId"]]; }

- (void)exportIDs:(NSArray *)ids {
    if (_busy || !ids.count) return;
    _busy = YES;
    [self updateMenu];
    dispatch_async(SGLibraryQueue(), ^{
        NSError *error;
        NSURL *folder = [NSFileManager.defaultManager.temporaryDirectory URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
        NSURL *url = [folder URLByAppendingPathComponent:@"Spotify_SYNA_Loi_bai_hat.zip"];
        BOOL ok = [NSFileManager.defaultManager createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:&error] &&
            [SGLibraryLocalStore() exportIDs:ids toURL:url error:&error];
        if (!ok) [NSFileManager.defaultManager removeItemAtURL:folder error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_busy = NO;
            [self updateMenu];
            if (!ok) {
                [self alert:@"Xuất không thành công" message:@"Không thể tạo ZIP từ dữ liệu đã chọn."];
                return;
            }
            self->_export = folder;
            UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForExportingURLs:@[url] asCopy:YES];
            picker.delegate = self;
            [self presentViewController:picker animated:YES completion:nil];
        });
    });
}

- (void)pickImport {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON, UTTypeZIP] asCopy:YES];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)cleanupExport {
    NSURL *folder = _export;
    _export = nil;
    if (folder) dispatch_async(SGLibraryQueue(), ^{ [NSFileManager.defaultManager removeItemAtURL:folder error:nil]; });
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller { [self cleanupExport]; }

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (_export) {
        [self cleanupExport];
        return;
    }
    NSURL *url = urls.firstObject;
    if (!url || _busy) return;
    _busy = YES;
    [self updateMenu];
    dispatch_async(SGLibraryQueue(), ^{
        BOOL accessed = [url startAccessingSecurityScopedResource];
        NSError *error;
        NSDictionary *report = [SGLibraryLocalStore() importURL:url error:&error];
        if (accessed) [url stopAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_busy = NO;
            [self updateMenu];
            if (!report) {
                NSString *message = [error.domain isEqualToString:@"SpotifySYNA.LyricsLibrary"] ? error.localizedDescription : @"Không đọc được tệp đã chọn.";
                [self alert:@"Nhập không thành công" message:message];
                return;
            }
            [NSNotificationCenter.defaultCenter postNotificationName:SGLibraryDidChange object:nil];
            NSString *details = [report[@"details"] componentsJoinedByString:@"\n"];
            [self alert:@"Kết quả nhập" message:[NSString stringWithFormat:@"Đã nhập %@ · Đã dịch %@ · Lỗi %@%@%@",
                report[@"imported"], report[@"translated"], report[@"errors"], details.length ? @"\n\n" : @"", details]];
        });
    });
}

- (void)confirmDelete {
    if (_busy || !_selected.count || SGLibraryScanner.shared.isRunning) return;
    NSArray *ids = _selected.allObjects;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Xóa lời đã lưu?"
        message:@"Chỉ xóa dữ liệu lời trên thiết bị. Các bài vẫn nằm trong Bài hát đã thích của Spotify."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Hủy" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Xóa" style:UIAlertActionStyleDestructive handler:^(__kindof UIAlertAction *action) {
        self->_busy = YES;
        [self updateMenu];
        dispatch_async(SGLibraryQueue(), ^{
            NSUInteger removed = 0;
            for (NSString *trackID in ids) if ([SGLibraryLocalStore() remove:trackID error:nil]) removed++;
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_busy = NO;
                [NSNotificationCenter.defaultCenter postNotificationName:SGLibraryDidChange object:nil];
                [self alert:@"Kết quả xóa" message:[NSString stringWithFormat:@"Đã xóa %lu/%lu mục.",
                    (unsigned long)removed, (unsigned long)ids.count]];
            });
        });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return _visible.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"track"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"track"];
    NSDictionary *track = _visible[indexPath.row];
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = [track[@"title"] length] ? track[@"title"] : track[@"trackId"];
    NSString *artists = [track[@"artists"] componentsJoinedByString:@", "];
    content.secondaryText = artists.length ? [NSString stringWithFormat:@"%@ · %@", artists, statusTitle(track[@"status"])] : statusTitle(track[@"status"]);
    cell.contentConfiguration = content;
    cell.accessoryType = [_selected containsObject:track[@"trackId"]] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *trackID = _visible[indexPath.row][@"trackId"];
    if ([_selected containsObject:trackID]) [_selected removeObject:trackID];
    else [_selected addObject:trackID];
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    [self updateStatus];
}
@end

UIViewController *SGLyricsLibraryPage(void) { return [[SGLibraryPage alloc] initWithStyle:UITableViewStyleInsetGrouped]; }

@interface SGLibraryPlayingPage : SGPage
@end

@implementation SGLibraryPlayingPage {
    NSTimer *_timer;
    NSString *_track;
    NSArray<SGKaraokeLine *> *_lines;
    NSInteger _active;
    NSUInteger _revision;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Lời của bài đang phát";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"" style:UIBarButtonItemStylePlain
        target:self action:@selector(toggle)];
    _active = -1;
    if (self.navigationController.viewControllers.firstObject == self) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Đóng" style:UIBarButtonItemStylePlain
            target:self action:@selector(close)];
    }
    [self updateToggle];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(libraryChanged:) name:SGLibraryDidChange object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self tick];
    __weak typeof(self) weakSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) { [weakSelf tick]; }];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [_timer invalidate];
    _timer = nil;
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)libraryChanged:(NSNotification *)notification { [self reloadLyrics]; }

- (void)updateToggle {
    self.navigationItem.rightBarButtonItem.title = SGLibraryShowsTranslation() ? @"Hiện lời gốc" : @"Hiện bản dịch";
}

- (void)toggle {
    [NSUserDefaults.standardUserDefaults setBool:!SGLibraryShowsTranslation() forKey:SGLibraryShowTranslationKey];
    [self updateToggle];
    [self.tableView reloadData];
}

- (void)reloadLyrics {
    NSString *track = _track;
    NSUInteger revision = ++_revision;
    dispatch_async(SGLibraryQueue(), ^{
        NSArray *lines = SGLibraryKaraokeLines([SGLibraryLocalStore() track:track error:nil]);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (revision != self->_revision) return;
            self->_lines = lines;
            self->_active = -1;
            [self.tableView reloadData];
            [self tick];
        });
    });
}

- (void)tick {
    NSString *current = SGKaraokePlayingTrack();
    if (current != _track && ![current isEqual:_track]) {
        _track = current;
        _lines = nil;
        [self.tableView reloadData];
        [self reloadLyrics];
        return;
    }
    if (SGKaraokeLinesTiming(_lines) == SGKaraokeTimingNone) return;
    NSInteger time = SGKaraokePositionMs();
    NSInteger active = time < 0 ? -1 : SGKaraokeLeadLine(_lines, time - SGKaraokeDelayMs());
    if (active == _active) return;
    _active = active;
    [self.tableView reloadData];
    if (active >= 0 && !self.tableView.dragging && !self.tableView.decelerating)
        [self.tableView scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:active inSection:0]
                            atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return MAX(_lines.count, 1u); }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"line"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"line"];
    UIListContentConfiguration *content = [UIListContentConfiguration cellConfiguration];
    SGKaraokeLine *line = _lines.count ? _lines[indexPath.row] : nil;
    content.text = line ? (SGLibraryShowsTranslation() && line.translation.length ? line.translation : SGKaraokeLineText(line))
                        : @"Thư viện chưa có lời cho bài đang phát.";
    content.textProperties.numberOfLines = 0;
    content.textProperties.color = line && indexPath.row == _active ? UIColor.systemGreenColor : UIColor.labelColor;
    cell.contentConfiguration = content;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}
@end

UIViewController *SGLibraryPlayingLyricsPage(void) { return [[SGLibraryPlayingPage alloc] initWithStyle:UITableViewStyleInsetGrouped]; }
