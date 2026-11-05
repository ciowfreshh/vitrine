#import <UIKit/UIKit.h>
@class SGModRow;
void SGBatchQueueStart(NSString *uri, UIWindow *window);
BOOL SGBatchQueueRunning(void);
SGModRow *SGBatchQueueRow(void);
UIViewController *SGBatchQueuePage(void);
