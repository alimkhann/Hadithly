package com.hadithly.app.core.purchases

class PurchaseAccountGate {
    var accountId: String? = null
        private set
    var revision: Int = 0
        private set
    var ready: Boolean = false
        private set

    fun bind(accountId: String?): Int {
        revision += 1
        this.accountId = accountId
        ready = false
        return revision
    }

    fun identified(revision: Int) {
        if (this.revision == revision && accountId != null) ready = true
    }

    fun accepts(revision: Int, currentAccountId: String?): Boolean =
        ready && this.revision == revision && accountId != null && accountId == currentAccountId
}
