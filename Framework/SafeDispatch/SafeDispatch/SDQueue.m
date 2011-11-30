//
//  SDQueue.m
//  SafeDispatch
//
//  Created by Justin Spahr-Summers on 29.11.11.
//  Released into the public domain.
//

#import <SafeDispatch/SDQueue.h>

typedef struct sd_dispatch_queue_stack {
    dispatch_queue_t queue;
    struct sd_dispatch_queue_stack *next;
} sd_dispatch_queue_stack;

// used with dispatch_set_queue_specific()
static const void * const SDDispatchQueueStackKey = "SDDispatchQueueStack";

@interface SDQueue () {
    dispatch_queue_t m_dispatchQueue;
}

@property (readonly, getter = isCurrentQueue) BOOL currentQueue;
@end

@implementation SDQueue

#pragma mark Properties

- (BOOL)isCurrentQueue {
    sd_dispatch_queue_stack *stack = dispatch_get_specific(SDDispatchQueueStackKey);
    while (stack) {
        if (stack->queue == m_dispatchQueue)
            return YES;

        stack = stack->next;
    }

    return NO;
}

#pragma mark Lifecycle

- (id)init; {
    return [self initWithPriority:DISPATCH_QUEUE_PRIORITY_DEFAULT];
}

- (id)initWithGCDQueue:(dispatch_queue_t)queue; {
    self = [super init];
    if (!self || !queue)
        return nil;

    dispatch_retain(queue);
    m_dispatchQueue = queue;

    return self;
}

- (id)initWithPriority:(dispatch_queue_priority_t)priority; {
    return [self initWithPriority:priority concurrent:NO];
}

- (id)initWithPriority:(dispatch_queue_priority_t)priority concurrent:(BOOL)concurrent; {
    dispatch_queue_attr_t attribute = (concurrent ? DISPATCH_QUEUE_CONCURRENT : DISPATCH_QUEUE_SERIAL);

    // TODO: add label support
    dispatch_queue_t queue = dispatch_queue_create(NULL, attribute);
    self = [self initWithGCDQueue:queue];
    dispatch_release(queue);

    return self;
}

- (void)dealloc {
    // attempt to flush the queue to avoid a crash from releasing it while it
    // still has blocks
    dispatch_barrier_sync(m_dispatchQueue, ^{});

    dispatch_release(m_dispatchQueue);
}

@end
