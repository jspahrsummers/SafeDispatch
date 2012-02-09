//
//  SDQueue.m
//  SafeDispatch
//
//  Created by Justin Spahr-Summers on 29.11.11.
//  Released into the public domain.
//

#import "SDQueue.h"

typedef struct sd_dispatch_queue_stack {
    dispatch_queue_t queue;
    struct sd_dispatch_queue_stack *next;
} sd_dispatch_queue_stack;

// used with dispatch_set_queue_specific()
static const void * const SDDispatchQueueStackKey = "SDDispatchQueueStack";

@interface SDQueue ()
@property (nonatomic, readonly) dispatch_queue_t dispatchQueue;

- (void)callDispatchFunction:(void (*)(dispatch_queue_t, dispatch_block_t))function withSynchronousBlock:(dispatch_block_t)block;
- (void)callDispatchFunction:(void (*)(dispatch_queue_t, dispatch_block_t))function withAsynchronousBlock:(dispatch_block_t)block;
@end

@implementation SDQueue

#pragma mark Properties

@synthesize dispatchQueue = m_dispatchQueue;
@synthesize concurrent = m_concurrent;
@synthesize private = m_private;
@synthesize prologueBlock = m_prologueBlock;
@synthesize epilogueBlock = m_epilogueBlock;

- (BOOL)isCurrentQueue {
    if (dispatch_get_current_queue() == m_dispatchQueue)
        return YES;

    sd_dispatch_queue_stack *stack = dispatch_get_specific(SDDispatchQueueStackKey);
    while (stack) {
        if (stack->queue == m_dispatchQueue)
            return YES;

        stack = stack->next;
    }

    return NO;
}

#pragma mark Lifecycle

+ (SDQueue *)concurrentGlobalQueue; {
    static SDQueue *queue = nil;
    static dispatch_once_t pred;

    dispatch_once(&pred, ^{
        queue = [self concurrentGlobalQueueWithPriority:DISPATCH_QUEUE_PRIORITY_DEFAULT];
    });

    return queue;
}

+ (SDQueue *)currentQueue; {
    return [self queueWithGCDQueue:dispatch_get_current_queue() concurrent:NO private:NO];
}

+ (SDQueue *)concurrentGlobalQueueWithPriority:(dispatch_queue_priority_t)priority; {
    dispatch_queue_t queue = dispatch_get_global_queue(priority, 0);
    return [self queueWithGCDQueue:queue concurrent:YES private:NO];
}

+ (SDQueue *)mainQueue; {
    static SDQueue *queue = nil;
    static dispatch_once_t pred;

    dispatch_once(&pred, ^{
        queue = [self queueWithGCDQueue:dispatch_get_main_queue() concurrent:NO private:NO];
    });

    return queue;
}

+ (SDQueue *)queueWithGCDQueue:(dispatch_queue_t)queue concurrent:(BOOL)concurrent private:(BOOL)private; {
    return [[self alloc] initWithGCDQueue:queue concurrent:concurrent private:private];
}

- (id)init; {
    return [self initWithPriority:DISPATCH_QUEUE_PRIORITY_DEFAULT];
}

- (id)initWithGCDQueue:(dispatch_queue_t)queue concurrent:(BOOL)concurrent private:(BOOL)private; {
    self = [super init];
    if (!self || !queue)
        return nil;

    dispatch_retain(queue);
    m_dispatchQueue = queue;

    m_concurrent = concurrent;
    m_private = private;

    return self;
}

- (id)initWithPriority:(dispatch_queue_priority_t)priority; {
    return [self initWithPriority:priority concurrent:NO];
}

- (id)initWithPriority:(dispatch_queue_priority_t)priority concurrent:(BOOL)concurrent; {
    return [self initWithPriority:priority concurrent:concurrent label:@"org.jspahrsummers.SafeDispatch.customQueue"];
}

- (id)initWithPriority:(dispatch_queue_priority_t)priority concurrent:(BOOL)concurrent label:(NSString *)label; {
    dispatch_queue_attr_t attribute = (concurrent ? DISPATCH_QUEUE_CONCURRENT : DISPATCH_QUEUE_SERIAL);

    dispatch_queue_t queue = dispatch_queue_create([label UTF8String], attribute);
    dispatch_set_target_queue(queue, dispatch_get_global_queue(priority, 0));

    self = [self initWithGCDQueue:queue concurrent:concurrent private:YES];
    dispatch_release(queue);

    return self;
}

- (void)dealloc {
    if (self.private) {
        // attempt to flush the queue to avoid a crash from releasing it while it
        // still has blocks
        dispatch_barrier_sync(m_dispatchQueue, ^{});
    }

    dispatch_release(m_dispatchQueue);
    m_dispatchQueue = NULL;
}

#pragma mark NSObject overrides

- (NSUInteger)hash {
    return (NSUInteger)m_dispatchQueue;
}

- (BOOL)isEqual:(SDQueue *)queue {
    if (![queue isKindOfClass:[SDQueue class]])
        return NO;

    return self.dispatchQueue == queue.dispatchQueue;
}

#pragma mark Dispatch

+ (void)synchronizeQueues:(NSArray *)queues runAsynchronously:(dispatch_block_t)block; {
    NSArray *sortedQueues = [queues sortedArrayUsingComparator:^ NSComparisonResult (SDQueue *queueA, SDQueue *queueB){
        dispatch_queue_t dispatchA = queueA.dispatchQueue;
        dispatch_queue_t dispatchB = queueB.dispatchQueue;

        if (dispatchA < dispatchB)
            return NSOrderedAscending;
        else if (dispatchA > dispatchB)
            return NSOrderedDescending;
        else
            return NSOrderedSame;
    }];

    NSUInteger count = [sortedQueues count];

    __block __weak dispatch_block_t recursiveJumpBlock = NULL;
    __block NSUInteger currentIndex = 0;

    dispatch_block_t jumpBlock = [^{
        if (currentIndex >= count - 1) {
            block();
        } else {
            ++currentIndex;

            SDQueue *queue = [sortedQueues objectAtIndex:currentIndex];
            [queue runBarrierSynchronously:recursiveJumpBlock];
        }
    } copy];

    recursiveJumpBlock = jumpBlock;

    SDQueue *firstQueue = [sortedQueues objectAtIndex:0];
    [firstQueue runBarrierAsynchronously:jumpBlock];
}

+ (void)synchronizeQueues:(NSArray *)queues runSynchronously:(dispatch_block_t)block; {
    NSArray *sortedQueues = [queues sortedArrayUsingComparator:^ NSComparisonResult (SDQueue *queueA, SDQueue *queueB){
        dispatch_queue_t dispatchA = queueA.dispatchQueue;
        dispatch_queue_t dispatchB = queueB.dispatchQueue;

        if (dispatchA < dispatchB)
            return NSOrderedAscending;
        else if (dispatchA > dispatchB)
            return NSOrderedDescending;
        else
            return NSOrderedSame;
    }];

    NSUInteger count = [sortedQueues count];

    __block __weak dispatch_block_t recursiveJumpBlock = NULL;
    __block NSUInteger nextIndex = 0;

    dispatch_block_t jumpBlock = ^{
        if (nextIndex >= count) {
            block();
        } else {
            SDQueue *queue = [sortedQueues objectAtIndex:nextIndex];
            ++nextIndex;

            [queue runBarrierSynchronously:recursiveJumpBlock];
        }
    };

    recursiveJumpBlock = jumpBlock;
    jumpBlock();
}

- (void)callDispatchFunction:(void (*)(dispatch_queue_t, dispatch_block_t))function withSynchronousBlock:(dispatch_block_t)block; {
    if (!block)
        return;

    dispatch_block_t prologue = self.prologueBlock;
    dispatch_block_t epilogue = self.epilogueBlock;

    BOOL isCurrentQueue = self.currentQueue;
    dispatch_queue_t realCurrentQueue = dispatch_get_current_queue();

    dispatch_queue_t trampolineQueue;
    if (isCurrentQueue)
        trampolineQueue = realCurrentQueue;
    else
        trampolineQueue = m_dispatchQueue;

    dispatch_block_t trampoline = ^{
        sd_dispatch_queue_stack *next;

        // it's cheaper to get thread-specific data from the current queue than
        // an arbitrary one
        if (trampolineQueue == realCurrentQueue)
            next = dispatch_get_specific(SDDispatchQueueStackKey);
        else
            next = dispatch_queue_get_specific(realCurrentQueue, SDDispatchQueueStackKey);

        sd_dispatch_queue_stack head = {
            .queue = realCurrentQueue,
            .next = next
        };

        sd_dispatch_queue_stack *oldStack;
        
        // it's cheaper to get thread-specific data from the current queue than
        // an arbitrary one
        if (trampolineQueue == m_dispatchQueue) {
            oldStack = dispatch_get_specific(SDDispatchQueueStackKey);
        } else {
            oldStack = dispatch_queue_get_specific(m_dispatchQueue, SDDispatchQueueStackKey);
        }

        dispatch_queue_set_specific(m_dispatchQueue, SDDispatchQueueStackKey, &head, NULL);

        if (prologue)
            prologue();

        block();

        if (epilogue)
            epilogue();

        dispatch_queue_set_specific(m_dispatchQueue, SDDispatchQueueStackKey, oldStack, NULL);
    };

    if (isCurrentQueue)
        trampoline();
    else
        function(m_dispatchQueue, trampoline);
}

- (void)callDispatchFunction:(void (*)(dispatch_queue_t, dispatch_block_t))function withAsynchronousBlock:(dispatch_block_t)block; {
    if (!block)
        return;

    dispatch_block_t prologue = self.prologueBlock;
    dispatch_block_t epilogue = self.epilogueBlock;

    dispatch_block_t copiedBlock = [block copy];

    dispatch_block_t trampoline = [^{
        NSAssert1(self.concurrent || !dispatch_get_specific(SDDispatchQueueStackKey), @"%@ should not have a queue stack before executing an asynchronous block", self);

        if (prologue)
            prologue();

        copiedBlock();

        if (epilogue)
            epilogue();

        NSAssert1(self.concurrent || !dispatch_get_specific(SDDispatchQueueStackKey), @"%@ should not have a queue stack after executing an asynchronous block", self);
    } copy];

    function(m_dispatchQueue, trampoline);
}

- (void)runAsynchronously:(dispatch_block_t)block; {
    [self callDispatchFunction:&dispatch_async withAsynchronousBlock:block];
}

- (void)runBarrierAsynchronously:(dispatch_block_t)block; {
    NSAssert1(self.private || !self.concurrent, @"%s should not be used with a global concurrent queue", __func__);

    [self callDispatchFunction:&dispatch_barrier_async withAsynchronousBlock:block];
}

- (void)runBarrierSynchronously:(dispatch_block_t)block; {
    NSAssert1(self.private || !self.concurrent, @"%s should not be used with a global concurrent queue", __func__);

    [self callDispatchFunction:&dispatch_barrier_sync withSynchronousBlock:block];
}

- (void)runSynchronously:(dispatch_block_t)block; {
    [self callDispatchFunction:&dispatch_sync withSynchronousBlock:block];
}

@end
