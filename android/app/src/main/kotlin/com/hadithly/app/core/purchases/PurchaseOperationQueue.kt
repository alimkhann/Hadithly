package com.hadithly.app.core.purchases

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class PurchaseOperationQueue {
    private val mutex = Mutex()
    suspend fun <T> run(operation: suspend () -> T): T = mutex.withLock { operation() }
}
