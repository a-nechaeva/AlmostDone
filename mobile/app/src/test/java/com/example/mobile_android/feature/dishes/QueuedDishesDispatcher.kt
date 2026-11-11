package com.example.mobile_android.feature.dishes

import java.util.concurrent.ConcurrentLinkedQueue
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.CoroutineDispatcher

internal class QueuedDishesDispatcher : CoroutineDispatcher() {
    private val tasks = ConcurrentLinkedQueue<Runnable>()
    val hasWork: Boolean
        get() = tasks.isNotEmpty()

    override fun dispatch(context: CoroutineContext, block: Runnable) {
        tasks.add(block)
    }

    fun runNext() {
        checkNotNull(tasks.poll()).run()
    }
}
