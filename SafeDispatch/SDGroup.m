//
//  SDGroup.m
//  SafeDispatch
//
//  Created by Justin Spahr-Summers on 30.11.11.
//  Released into the public domain.
//

#import "SDGroup.h"
#import "SDQueue.h"

@interface SDGroup ()
@property (nonatomic, readonly) dispatch_group_t dispatchGroup;
@end

@implementation SDGroup

#pragma mark Properties

- (BOOL)isCompleted {
    return [self waitUntilDate:nil];
}

#pragma mark Lifecycle

- (id)init {
    return [self initWithDestinationQueue:[SDQueue concurrentGlobalQueueWithPriority:DISPATCH_QUEUE_PRIORITY_DEFAULT]];
}

- (id)initWithDestinationQueue:(SDQueue *)queue; {
    self = [super init];
    if (!self)
        return nil;

    _destinationQueue = queue;
    _dispatchGroup = dispatch_group_create();

    return self;
}

- (void)dealloc {
    dispatch_release(_dispatchGroup);
    _dispatchGroup = NULL;
}

#pragma mark Dispatch

- (void)runAsynchronously:(dispatch_block_t)block; {
    dispatch_block_t copiedBlock = [block copy];

    dispatch_block_t groupBlock = [^{
        copiedBlock();
        dispatch_group_leave(_dispatchGroup);
    } copy];

    dispatch_group_enter(_dispatchGroup);
    [self.destinationQueue runAsynchronously:groupBlock];
}

#pragma mark Completion

- (void)runWhenCompleted:(dispatch_block_t)block; {
    dispatch_queue_t initialQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    dispatch_group_notify(_dispatchGroup, initialQueue, ^{
        [self.destinationQueue runAsynchronously:block];
    });
}

- (void)wait; {
    dispatch_group_wait(_dispatchGroup, DISPATCH_TIME_FOREVER);
}

- (BOOL)waitUntilDate:(NSDate *)date; {
    NSTimeInterval seconds = [date timeIntervalSinceNow];
    int64_t nanoseconds = (int64_t)(seconds * 1e9);

    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, nanoseconds);
    return dispatch_group_wait(_dispatchGroup, timeout) == 0;
}

@end
