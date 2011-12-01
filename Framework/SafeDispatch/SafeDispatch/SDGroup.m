//
//  SDGroup.m
//  SafeDispatch
//
//  Created by Justin Spahr-Summers on 30.11.11.
//  Released into the public domain.
//

#import <SafeDispatch/SDGroup.h>
#import <SafeDispatch/SDQueue.h>

@interface SDGroup ()
@property (nonatomic, readonly) dispatch_group_t dispatchGroup;
@end

@implementation SDGroup

#pragma mark Properties

@synthesize destinationQueue = m_destinationQueue;
@synthesize dispatchGroup = m_dispatchGroup;

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

    m_destinationQueue = queue;
    m_dispatchGroup = dispatch_group_create();

    return self;
}

- (void)dealloc {
    dispatch_release(m_dispatchGroup);
    m_dispatchGroup = NULL;
}

#pragma mark Dispatch

- (void)runAsynchronously:(dispatch_block_t)block; {
    dispatch_group_enter(m_dispatchGroup);

    dispatch_block_t groupBlock = ^{
        block();
        dispatch_group_leave(m_dispatchGroup);
    };

    [self.destinationQueue runAsynchronously:groupBlock];
}

#pragma mark Completion

- (void)runWhenCompleted:(dispatch_block_t)block; {
    dispatch_queue_t initialQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);

    dispatch_group_notify(m_dispatchGroup, initialQueue, ^{
        [self.destinationQueue runAsynchronously:block];
    });
}

- (void)wait; {
    dispatch_group_wait(m_dispatchGroup, DISPATCH_TIME_FOREVER);
}

- (BOOL)waitUntilDate:(NSDate *)date; {
    NSTimeInterval seconds = [date timeIntervalSinceNow];
    int64_t nanoseconds = (int64_t)(seconds * 1e9);

    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, nanoseconds);
    return dispatch_group_wait(m_dispatchGroup, timeout) == 0;
}

@end
