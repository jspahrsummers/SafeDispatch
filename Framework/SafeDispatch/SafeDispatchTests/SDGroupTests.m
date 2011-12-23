//
//  SDGroupTests.m
//  SafeDispatch
//
//  Created by Justin Spahr-Summers on 30.11.11.
//  Released into the public domain.
//

#import "SDGroupTests.h"
#import "SafeDispatch.h"
#import <libkern/OSAtomic.h>

@implementation SDGroupTests

- (void)testSimpleGroup {
    __block BOOL doneA = NO;
    __block BOOL doneB = NO;

    SDQueue *queue = [SDQueue concurrentGlobalQueue];
    SDGroup *group = [[SDGroup alloc] initWithDestinationQueue:queue];

    [group runAsynchronously:^{
        [NSThread sleepForTimeInterval:0.01];
        doneA = YES;
    }];

    [group runAsynchronously:^{
        doneB = YES;
        [NSThread sleepForTimeInterval:0.01];
    }];

    [group wait];

    OSMemoryBarrier();
    STAssertTrue(doneA, @"");
    STAssertTrue(doneB, @"");
}

- (void)testNotification {
    __block BOOL done = NO;
    __block BOOL notified = NO;

    SDQueue *queue = [[SDQueue alloc] init];
    SDGroup *group = [[SDGroup alloc] initWithDestinationQueue:queue];

    [group runAsynchronously:^{
        [NSThread sleepForTimeInterval:0.01];
        done = YES;
    }];

    [group runWhenCompleted:^{
        STAssertTrue(done, @"");
        notified = YES;
    }];

    [group wait];
    [NSThread sleepForTimeInterval:0.05];

    [queue runBarrierSynchronously:^{
        STAssertTrue(done, @"");
        STAssertTrue(notified, @"");
    }];
}

@end
