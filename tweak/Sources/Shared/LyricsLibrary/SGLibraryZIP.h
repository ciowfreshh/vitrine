#import <Foundation/Foundation.h>

// Only the manifest and track JSON entries of the library format are accepted. No filesystem extraction.
@interface SGLibraryZIP : NSObject
- (instancetype)initWithData:(NSData *)data error:(NSError **)error;
@property (nonatomic, readonly) NSArray<NSString *> *names;
- (NSData *)dataForName:(NSString *)name error:(NSError **)error;
@end

@interface SGLibraryZIPWriter : NSObject
- (BOOL)addData:(NSData *)data name:(NSString *)name error:(NSError **)error;
- (NSData *)finish;
@end
