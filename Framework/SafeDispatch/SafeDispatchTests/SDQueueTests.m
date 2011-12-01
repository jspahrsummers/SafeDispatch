//
//  SDQueueTests.m
//  SafeDispatch
//
//  Created by Justin Spahr-Summers on 30.11.11.
//  Released into the public domain.
//

#import "SDQueueTests.h"
#import <SafeDispatch/SDQueue.h>

@implementation SDQueueTests

- (void)testInitialization {
    dispatch_queue_priority_t priorities[] = {
        DISPATCH_QUEUE_PRIORITY_HIGH,
        DISPATCH_QUEUE_PRIORITY_DEFAULT,
        DISPATCH_QUEUE_PRIORITY_LOW,
        DISPATCH_QUEUE_PRIORITY_BACKGROUND
    };

    STAssertNotNil([SDQueue currentQueue], @"");
    STAssertNotNil([SDQueue mainQueue], @"");
    STAssertNotNil([[SDQueue alloc] init], @"");

    for (size_t i = 0;i < sizeof(priorities) / sizeof(*priorities);++i) {
        dispatch_queue_priority_t priority = priorities[i];

        STAssertNotNil([SDQueue concurrentGlobalQueueWithPriority:priority], @"");
        STAssertNotNil([[SDQueue alloc] initWithPriority:priority], @"");
        STAssertNotNil([[SDQueue alloc] initWithPriority:priority concurrent:YES], @"");
    }
}

- (void)testSingleRecursion {
    __block BOOL finished = NO;

    SDQueue *firstQueue = [[SDQueue alloc] init];
    SDQueue *secondQueue = [[SDQueue alloc] init];

    [firstQueue runSynchronously:^{
        [secondQueue runSynchronously:^{
            [firstQueue runSynchronously:^{
                finished = YES;
            }];
        }];
    }];

    STAssertTrue(finished, @"");
}

- (void)testMultipleRecursion {
    __block BOOL finished = NO;

    SDQueue *firstQueue = [[SDQueue alloc] init];
    SDQueue *secondQueue = [[SDQueue alloc] init];

    [firstQueue runSynchronously:^{
        [secondQueue runSynchronously:^{
            [SDQueue synchronizeQueues:[NSArray arrayWithObjects:firstQueue, secondQueue, nil] runSynchronously:^{
                finished = YES;
            }];
        }];
    }];

    STAssertTrue(finished, @"");
}

@end
