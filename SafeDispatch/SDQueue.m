//
//	SDQueue.m
//	SafeDispatch
//
//	Created by Justin Spahr-Summers on 29.11.11.
//	Released into the public domain.
//

#import "SDQueue.h"
#import <libkern/OSAtomic.h>

typedef struct sd_dispatch_queue_stack {
	dispatch_queue_t queue;
	struct sd_dispatch_queue_stack *next;
} sd_dispatch_queue_stack;

// used with dispatch_set_queue_specific()
static const void * const SDDispatchQueueStackKey = &SDDispatchQueueStackKey;
static const void * const SDTargetQueueKey = &SDTargetQueueKey;

@interface SDQueue () {
// public for the compareQueues() function
@public
	/*
	 * The underlying GCD queue.
	 */
	dispatch_queue_t _dispatchQueue;

	/*
	 * The receiver's target queue should not be changed while this value is
	 * greater than zero.
	 *
	 * This value should only be read while the <_retargetingCondition> is held.
	 */
	NSUInteger _retargetingSuspensionCount;

	/*
	 * A lock used to synchronize the <_retargetingSuspensionCount>, or `nil` if
	 * the receiver is a global queue.
	 */
	NSCondition *_retargetingCondition;
}

/*
 * Returns an `SDQueue` wrapping the given GCD queue.
 *
 * @param queue The dispatch queue to wrap.
 * @param concurrent Whether this queue is concurrent.
 * @param private Whether this queue is private (custom).
 */
+ (SDQueue *)queueWithGCDQueue:(dispatch_queue_t)queue concurrent:(BOOL)concurrent private:(BOOL)private;

/*
 * Initializes the receiver to wrap around the given GCD queue.
 *
 * This is the designated initializer for this class.
 *
 * @param queue The dispatch queue to wrap.
 * @param concurrent Whether this queue is concurrent.
 * @param private Whether this queue is private (custom).
 */
- (id)initWithGCDQueue:(dispatch_queue_t)queue concurrent:(BOOL)concurrent private:(BOOL)private;

/*
 * Enumerates the receiver, followed by any queue that the receiver targets,
 * followed by any queue that queue targets, etc.
 */
- (void)enumerateTargetQueuesUsingBlock:(void (^)(SDQueue *queue, BOOL *stop))block;
@end

/*
 * Sorting function for use with `-[NSArray sortedArrayUsingFunction:context:]`.
 *
 * This applies a deterministic total ordering to SDQueues based on their
 * underlying GCD queues, and so is used to implement multi-queue
 * synchronization (where an arbitrary ordering could easily lead to deadlocks).
 */
static NSInteger compareQueues (SDQueue *queueA, SDQueue *queueB, void *context) {
	dispatch_queue_t dispatchA = queueA->_dispatchQueue;
	dispatch_queue_t dispatchB = queueB->_dispatchQueue;

	if (dispatchA < dispatchB)
		return NSOrderedAscending;
	else if (dispatchA > dispatchB)
		return NSOrderedDescending;
	else
		return NSOrderedSame;
}

/*
 * Returns whether `dispatchQueueA` is or targets `dispatchQueueB`, directly or indirectly.
 */
static BOOL queueTargetsQueue (dispatch_queue_t dispatchQueueA, dispatch_queue_t dispatchQueueB) {
	if (dispatchQueueA == dispatchQueueB) {
		return YES;
	}

	SDQueue *queue = (__bridge id)dispatch_queue_get_specific(dispatchQueueA, SDTargetQueueKey);
	if (!queue) {
		return NO;
	}

	return queueTargetsQueue(queue->_dispatchQueue, dispatchQueueB);
}

/*
 * Returns whether either of the given queues targets the other (and is thus
 * equivalent for call stack purposes).
 */
static BOOL queuesAreEquivalent (dispatch_queue_t dispatchQueueA, dispatch_queue_t dispatchQueueB) {
	// seems like there's a more efficient way to do this
	return queueTargetsQueue(dispatchQueueA, dispatchQueueB) || queueTargetsQueue(dispatchQueueB, dispatchQueueA);
}

// Destructor stub for dispatch_queue_set_specific()
static void SDQueueRelease (void *queue) {
	// although CFRelease() will crash if given NULL, dispatch_queue_set_specific()
	// will never invoke it if the queue is nil
	CFRelease(queue);
}

@implementation SDQueue

#pragma mark Properties

- (SDQueue *)targetQueue {
	return (__bridge id)dispatch_queue_get_specific(_dispatchQueue, SDTargetQueueKey);
}

- (void)setTargetQueue:(SDQueue *)queue {
	NSAssert(self.private, @"Global queue %@ cannot be retargeted", self);

	// set up an intermediate queue which will target the correct queue
	//
	// the use of an intermediate queue allows us to atomically swap in the new
	// target and update the target queue reference simultaneously
	dispatch_queue_attr_t attribute = (self.concurrent ? DISPATCH_QUEUE_CONCURRENT : DISPATCH_QUEUE_SERIAL);
	dispatch_queue_t intermediateQueue = dispatch_queue_create("org.jspahrsummers.SafeDispatch.intermediateTargetQueue", attribute);

	dispatch_suspend(intermediateQueue);
	dispatch_set_target_queue(intermediateQueue, (queue ? queue->_dispatchQueue : NULL));

	// first order of business on the new queue will be to update the target
	// queue reference
	dispatch_barrier_async(intermediateQueue, ^{
		dispatch_queue_set_specific(_dispatchQueue, SDTargetQueueKey, (__bridge_retained void *)queue, &SDQueueRelease);

		// signal any other thread that might be waiting to retarget
		[_retargetingCondition signal];
		[_retargetingCondition unlock];
	});

	[_retargetingCondition lock];
	while (_retargetingSuspensionCount > 0)
		[_retargetingCondition wait];

	dispatch_set_target_queue(_dispatchQueue, intermediateQueue);

	dispatch_resume(intermediateQueue);
	dispatch_release(intermediateQueue);
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
	_dispatchQueue = queue;

	if (private)
		_retargetingCondition = [[NSCondition alloc] init];

	_concurrent = concurrent;
	_private = private;

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

	dispatch_queue_t queue = dispatch_queue_create(label.UTF8String, attribute);
	self = [self initWithGCDQueue:queue concurrent:concurrent private:YES];
	dispatch_release(queue);

	SDQueue *globalQueue = [SDQueue concurrentGlobalQueueWithPriority:priority];
	if (self == nil || globalQueue == nil) return nil;

	// we don't need all the craziness of -setTargetQueue: because
	// synchronization is not necessary while initializing
	dispatch_set_target_queue(_dispatchQueue, globalQueue->_dispatchQueue);
	dispatch_queue_set_specific(_dispatchQueue, SDTargetQueueKey, (__bridge_retained void *)globalQueue, &SDQueueRelease);

	return self;
}

- (void)dealloc {
	if (self.private) {
		// asynchronously flush the queue, to avoid any crashes from releasing
		// it while it still has blocks
		dispatch_barrier_async(_dispatchQueue, ^{});
	}

	dispatch_release(_dispatchQueue);
	_dispatchQueue = NULL;
}

#pragma mark NSObject overrides

- (NSString *)description {
	const char *label = dispatch_queue_get_label(_dispatchQueue);

	SDQueue *target = self.targetQueue;
	const char *targetLabel = (target ? dispatch_queue_get_label(target->_dispatchQueue) : NULL);

	return [NSString stringWithFormat:@"<%@: %p>{ label = %s, target = %s }", self.class, self, label, targetLabel];
}

- (NSUInteger)hash {
	// shift off some low bits that will be very similar
	// (this is still a really crappy hash, but SDQueues probably shouldn't be
	// in hashed collections anyways)
	return (NSUInteger)_dispatchQueue >> 4;
}

- (BOOL)isEqual:(SDQueue *)queue {
	if (![queue isKindOfClass:[SDQueue class]])
		return NO;

	return _dispatchQueue == queue->_dispatchQueue;
}

#pragma mark Targeting

- (void)suspendRetargeting {
	if (_retargetingCondition) {
		[_retargetingCondition lock];
		_retargetingSuspensionCount++;
		[_retargetingCondition unlock];
	}

	[self.targetQueue suspendRetargeting];
}

- (void)resumeRetargeting {
	// resume from the inside out (opposite order of suspension)
	[self.targetQueue resumeRetargeting];

	if (_retargetingCondition) {
		[_retargetingCondition lock];
		NSAssert(_retargetingSuspensionCount > 0, @"Unbalanced decrement of _retargetingSuspensionCount on %@", self);

		_retargetingSuspensionCount--;
		[_retargetingCondition signal];
		[_retargetingCondition unlock];
	}
}

- (void)enumerateTargetQueuesUsingBlock:(void (^)(SDQueue *queue, BOOL *stop))block {
	SDQueue *queue = self;
	do {
		BOOL stop = NO;
		block(queue, &stop);
		
		if (stop) {
			return;
		}

		queue = queue.targetQueue;
	} while (queue);
}

- (BOOL)targetsGCDQueue:(dispatch_queue_t)GCDQueue {
	__block BOOL result = NO;

	[self enumerateTargetQueuesUsingBlock:^(SDQueue *queue, BOOL *stop){
		if (queue->_dispatchQueue == GCDQueue) {
			result = YES;
			*stop = YES;
		}
	}];

	return result;
}

- (BOOL)isCurrentQueue {
	// if we're running on the main thread, the main queue is assumed to be
	// current (even if we're nominally on another queue)
	if ([NSThread isMainThread] && [self targetsGCDQueue:dispatch_get_main_queue()])
		return YES;

	if (queuesAreEquivalent(dispatch_get_current_queue(), _dispatchQueue))
		return YES;

	// see if this queue is anywhere in the call stack (that we've tracked
	// using SDQueue, anyways)
	sd_dispatch_queue_stack *stack = dispatch_get_specific(SDDispatchQueueStackKey);
	while (stack) {
		if (queuesAreEquivalent(stack->queue, _dispatchQueue))
			return YES;

		stack = stack->next;
	}

	return NO;
}

#pragma mark Dispatch

- (void)withGCDQueue:(void (^)(dispatch_queue_t queue, BOOL isCurrentQueue))block {
	dispatch_retain(_dispatchQueue);
	[self suspendRetargeting];

	@try {
		block(_dispatchQueue, [self isCurrentQueue]);
	} @finally {
		[self resumeRetargeting];
		dispatch_release(_dispatchQueue);
	}
}

+ (void)synchronizeQueues:(NSArray *)queues runAsynchronously:(dispatch_block_t)block; {
	NSArray *sortedQueues = [queues sortedArrayUsingFunction:&compareQueues context:NULL];
	NSUInteger count = sortedQueues.count;

	__block __weak dispatch_block_t recursiveJumpBlock = NULL;
	__block NSUInteger currentIndex = 0;

	// this block will be invoked recursively, to synchronously jump to each
	// successive queue, so that they're all blocked while we execute the given block
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

	// start on the first queue asynchronously (so we return immediately)
	SDQueue *firstQueue = [sortedQueues objectAtIndex:0];
	[firstQueue runBarrierAsynchronously:jumpBlock];
}

+ (void)synchronizeQueues:(NSArray *)queues runSynchronously:(dispatch_block_t)block; {
	NSArray *sortedQueues = [queues sortedArrayUsingFunction:&compareQueues context:NULL];
	NSUInteger count = sortedQueues.count;

	__block __weak dispatch_block_t recursiveJumpBlock = NULL;
	__block NSUInteger nextIndex = 0;

	// this block will be invoked recursively, to synchronously jump to each
	// successive queue, so that they're all blocked while we execute the given block
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

	// unlike the asynchronous case, we can start the recursion directly, with
	// no copying to the heap, because our current stack frame will be reachable
	// all the way down
	jumpBlock();
}

- (void)callDispatchFunction:(void (*)(dispatch_queue_t, dispatch_block_t))function withSynchronousBlock:(dispatch_block_t)block; {
	if (!block)
		return;

	dispatch_block_t prologue = self.prologueBlock;
	dispatch_block_t epilogue = self.epilogueBlock;

	__block NSException *thrownException = nil;

	[self withGCDQueue:^(dispatch_queue_t queue, BOOL isCurrentQueue){
		dispatch_queue_t realCurrentQueue = dispatch_get_current_queue();

		dispatch_block_t trampoline = ^{
			sd_dispatch_queue_stack *oldStack = NULL;

			// if we're just now jumping to our dispatch queue, we need to copy over
			// the call stack of queues, so that -isCurrentQueue works properly for
			// all of those queues
			if (!isCurrentQueue) {
				// get the stack of queues from the dispatch queue we were just on,
				// and add it to our stack
				sd_dispatch_queue_stack head = {
					.queue = realCurrentQueue,
					.next = dispatch_queue_get_specific(realCurrentQueue, SDDispatchQueueStackKey)
				};
				
				// then save that as the stack of our current queue (preserving the
				// original value, to be restored once this block is popped)
				oldStack = dispatch_get_specific(SDDispatchQueueStackKey);

				dispatch_queue_set_specific(queue, SDDispatchQueueStackKey, &head, NULL);
			}

			@try {
				// although this will catch exceptions coming from the prologue or
				// epilogue blocks, we don't really support it (since the
				// asynchronous case would have different behavior)
				if (prologue)
					prologue();

				block();

				if (epilogue)
					epilogue();
			} @catch (NSException *ex) {
				// exceptions aren't allowed to escape a dispatch block, so catch it
				// and re-throw once we're off the queue
				thrownException = ex;
			}

			if (!isCurrentQueue) {
				// restore the original stack
				dispatch_queue_set_specific(queue, SDDispatchQueueStackKey, oldStack, NULL);
			}
		};

		if (isCurrentQueue)
			trampoline();
		else
			function(queue, trampoline);
	}];
	
	if (thrownException) {
		@throw thrownException;
	}
}

- (dispatch_block_t)asynchronousTrampolineWithBlock:(dispatch_block_t)block; {
	NSParameterAssert(block);

	dispatch_block_t prologue = self.prologueBlock;
	dispatch_block_t epilogue = self.epilogueBlock;

	dispatch_block_t copiedBlock = [block copy];

	// unlike the synchronous case, we don't set up a queue stack, because the
	// very nature of asynchronous dispatch means that this will be the first
	// (current) queue on any stack (and the reference to it will be preserved
	// if a block is dispatched synchronously later)
	return [^{
		NSAssert1(self.concurrent || !dispatch_get_specific(SDDispatchQueueStackKey), @"%@ should not have a queue stack before executing an asynchronous block", self);

		if (prologue)
			prologue();

		copiedBlock();

		if (epilogue)
			epilogue();

		NSAssert1(self.concurrent || !dispatch_get_specific(SDDispatchQueueStackKey), @"%@ should not have a queue stack after executing an asynchronous block", self);
	} copy];
}

- (void)afterDelay:(NSTimeInterval)delay runAsynchronously:(dispatch_block_t)block; {
	NSParameterAssert(delay >= 0);

	if (!block)
		return;

	dispatch_block_t trampoline = [self asynchronousTrampolineWithBlock:block];
	dispatch_time_t time = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC));

	dispatch_after(time, _dispatchQueue, trampoline);
}

- (void)runAsynchronously:(dispatch_block_t)block; {
	if (!block)
		return;

	dispatch_block_t trampoline = [self asynchronousTrampolineWithBlock:block];
	dispatch_async(_dispatchQueue, trampoline);
}

- (void)runAsynchronouslyIfNotCurrent:(dispatch_block_t)block; {
	[self withGCDQueue:^(dispatch_queue_t queue, BOOL isCurrentQueue){
		if (isCurrentQueue) {
			[self runSynchronously:block];
		} else {
			[self runAsynchronously:block];
		}
	}];
}

- (void)runBarrierAsynchronously:(dispatch_block_t)block; {
	NSAssert1(self.private || !self.concurrent, @"%s should not be used with a global concurrent queue", __func__);

	if (!block)
		return;

	dispatch_block_t trampoline = [self asynchronousTrampolineWithBlock:block];
	dispatch_barrier_async(_dispatchQueue, trampoline);
}

- (void)runBarrierSynchronously:(dispatch_block_t)block; {
	NSAssert1(self.private || !self.concurrent, @"%s should not be used with a global concurrent queue", __func__);

	[self callDispatchFunction:&dispatch_barrier_sync withSynchronousBlock:block];
}

- (void)runSynchronously:(dispatch_block_t)block; {
	[self callDispatchFunction:&dispatch_sync withSynchronousBlock:block];
}

@end
