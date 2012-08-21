//
//  SDGroup.h
//  SafeDispatch
//
//  Created by Justin Spahr-Summers on 30.11.11.
//  Copyright (C) 2012 Justin Spahr-Summers.
//  Released under the MIT license.
//

#import <Foundation/Foundation.h>

@class SDQueue;

/**
 * Represents a dispatch group.
 *
 * Dispatch groups allow you to track the execution of multiple blocks and wait
 * upon them as a group.
 */
@interface SDGroup : NSObject

/**
 * @name Initialization
 */

/**
 * Initializes a dispatch group which will enqueue its blocks on the default
 * priority global concurrent queue.
 */
- (id)init;

/**
 * Initializes the receiver for dispatching its blocks to the given queue.
 *
 * This is the designated initializer for this class.
 *
 * @param queue The queue to dispatch blocks to.
 */
- (id)initWithDestinationQueue:(SDQueue *)queue;

/**
 * @name Destination Queue
 */

/**
 * The queue to dispatch to.
 *
 * All blocks grouped with the receiver are enqueued on this dispatch queue.
 */
@property (nonatomic, strong, readonly) SDQueue *destinationQueue;

/**
 * @name Dispatch
 */

/**
 * Adds the given block to the group, schedules it on the <destinationQueue>,
 * and returns immediately.
 *
 * @param block The block to execute when the queue is available.
 */
- (void)runAsynchronously:(dispatch_block_t)block;

/**
 * @name Group Completion
 */

/**
 * Whether all blocks previously added to the group have completed.
 */
@property (nonatomic, readonly, getter = isCompleted) BOOL completed;

/**
 * Schedules a block to run when the receiver is marked as <completed>.
 *
 * @param block A block to dispatch upon completion.
 */
- (void)runWhenCompleted:(dispatch_block_t)block;

/**
 * Blocks the current thread, waiting indefinitely for the dispatch group to
 * complete.
 */
- (void)wait;

/**
 * Blocks the current thread, waiting on the dispatch group to complete or the
 * given time limit to be reached.
 *
 * @param date The time at which to stop waiting and return if the group has not
 * yet completed. You can specify \c nil to immediately return if the dispatch
 * group has not completed.
 */
- (BOOL)waitUntilDate:(NSDate *)date;

@end
