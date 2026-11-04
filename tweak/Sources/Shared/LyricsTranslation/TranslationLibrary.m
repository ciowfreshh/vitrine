#import "Core/SGCore.h"
#import "Core/TranslationStore/SGTranslationStore.h"
#import "Core/TranslationStore/SGTranslationArchive.h"
#import "Settings/SGPage.h"
#import "Settings/SGPageStyle.h"
#import "LyricsTranslation.h"
#import "TranslationLibrary.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface SGTranslationLibraryPage : SGPage <UIDocumentPickerDelegate>
@end
@implementation SGTranslationLibraryPage {
    NSArray<NSDictionary *> *_records;
    NSMutableIndexSet *_selected;
    BOOL _busy, _replace;
    UIAlertController *_progress;
    CFAbsoluteTime _lastProgress;
}
- (instancetype)init {
    if (!(self=[super initWithStyle:UITableViewStyleInsetGrouped])) return nil;
    self.title=SGLocalized(@"Saved translations"); _records=@[]; _selected=[NSMutableIndexSet indexSet];
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    [self reload];
}
- (void)message:(NSString *)title detail:(NSString *)detail {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:title message:detail preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGLocalized(@"OK") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)reload {
    _busy=YES;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{
        NSError *error=nil; NSArray *rows=[SGSavedTranslationStore() summaries:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_records=rows; [self->_selected removeAllIndexes]; self->_busy=NO; [self.tableView reloadData];
            if(error)[self message:SGLocalized(@"Translation storage error") detail:SGLocalizedError(error)];
        });
    });
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return 2; }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section { return section==0?5:(NSInteger)_records.count; }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section { return section==1?SGLocalized(@"Translations"):nil; }
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    return section==0?SGLocalized(@"Stored without a song limit in Application Support and included in device backups. Select songs to export. Share a JSON or ZIP through AirDrop, Files or iCloud Drive, then import it on the other iPhone."):nil;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=SGDequeueCell(table,@"translation");
    if(path.section==0) {
        NSArray *actions=@[SGLocalized(@"Select all"),SGLocalized(@"Export selected"),SGLocalized(@"Export all"),SGLocalized(@"Import JSON or ZIP"),SGLocalized(@"Delete selected")];
        NSString *title=path.row==0&&_selected.count==_records.count&&_records.count?SGLocalized(@"Deselect all"):actions[(NSUInteger)path.row];
        SGFillCell(cell,title,nil,SGGreen(),nil); cell.accessoryType=UITableViewCellAccessoryNone;
    } else {
        NSDictionary *row=_records[(NSUInteger)path.row];
        NSString *detail=[NSString stringWithFormat:@"%@ · %@",row[@"language"],[NSByteCountFormatter stringFromByteCount:[row[@"bytes"] longLongValue] countStyle:NSByteCountFormatterCountStyleFile]];
        SGFillCell(cell,row[@"title"]?:row[@"track"],detail,nil,nil);
        cell.accessoryType=[_selected containsIndex:(NSUInteger)path.row]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;
    }
    cell.selectionStyle=_busy?UITableViewCellSelectionStyleNone:UITableViewCellSelectionStyleDefault;
    return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path {
    [table deselectRowAtIndexPath:path animated:YES]; if(_busy)return;
    if(path.section==1) {
        NSUInteger index=(NSUInteger)path.row;
        if([_selected containsIndex:index])[_selected removeIndex:index]; else [_selected addIndex:index];
        [table reloadRowsAtIndexPaths:@[path] withRowAnimation:UITableViewRowAnimationNone]; return;
    }
    switch(path.row) {
        case 0: if(_selected.count==_records.count)[_selected removeAllIndexes];else [_selected addIndexesInRange:NSMakeRange(0,_records.count)]; [table reloadData]; break;
        case 1: [self exportRows:[_records objectsAtIndexes:_selected] forceZIP:NO]; break;
        case 2: [self exportRows:_records forceZIP:YES]; break;
        case 3: [self chooseImport]; break;
        case 4: [self deleteSelected]; break;
    }
}
- (void)begin:(NSString *)title run:(void (^)(void))run {
    _busy=YES; _lastProgress=0;
    _progress=[UIAlertController alertControllerWithTitle:title message:SGLocalized(@"Preparing…") preferredStyle:UIAlertControllerStyleAlert];
    self.navigationItem.hidesBackButton=YES; self.modalInPresentation=YES;
    [self presentViewController:_progress animated:YES completion:^{ dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),run); }];
}
- (void)progress:(NSUInteger)done total:(NSUInteger)total {
    CFAbsoluteTime now=CFAbsoluteTimeGetCurrent();
    if(done!=total&&now-_lastProgress<0.1)return; _lastProgress=now;
    dispatch_async(dispatch_get_main_queue(), ^{ self->_progress.message=[NSString stringWithFormat:SGLocalized(@"%lu of %lu"),(unsigned long)done,(unsigned long)total]; });
}
- (void)finish:(void (^)(void))completion {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.navigationItem.hidesBackButton=NO; self.modalInPresentation=NO; self->_busy=NO;
        [self->_progress dismissViewControllerAnimated:YES completion:completion]; self->_progress=nil;
    });
}
- (void)exportRows:(NSArray<NSDictionary *> *)rows forceZIP:(BOOL)forceZIP {
    if(!rows.count){[self message:SGLocalized(@"No translations selected") detail:SGLocalized(@"Select at least one saved translation.")];return;}
    [self begin:SGLocalized(@"Exporting translations") run:^{
        NSError *error=nil;
        NSURL *directory=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
        BOOL ok=[NSFileManager.defaultManager createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:&error];
        NSURL *url=[directory URLByAppendingPathComponent:!forceZIP&&rows.count==1?@"translation.json":@"translations.zip"];
        if(ok&&!forceZIP&&rows.count==1) {
            NSDictionary *row=rows.firstObject;
            NSDictionary *record=[SGSavedTranslationStore() recordForTrack:row[@"track"] language:row[@"language"] error:&error];
            NSDictionary *clean=record?[SGTranslationStore validatedRecord:record error:&error]:nil;
            NSData *data=clean?[NSJSONSerialization dataWithJSONObject:clean options:NSJSONWritingPrettyPrinted|NSJSONWritingSortedKeys error:&error]:nil;
            ok=data&&[data writeToURL:url options:NSDataWritingAtomic error:&error];
        } else if(ok) ok=[SGTranslationArchive writeRecords:rows toURL:url record:^NSDictionary *(NSDictionary *row,NSError **failure){
            return [SGSavedTranslationStore() recordForTrack:row[@"track"] language:row[@"language"] error:failure];
        } progress:^(NSUInteger done,NSUInteger total){[self progress:done total:total];} error:&error];
        [self finish:^{
            if(!ok){[self message:SGLocalized(@"Export failed") detail:SGLocalizedError(error)?:SGLocalized(@"Could not read saved translations.")];return;}
            UIActivityViewController *sheet=[[UIActivityViewController alloc]initWithActivityItems:@[url] applicationActivities:nil];
            sheet.popoverPresentationController.sourceView=self.view;
            sheet.popoverPresentationController.sourceRect=CGRectMake(self.view.bounds.size.width/2,self.view.bounds.size.height/2,1,1);
            sheet.completionWithItemsHandler=^(UIActivityType type,BOOL completed,NSArray *items,NSError *failure){[NSFileManager.defaultManager removeItemAtURL:directory error:nil];};
            [self presentViewController:sheet animated:YES completion:nil];
        }];
    }];
}
- (void)deleteSelected {
    NSArray *rows=[_records objectsAtIndexes:_selected];
    if(!rows.count){[self message:SGLocalized(@"No translations selected") detail:SGLocalized(@"Select at least one saved translation.")];return;}
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:SGLocalized(@"Delete selected translations?") message:SGLocalized(@"This permanently removes the selected saved translations from this iPhone.") preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:SGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:SGLocalized(@"Delete") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){
        [self begin:SGLocalized(@"Deleting translations") run:^{
            NSError *error=nil; NSUInteger done=0;
            for(NSDictionary *row in rows) {
                if(![SGSavedTranslationStore() removeTrack:row[@"track"] language:row[@"language"] error:&error])break;
                [self progress:++done total:rows.count];
            }
            [self finish:^{SGLyricsForgetAITranslation(nil,nil);[NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationsDidChangeNotification object:nil];[self reload];
                if(error)[self message:SGLocalized(@"Translation storage error") detail:SGLocalizedError(error)];
            }];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)chooseImport {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:SGLocalized(@"Import translations") message:SGLocalized(@"If the same track and language already exist, skip the imported copy or replace the saved translation.") preferredStyle:UIAlertControllerStyleAlert];
    for(NSNumber *replace in @[@NO,@YES]) [alert addAction:[UIAlertAction actionWithTitle:replace.boolValue?SGLocalized(@"Replace duplicates"):SGLocalized(@"Skip duplicates") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
        self->_replace=replace.boolValue;
        UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc]initForOpeningContentTypes:@[UTTypeJSON,UTTypeZIP] asCopy:YES];
        picker.delegate=self; [self presentViewController:picker animated:YES completion:nil];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:SGLocalized(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url=urls.firstObject; if(!url)return;
    BOOL scope=[url startAccessingSecurityScopedResource];
    void (^run)(void)=^{[self begin:SGLocalized(@"Importing translations") run:^{
        __block NSUInteger added=0,skipped=0,replaced=0; NSError *error=nil;
        BOOL ok=[SGTranslationArchive readURL:url consume:^BOOL(id value,NSError **failure){
            NSDictionary *clean=[SGTranslationStore validatedRecord:value error:failure]; if(!clean)return NO;
            BOOL existed=[SGSavedTranslationStore() recordForTrack:clean[@"track"] language:clean[@"language"] error:failure]!=nil;
            if(failure&&*failure)return NO;
            BOOL wrote=NO; if(![SGSavedTranslationStore() putRecord:clean replace:self->_replace didWrite:&wrote error:failure])return NO;
            if(!wrote)skipped++;else if(existed)replaced++;else added++;
            return YES;
        } progress:^(NSUInteger done,NSUInteger total){[self progress:done total:total];} error:&error];
        if(scope)[url stopAccessingSecurityScopedResource];
        [self finish:^{
            SGLyricsForgetAITranslation(nil,nil);
            [NSNotificationCenter.defaultCenter postNotificationName:SGLyricsTranslationsDidChangeNotification object:nil];
            [self reload];
            NSString *counts=[NSString stringWithFormat:SGLocalized(@"Added: %lu. Replaced: %lu. Skipped: %lu."),(unsigned long)added,(unsigned long)replaced,(unsigned long)skipped];
            [self message:ok?SGLocalized(@"Import complete"):SGLocalized(@"Import stopped") detail:ok?counts:[NSString stringWithFormat:@"%@\n%@",counts,SGLocalizedError(error)?:SGLocalized(@"Invalid translation record.")]];
        }];
    }];};
    // Document picker's dismissal can still be in flight when its delegate is called.
    if(picker.presentingViewController)[picker dismissViewControllerAnimated:YES completion:run];else run();
}
@end
UIViewController *SGSavedTranslationsPage(void) { return [SGTranslationLibraryPage new]; }
