The SafeDispatch framework is a Cocoa wrapper for Grand Central Dispatch that adds important safety features. Not all of GCD is included – the main focus is on improving dispatch queues and groups.

# Features

Besides an easy-to-use Objective-C API, this framework adds:

 * **Recursive synchronous dispatch**. `dispatch_sync()` deadlocks when targeting the current queue – `SDQueue` does not.
 * **Conditionally asynchronous or synchronous dispatch**. Blocks can be run synchronously if targeting the current queue, or asynchronously if targeting another.
 * **Exception-safe synchronous dispatch**, to support throwing exceptions from synchronous blocks and propagating them to callers.
 * **Synchronization across multiple queues**, based on a deterministic total ordering of the queues (to prevent deadlocks).
 * **Prologue and epilogue blocks**, to perform work before or after each block added to a queue.
 * **Better detection of the current queue**. SafeDispatch can identify whether code is executing on a given queue even if that queue is many layers up the call stack. _(This is especially important for recursive and conditional dispatch.)_

# License

This project is released into the public domain, and can be incorporated for free and without attribution for any use.
