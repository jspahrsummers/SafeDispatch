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

@end
