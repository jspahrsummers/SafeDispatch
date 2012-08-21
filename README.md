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

**Copyright (c) 2012 Justin Spahr-Summers**

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
