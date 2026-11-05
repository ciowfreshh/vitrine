#import <Foundation/Foundation.h>
#import <sqlite3.h>
#import <sys/wait.h>
#import <unistd.h>
#import "Core/TranslationStore/SGTranslationStore.h"
#import "Core/TranslationStore/SGTranslationArchive.h"
#import "Core/TranslationStore/SGTranslationLanguage.h"
#import "Core/SGLocalization.h"
#define CHECK(x) do { if(!(x)){fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#x);exit(1);} checks++; } while(0)
static int checks;
static NSDictionary *record(NSString *track) { return @{@"type":@"vitrine.translation",@"schemaVersion":@1,@"track":track,@"language":@"vi",@"by":@"openai",@"model":@"unchanged-model",@"made":@123,@"title":@"Home",@"artist":@"English Artist",@"lines":@{@"Original words":@"Lời đã dịch"}}; }
int main(int argc,const char *argv[]) { @autoreleasepool {
    if(argc==3 && strcmp(argv[1],"--terminate")==0){
        SGTranslationStore *writer=[[SGTranslationStore alloc]initWithURL:[NSURL fileURLWithPath:@(argv[2])] legacyDirectory:nil];
        BOOL ok=[writer putRecord:record(@"terminated") replace:YES didWrite:NULL error:nil];_exit(ok?23:24);
    }
    NSURL *root=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    CHECK(SGTranslationSameLanguage(@"vi", @"vi-VN"));
    CHECK(SGTranslationSameLanguage(@"VI_vn", @"vi-Latn-VN"));
    CHECK(!SGTranslationSameLanguage(@"vi", @"en") && !SGTranslationSameLanguage(@"vi", @"vi-Hani"));
    CHECK(!SGTranslationSameLanguage(@"zh-Hans", @"zh-Hant") && !SGTranslationSameLanguage(@"en-US", @"en-GB"));
    SGTranslationStore *regional=[[SGTranslationStore alloc] initWithURL:[root URLByAppendingPathComponent:@"regional.sqlite3"] legacyDirectory:nil];
    NSMutableDictionary *legacyRegion=[record(@"regional-track") mutableCopy]; legacyRegion[@"language"]=@"vi-VN";
    CHECK([regional putRecord:legacyRegion replace:YES didWrite:NULL error:nil]);
    CHECK([regional recordForTrack:@"regional-track" language:@"vi" error:nil]==nil);
    CHECK([[[regional compatibleRecordForTrack:@"regional-track" language:@"vi" error:nil] objectForKey:@"language"] isEqual:@"vi-VN"]);
    CHECK([[regional recordForTrack:@"regional-track" language:@"vi-VN" error:nil] isEqual:legacyRegion]);
    CHECK([regional summaries:nil].count==1); // compatible reads must never migrate or duplicate rows
    NSMutableDictionary *baseRegion=[record(@"regional-track") mutableCopy];
    baseRegion[@"lines"]=@{@"Original words":@"Bản chọn tay", @"Additional words":@"Dòng bổ sung"};
    CHECK([regional putRecord:baseRegion replace:YES didWrite:NULL error:nil]);
    CHECK([[[regional compatibleRecordForTrack:@"regional-track" language:@"vi" error:nil] objectForKey:@"lines"][@"Original words"] isEqual:@"Bản chọn tay"]);
    CHECK([[[regional compatibleRecordForTrack:@"regional-track" language:@"vi-VN" error:nil] objectForKey:@"lines"][@"Original words"] isEqual:@"Lời đã dịch"]);
    CHECK([[[regional compatibleRecordForTrack:@"regional-track" language:@"vi-VN" error:nil] objectForKey:@"lines"][@"Additional words"] isEqual:@"Dòng bổ sung"]);
    CHECK([regional compatibleRecordForTrack:@"regional-track" language:@"en" error:nil]==nil && [regional compatibleRecordForTrack:@"regional-track" language:@"vi-Hani" error:nil]==nil);
    CHECK([NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil]);
    NSURL *legacy=[root URLByAppendingPathComponent:@"Caches" isDirectory:YES];
    CHECK([NSFileManager.defaultManager createDirectoryAtURL:legacy withIntermediateDirectories:YES attributes:nil error:nil]);
    NSDictionary *old=@{@"lines":@{@"Original":@"Cũ"},@"by":@"gemini",@"model":@"original-model",@"made":@10};
    CHECK([[NSJSONSerialization dataWithJSONObject:old options:0 error:nil] writeToURL:[legacy URLByAppendingPathComponent:@"legacy.vi.json"] atomically:YES]);
    CHECK([[NSJSONSerialization dataWithJSONObject:@{@"Old":@"Xưa"} options:0 error:nil] writeToURL:[legacy URLByAppendingPathComponent:@"older.en.json"] atomically:YES]);
    CHECK([@"{bad" writeToURL:[legacy URLByAppendingPathComponent:@"broken.vi.json"] atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    NSURL *db=[root URLByAppendingPathComponent:@"Support/translations.sqlite3"];
    SGTranslationStore *store=[[SGTranslationStore alloc]initWithURL:db legacyDirectory:legacy];
    CHECK([store summaries:nil].count==2);
    CHECK(![NSFileManager.defaultManager fileExistsAtPath:[legacy URLByAppendingPathComponent:@"legacy.vi.json"].path]);
    CHECK([NSFileManager.defaultManager fileExistsAtPath:[legacy URLByAppendingPathComponent:@"broken.vi.json"].path]);
    CHECK([[[store recordForTrack:@"legacy" language:@"vi" error:nil] objectForKey:@"model"] isEqual:@"original-model"]);
    for(NSUInteger i=0;i<10001;i++) { @autoreleasepool { CHECK([store putRecord:record([NSString stringWithFormat:@"track%lu",(unsigned long)i]) replace:YES didWrite:NULL error:nil]); } }
    CHECK([store summaries:nil].count==10003);
    store=nil; store=[[SGTranslationStore alloc]initWithURL:db legacyDirectory:legacy];
    CHECK([store summaries:nil].count==10003);
    CHECK([store recordForTrack:@"track0" language:@"vi" error:nil]!=nil);
    CHECK([store recordForTrack:@"track10000" language:@"vi" error:nil]!=nil);
    NSMutableDictionary *changed=[record(@"track0") mutableCopy];changed[@"title"]=@"Replacement";
    BOOL wrote=YES;CHECK([store putRecord:changed replace:NO didWrite:&wrote error:nil]&&!wrote);
    CHECK([[[store recordForTrack:@"track0" language:@"vi" error:nil] objectForKey:@"title"]isEqual:@"Home"]);
    CHECK([store putRecord:changed replace:YES didWrite:&wrote error:nil]&&wrote);
    CHECK([[[store recordForTrack:@"track0" language:@"vi" error:nil] objectForKey:@"title"]isEqual:@"Replacement"]);
    // A failed write must report failure and leave the previous committed song intact.
    sqlite3 *locked=NULL;CHECK(sqlite3_open(db.path.UTF8String,&locked)==SQLITE_OK);
    CHECK(sqlite3_exec(locked,"BEGIN IMMEDIATE",NULL,NULL,NULL)==SQLITE_OK);
    changed[@"title"]=@"Must not replace";NSError *writeError=nil;wrote=YES;
    CHECK(![store putRecord:changed replace:YES didWrite:&wrote error:&writeError]&&writeError!=nil&&!wrote);
    CHECK([[[store recordForTrack:@"track0" language:@"vi" error:nil]objectForKey:@"title"]isEqual:@"Replacement"]);
    CHECK(sqlite3_exec(locked,"ROLLBACK",NULL,NULL,NULL)==SQLITE_OK);sqlite3_close(locked);
    NSMutableDictionary *secret=[record(@"private") mutableCopy];secret[@"apiKey"]=@"DO_NOT_EXPORT";secret[@"settings"]=@{@"token":@"DO_NOT_EXPORT"};
    NSDictionary *clean=[SGTranslationStore validatedRecord:secret error:nil];CHECK(clean[@"apiKey"]==nil&&clean[@"settings"]==nil);
    CHECK([clean[@"title"]isEqual:@"Home"]&&[clean[@"lines"]isEqual:record(@"private")[@"lines"]]);
    for(id bad in @[@{},@[],@"wrong",@{@"type":@"vitrine.translation",@"schemaVersion":@99},@{@"type":@"vitrine.translation",@"schemaVersion":@1,@"track":@"x",@"language":@"vi",@"lines":@{@"x":@5}}]) {CHECK([SGTranslationStore validatedRecord:bad error:nil]==nil);}
    NSURL *archive=[root URLByAppendingPathComponent:@"selected.zip"];
    NSArray *selected=@[record(@"track1"),record(@"track2")];
    CHECK([SGTranslationArchive writeRecords:selected toURL:archive record:^NSDictionary *(NSDictionary *row,NSError **e){return row;} progress:nil error:nil]);
    __block NSUInteger imported=0;
    CHECK([SGTranslationArchive readURL:archive consume:^BOOL(id row,NSError **e){imported++;return [SGTranslationStore validatedRecord:row error:e]!=nil;} progress:nil error:nil]&&imported==2);
    NSURL *all=[root URLByAppendingPathComponent:@"all.zip"];
    CHECK([SGTranslationArchive writeRecords:[store summaries:nil] toURL:all record:^NSDictionary *(NSDictionary *row,NSError **e){return [store recordForTrack:row[@"track"] language:row[@"language"] error:e];} progress:nil error:nil]);
    imported=0;CHECK([SGTranslationArchive readURL:all consume:^BOOL(id row,NSError **e){imported++;return YES;} progress:nil error:nil]&&imported==10003);
    NSMutableData *broken=[[NSData dataWithContentsOfURL:archive] mutableCopy];((uint8_t *)broken.mutableBytes)[32]^=1;
    NSURL *corrupt=[root URLByAppendingPathComponent:@"corrupt.zip"];CHECK([broken writeToURL:corrupt atomically:YES]);
    CHECK(![SGTranslationArchive readURL:corrupt consume:^BOOL(id row,NSError **e){return YES;} progress:nil error:nil]);
    NSURL *json=[root URLByAppendingPathComponent:@"one.json"];CHECK([[NSJSONSerialization dataWithJSONObject:clean options:0 error:nil] writeToURL:json atomically:YES]);
    imported=0;CHECK([SGTranslationArchive readURL:json consume:^BOOL(id row,NSError **e){imported++;return YES;} progress:nil error:nil]&&imported==1);
    // A process terminated immediately after a save still leaves a committed translation.
    store=nil;pid_t child=fork();
    if(child==0){execl(argv[0],argv[0],"--terminate",db.path.UTF8String,NULL);_exit(25);}
    int status=0;CHECK(waitpid(child,&status,0)==child&&WEXITSTATUS(status)==23);
    store=[[SGTranslationStore alloc]initWithURL:db legacyDirectory:nil];CHECK([store recordForTrack:@"terminated" language:@"vi" error:nil]!=nil);
    // A failed migration never removes the source file.
    NSURL *badDB=[root URLByAppendingPathComponent:@"not-a-database"];CHECK([@"bad"writeToURL:badDB atomically:YES encoding:NSUTF8StringEncoding error:nil]);
    SGTranslationStore *failed=[[SGTranslationStore alloc]initWithURL:badDB legacyDirectory:legacy];NSError *failure=nil;CHECK(![failed putRecord:record(@"x") replace:YES didWrite:NULL error:&failure]&&failure!=nil);
    CHECK([NSFileManager.defaultManager fileExistsAtPath:[legacy URLByAppendingPathComponent:@"broken.vi.json"].path]);
    [NSUserDefaults.standardUserDefaults setObject:@"vi" forKey:SGKeyUILanguage];CHECK([SGLocalized(@"Lyrics")isEqual:@"Lời bài hát"]);CHECK([SGLocalized(@"unregistered technical value")isEqual:@"unregistered technical value"]);
    [NSUserDefaults.standardUserDefaults setObject:@"en" forKey:SGKeyUILanguage];CHECK([SGLocalized(@"Lyrics")isEqual:@"Lyrics"]);
    [NSUserDefaults.standardUserDefaults removeObjectForKey:SGKeyUILanguage];
    NSString *resources=[[@(argv[0]) stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"vi.lproj"];
    NSBundle *vietnamese=[NSBundle bundleWithPath:resources];
    CHECK([[vietnamese localizedStringForKey:@"Lyrics" value:nil table:@"Vitrine"]isEqual:@"Lời bài hát"]);
    CHECK([[vietnamese localizedStringForKey:@"Play or pause ${applicationName}" value:nil table:@"AppShortcuts"]isEqual:@"Phát hoặc tạm dừng ${applicationName}"]);
    if(argc>1) { for(NSString *file in [NSFileManager.defaultManager contentsOfDirectoryAtPath:@(argv[1]) error:nil]) {
        BOOL shouldFail=[file hasPrefix:@"bad-"];BOOL ok=[SGTranslationArchive readURL:[[NSURL fileURLWithPath:@(argv[1])] URLByAppendingPathComponent:file] consume:^BOOL(id row,NSError **e){return [SGTranslationStore validatedRecord:row error:e]!=nil;} progress:nil error:nil];CHECK(ok!=shouldFail);
    }}
    CHECK([store removeTrack:@"track0" language:@"vi" error:nil]);CHECK(![store recordForTrack:@"track0" language:@"vi" error:nil]);
    [NSFileManager.defaultManager removeItemAtURL:root error:nil];
    printf("PASS: %d checks, including 10,001 saves, relaunch, termination, legacy migration, duplicates, JSON and ZIP transfers\n",checks);
}return 0;}
