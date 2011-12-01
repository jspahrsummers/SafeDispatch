//
//  SDQueue.h
//  SafeDispatch
//
//  Created by Justin Spahr-Summers on 29.11.11.
//  Released into the public domain.
//

#import <Foundation/Foundation.h>

/**
 * Represents a Grand Central Dispatch queue.
 */
@interface SDQueue : NSObject

/**
 * @name Initialization
 */

/**
 * The queue upon which the current code is executing.
 *
 * This may be the <mainQueue>, one of the global queues, or a custom queue.
 */
+ (SDQueue *)currentQueue;

/**
 * Returns the concurrent global queue of the given priority.
 *
 * @param priority The priority of the dispatch queue. Blocks dispatched to
 * a queue with higher priority will be executed before those with a lower
 * priority.
 */
+ (SDQueue *)concurrentGlobalQueueWithPriority:(dispatch_queue_priority_t)priority;

/**
 * Returns the serial dispatch queue associated with the main thread.
 */
+ (SDQueue *)mainQueue;

/**
 * Returns an `SDQueue` wrapping the given GCD queue.
 *
 * @param queue The dispatch queue to wrap.
 * @param concurrent Whether this queue is concurrent.
 * @param private Whether this queue is private (custom).
 */
+ (SDQueue *)queueWithGCDQueue:(dispatch_queue_t)queue concurrent:(BOOL)concurrent private:(BOOL)private;

/**
 * Initializes a serial GCD queue of default priority.
 */
- (id)init;

/**
 * Initializes the receiver to wrap around the given GCD queue.
 *
 * This is the designated initializer for this class.
 *
 * @param queue The dispatch queue to wrap.
 * @param concurrent Whether this queue is concurrent.
 * @param private Whether this queue is private (custom).
 */
- (id)initWithGCDQueue:(dispatch_queue_t)queue concurrent:(BOOL)concurrent private:(BOOL)private;

/**
 * Initializes a serial GCD queue of the given priority.
 *
 * @param priority A priority level for the custom queue. Blocks dispatched to
 * a queue with higher priority will be executed before those with a lower
 * priority.
 */
- (id)initWithPriority:(dispatch_queue_priority_t)priority;

/**
 * Initializes a serial or concurrent GCD queue of the given priority.
 *
 * @param priority A priority level for the custom queue. Blocks dispatched to
 * a queue with higher priority will be executed before those with a lower
 * priority.
 * @param concurrent If `YES`, the returned queue is capable of executing
 * multiple blocks simultaneously. If `NO`, the returned queue executes its
 * blocks in FIFO order.
 */
- (id)initWithPriority:(dispatch_queue_priority_t)priority concurrent:(BOOL)concurrent;

/**
 * @name Queue Attributes
 */

/**
 * Whether this queue is a concurrent queue (`YES`) or a serial queue (`NO`).
 *
 * This will always be `NO` on a queue object retrieved with <currentQueue>.
 */
@property (nonatomic, readonly, getter = isConcurrent) BOOL concurrent;

/**
 * Whether this queue is a private queue (`YES`) or one created by the system
 * (`NO`).
 *
 * This will always be `NO` on a queue object retrieved with <currentQueue>.
 */
@property (nonatomic, readonly, getter = isPrivate) BOOL private;

/**
 * @name Dispatch
 */

/**
 * Adds the given block to the end of the queue and returns immediately.
 *
 * @param block The block to execute when the queue is available.
 */
- (void)runAsynchronously:(dispatch_block_t)block;

/**
 * Adds the given block to the end of the queue and waits for it to execute.
 *
 * If the receiver is a serial queue and (directly or indirectly) already
 * running the calling code, `block` executes immediately without being queued.
 *
 * @param block The block to execute when the queue is available.
 */
- (void)runSynchronously:(dispatch_block_t)block;

/**
 * @name Synchronization
 */

/**
 * Adds a barrier block to the end of the queue and returns immediately.
 *
 * When the block reaches the front of the queue, if the receiver is a serial
 * queue or a private concurrent queue, everything else on the queue waits for
 * the given block to finish executing.
 *
 * @param block The block to execute when the queue is available.
 */
- (void)runBarrierAsynchronously:(dispatch_block_t)block;

/**
 * Adds a barrier block to the end of the queue and waits for it to execute.
 *
 * When the block reaches the front of the queue, if the receiver is a serial
 * queue or a private concurrent queue, everything else on the queue waits for
 * the given block to finish executing.
 *
 * If the receiver is a serial queue and (directly or indirectly) already
 * running the calling code, `block` executes immediately without being queued.
 *
 * @param block The block to execute when the queue is available.
 */
- (void)runBarrierSynchronously:(dispatch_block_t)block;

/**
 * Asynchronously installs a barrier on multiple queues, executing a block when
 * all the queues are synchronized.
 *
 * If this method is the only tool being used to synchronize the actions of
 * multiple queues, it will not deadlock.
 */
+ (void)synchronizeQueues:(NSArray *)queues runAsynchronously:(dispatch_block_t)block;

/**
 * Installs a barrier on multiple queues, waits for all the queues to
 * synchronize, then executes the given block.
 *
 * If any of the given serial queues are (directly or indirectly) already
 * running the calling code, `block` will execute on those queues without being
 * queued at the end.
 *
 * If this method is the only tool being used to synchronize the actions of
 * multiple queues, it will not deadlock.
 */
+ (void)synchronizeQueues:(NSArray *)queues runSynchronously:(dispatch_block_t)block;
@end
