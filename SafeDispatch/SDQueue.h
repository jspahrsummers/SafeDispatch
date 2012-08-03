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
 *
 * Unless otherwise specified in the documentation (e.g., for
 * -runSynchronously:), methods of this class are not exception-safe.
 */
@interface SDQueue : NSObject

/**
 * @name Initialization
 */

/**
 * Returns the default priority concurrent global queue.
 */
+ (SDQueue *)concurrentGlobalQueue;

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
 * Initializes a serial GCD queue of default priority.
 */
- (id)init;

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
 * Initializes a serial or concurrent GCD queue of the given priority.
 *
 * @param priority A priority level for the custom queue. Blocks dispatched to
 * a queue with higher priority will be executed before those with a lower
 * priority.
 * @param concurrent If `YES`, the returned queue is capable of executing
 * multiple blocks simultaneously. If `NO`, the returned queue executes its
 * blocks in FIFO order.
 * @param label A reverse-DNS string to uniquely identify this queue in
 * debugging tools. This may be `nil` to not use a label.
 */
- (id)initWithPriority:(dispatch_queue_priority_t)priority concurrent:(BOOL)concurrent label:(NSString *)label;

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
 * The queue responsible for processing blocks dispatched to the receiver, or
 * `nil` if the receiver is not a private queue.
 *
 * Setting this property will synchronously wait for the termination of any
 * <withGCDQueue:> invocations, at which point an asynchronous barrier block
 * will be queued on the receiver. This barrier block is what will actually
 * switch the target queue and update the property.
 *
 * Because the setter for this property is synchronous, it will deadlock if the
 * calling code is executing on the receiver (directly or indirectly). If this
 * may be a possibility, consider setting this property in an asynchronous block
 * dispatched to a global queue.
 *
 * It is an error to set this property on a queue which is not <private>.
 */
@property (strong) SDQueue *targetQueue;

/**
 * @name Adding Behavior to Dispatched Blocks
 */

/**
 * A block to automatically invoke after every block executed on the receiver.
 *
 * Changing this property will not affect the epilogue used for blocks that have
 * already been queued.
 *
 * This block is run on the same thread as the queued block it is executing
 * after.
 */
@property (copy) dispatch_block_t epilogueBlock;

/**
 * A block to automatically invoke before every block executed on the receiver.
 *
 * Changing this property will not affect the prologue used for blocks that have
 * already been queued.
 *
 * This block is run on the same thread as the queued block that will execute
 * after it.
 */
@property (copy) dispatch_block_t prologueBlock;

/**
 * @name Dispatch
 */

/**
 * Adds the given block to the end of the queue, after the given delay has
 * passed.
 *
 * @param delay The delay before adding the block to the end of the queue.
 * @param block The block to execute after `delay` has passed, and thereafter
 * when the queue is available. If `NULL`, nothing happens.
 */
- (void)afterDelay:(NSTimeInterval)delay runAsynchronously:(dispatch_block_t)block;

/**
 * Adds the given block to the end of the queue and returns immediately.
 *
 * @param block The block to execute when the queue is available. If `NULL`,
 * nothing happens.
 */
- (void)runAsynchronously:(dispatch_block_t)block;

/**
 * Adds the given block to the end of the queue and returns immediately, unless
 * the receiver is the current queue.
 *
 * If the receiver is a serial queue and (directly or indirectly) already
 * running the calling code, `block` executes immediately without being queued.
 *
 * @param block The block to execute when the queue is available. If `NULL`,
 * nothing happens.
 */
- (void)runAsynchronouslyIfNotCurrent:(dispatch_block_t)block;

/**
 * Adds the given block to the end of the queue and waits for it to execute.
 *
 * If the receiver is a serial queue and (directly or indirectly) already
 * running the calling code, `block` executes immediately without being queued.
 *
 * @param block The block to execute when the queue is available. If `NULL`,
 * nothing happens.
 *
 * @note This method is exception-safe. Any exceptions thrown from within
 * `block` will be propagated to the caller of this method.
 */
- (void)runSynchronously:(dispatch_block_t)block;

/**
 * Invokes the given block with the GCD queue underlying the receiver, as well
 * as a flag indicating whether the queue is present somewhere in the current
 * call stack. The flag is guaranteed to remain valid for the duration of the
 * block.
 *
 * This method can be used to use the underlying GCD queue in a comparatively
 * safe way, with the following caveats:
 *
 *	- The queue reference must not escape `block`.
 *	- The queue must not have a new target set with
 *	`dispatch_set_target_queue()`.
 */
- (void)withGCDQueue:(void (^)(dispatch_queue_t queue, BOOL isCurrentQueue))block;

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
 * @param block The block to execute when the queue is available. If `NULL`,
 * nothing happens.
 *
 * @warning *Important:* This should not be used with a global concurrent queue.
 * You can check the type of queue you have with the <concurrent> and <private>
 * properties.
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
 * @param block The block to execute when the queue is available. If `NULL`,
 * nothing happens.
 *
 * @note This method is exception-safe. Any exceptions thrown from within
 * `block` will be propagated to the caller of this method.
 *
 * @warning *Important:* This should not be used with a global concurrent queue.
 * You can check the type of queue you have with the <concurrent> and <private>
 * properties.
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
 *
 * @note This method is exception-safe. Any exceptions thrown from within
 * `block` will be propagated to the caller of this method.
 */
+ (void)synchronizeQueues:(NSArray *)queues runSynchronously:(dispatch_block_t)block;
@end
