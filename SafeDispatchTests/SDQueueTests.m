//
//	SDQueueTests.m
//	SafeDispatch
//
//	Created by Justin Spahr-Summers on 30.11.11.
//	Copyright (C) 2012 Justin Spahr-Summers.
//	Released under the MIT license.
//

#import "SDQueueTests.h"
#import "SDQueue.h"
#import <libkern/OSAtomic.h>

@implementation SDQueueTests

- (void)verifyQueueIsCurrent:(SDQueue *)queue {
	__block BOOL executed = NO;
	[queue withGCDQueue:^(dispatch_queue_t dispatchQueue, BOOL isCurrentQueue){
		STAssertTrue(dispatchQueue != NULL, @"");
		STAssertTrue(isCurrentQueue, @"");
		executed = YES;
	}];

	STAssertTrue(executed, @"");
}

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

- (void)testAsynchronousRecursion {
	__block BOOL finished = NO;

	SDQueue *firstQueue = [[SDQueue alloc] init];
	SDQueue *secondQueue = [[SDQueue alloc] init];

	[firstQueue runAsynchronously:^{
		[secondQueue runSynchronously:^{
			[firstQueue runSynchronously:^{
				[secondQueue runSynchronously:^{
					finished = YES;
				}];
			}];
		}];
	}];

	[firstQueue runBarrierSynchronously:^{
	}];

	OSMemoryBarrier();
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

- (void)testPrologueEpilogue {
	__block BOOL prologueDone = NO;
	__block BOOL done = NO;
	__block BOOL epilogueDone = NO;

	SDQueue *queue = [[SDQueue alloc] init];

	queue.prologueBlock = ^{
		STAssertFalse(prologueDone, @"");
		STAssertFalse(done, @"");
		STAssertFalse(epilogueDone, @"");

		prologueDone = YES;
	};

	queue.epilogueBlock = ^{
		STAssertTrue(prologueDone, @"");
		STAssertTrue(done, @"");
		STAssertFalse(epilogueDone, @"");

		epilogueDone = YES;
	};

	[queue runSynchronously:^{
		STAssertTrue(prologueDone, @"");
		STAssertFalse(done, @"");
		STAssertFalse(epilogueDone, @"");

		done = YES;
	}];

	STAssertTrue(prologueDone, @"");
	STAssertTrue(done, @"");
	STAssertTrue(epilogueDone, @"");
}

- (void)testWithGCDQueue {
	SDQueue *unitTestQueue = [SDQueue currentQueue];
	SDQueue *firstQueue = [[SDQueue alloc] init];
	SDQueue *secondQueue = [[SDQueue alloc] init];

	[self verifyQueueIsCurrent:unitTestQueue];

	[firstQueue runSynchronously:^{
		[self verifyQueueIsCurrent:unitTestQueue];
		[self verifyQueueIsCurrent:firstQueue];
		
		[secondQueue runSynchronously:^{
			[self verifyQueueIsCurrent:unitTestQueue];
			[self verifyQueueIsCurrent:firstQueue];
			[self verifyQueueIsCurrent:secondQueue];
		}];
	}];
}

- (void)testRunAfterDelay {
	__block BOOL finished = NO;

	SDQueue *queue = [[SDQueue alloc] init];
	[queue afterDelay:0.1 runAsynchronously:^{
		[self verifyQueueIsCurrent:queue];

		finished = YES;
		OSMemoryBarrier();
	}];

	STAssertFalse(finished, @"");
	[NSThread sleepForTimeInterval:0.15];
	STAssertTrue(finished, @"");
}

- (void)testRethrowsExceptions {
	NSException *testException = [NSException exceptionWithName:@"TestException" reason:nil userInfo:nil];
	SDQueue *queue = [[SDQueue alloc] init];

	@try {
		[queue runSynchronously:^{
			@throw testException;
		}];
	} @catch (NSException *ex) {
		STAssertEqualObjects(ex, testException, @"");
	}
}

- (void)testTargetedQueueDeadlock {
	SDQueue *firstQueue = [[SDQueue alloc] initWithPriority:DISPATCH_QUEUE_PRIORITY_DEFAULT concurrent:NO label:@"1"];
	SDQueue *secondQueue = [[SDQueue alloc] initWithPriority:DISPATCH_QUEUE_PRIORITY_DEFAULT concurrent:NO label:@"2"];
	firstQueue.targetQueue = secondQueue;

	__block BOOL finished = NO;

	[firstQueue runSynchronously:^{
		STAssertEqualObjects(firstQueue.targetQueue, secondQueue, @"");

		[secondQueue runSynchronously:^{
			[firstQueue runSynchronously:^{
				finished = YES;
			}];
		}];
	}];

	STAssertTrue(finished, @"");
}

@end
