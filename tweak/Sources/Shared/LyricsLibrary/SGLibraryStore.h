#import <Foundation/Foundation.h>

// A store is used on one serial queue. A track write is atomic and recoverable independently.
@interface SGLibraryStore : NSObject
- (instancetype)initWithDirectory:(NSURL *)directory;
- (NSArray<NSDictionary *> *)summaries;
- (NSDictionary *)track:(NSString *)trackID error:(NSError **)error;
- (BOOL)save:(NSDictionary *)track error:(NSError **)error;
- (BOOL)remove:(NSString *)trackID error:(NSError **)error;
- (BOOL)exportIDs:(NSArray<NSString *> *)ids toURL:(NSURL *)url error:(NSError **)error;
- (NSDictionary *)importURL:(NSURL *)url error:(NSError **)error;
@end

SGLibraryStore *SGLibraryLocalStore(void);
dispatch_queue_t SGLibraryQueue(void);
extern NSNotificationName const SGLibraryDidChange;
