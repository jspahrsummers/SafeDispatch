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
