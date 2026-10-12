package com.hadithly.app.core.purchases

import android.content.SharedPreferences
import org.json.JSONObject

class PendingPurchaseStore(private val preferences: SharedPreferences) {
    data class Pending(val ownerId: String, val productId: String?, val purchase: Boolean)
    private val key = "pending.v1"
    val pending: Pending? get() = runCatching {
        preferences.getString(key, null)?.let {
            val row = JSONObject(it)
            Pending(row.getString("ownerId"), if (row.isNull("productId")) null else row.getString("productId"), row.getBoolean("purchase")).also {
                require(it.ownerId.isNotEmpty() && it.ownerId.length <= 200 && (!it.purchase || !it.productId.isNullOrEmpty()))
            }
        }
    }.getOrNull()
    val unreadable: Boolean get() = preferences.contains(key) && pending == null
    fun blocks(ownerId: String) = unreadable || (pending != null && pending?.ownerId != ownerId)
    fun begin(ownerId: String, productId: String?, purchase: Boolean): Boolean {
        if (blocks(ownerId)) return false
        pending?.let { if (!purchase) return true; if (it.purchase) return it.productId == productId }
        return preferences.edit().putString(key, JSONObject().put("ownerId", ownerId)
            .put("productId", productId ?: JSONObject.NULL).put("purchase", purchase).toString()).commit()
    }
    fun clear(ownerId: String) { if (pending?.ownerId == ownerId) preferences.edit().remove(key).commit() }
}
