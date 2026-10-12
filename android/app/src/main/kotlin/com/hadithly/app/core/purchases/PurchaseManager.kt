package com.hadithly.app.core.purchases

import android.app.Activity
import android.content.Context
import com.clerk.api.Clerk
import com.revenuecat.purchases.LogLevel
import com.revenuecat.purchases.Package
import com.revenuecat.purchases.PackageType
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.getOfferingsWith
import com.revenuecat.purchases.logInWith
import com.revenuecat.purchases.logOutWith
import com.revenuecat.purchases.purchaseWith
import com.revenuecat.purchases.restorePurchasesWith
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

class PurchaseManager(context: Context, apiKey: String, private val scope: CoroutineScope) {
    data class State(
        val packages: List<Package> = emptyList(), val configured: Boolean = false,
        val loading: Boolean = false, val purchasing: Boolean = false,
        val hasProEntitlement: Boolean = false, val errorMessage: String? = null,
    )
    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state
    var verifyBackendAccess: (suspend () -> Boolean)? = null
    private val gate = PurchaseAccountGate()
    private val operations = PurchaseOperationQueue()
    private val pendingStore = PendingPurchaseStore(context.getSharedPreferences("purchaseIntent", Context.MODE_PRIVATE))

    init {
        val trimmed = apiKey.trim()
        if (!pendingStore.unreadable && trimmed.isNotEmpty() && !trimmed.contains("placeholder", true) && !trimmed.contains("your_", true) && !trimmed.startsWith("test_", true)) {
            Purchases.logLevel = LogLevel.WARN
            val configuration = PurchasesConfiguration.Builder(context, trimmed)
            pendingStore.pending?.ownerId?.let { configuration.appUserID(it) }
            Purchases.configure(configuration.build())
            _state.update { it.copy(configured = true) }
        }
        scope.launch {
            Clerk.userFlow.collect { user ->
                if (gate.accountId != user?.id) {
                    if (user == null) clearAccount() else logIn(user.id)
                }
            }
        }
    }

    fun clearAccount() {
        gate.bind(null)
        _state.update { State(configured = it.configured) }
    }

    fun logIn(appUserId: String) {
        val revision = gate.bind(appUserId)
        _state.update { State(configured = it.configured) }
        if (!_state.value.configured) {
            gate.identified(revision)
            if (verifyBackendAccess != null) scope.launch { confirmBackend(revision) {} }
            return
        }
        if (pendingStore.blocks(appUserId)) {
            _state.update { it.copy(errorMessage = "A store operation is pending for another Hadithly account. Sign in to the account that started it, then restore.") }
            return
        }
        scope.launch {
            operations.run {
                if (gate.revision != revision) return@run
                val success = suspendCoroutine<Boolean> { continuation ->
                    Purchases.sharedInstance.logInWith(appUserId,
                        onError = { continuation.resume(false) },
                        onSuccess = { _, _ -> continuation.resume(true) })
                }
                if (gate.revision != revision) return@run
                if (success) gate.identified(revision)
                else _state.update { it.copy(errorMessage = "Sign in to your original Hadithly account to use this purchase.") }
            }
            if (accepts(revision)) confirmBackend(revision) {}
        }
    }

    fun logOut() {
        clearAccount()
        if (!_state.value.configured || pendingStore.pending != null || pendingStore.unreadable) return
        scope.launch {
            operations.run {
                if (!Purchases.sharedInstance.isAnonymous) suspendCoroutine<Unit> { continuation ->
                    Purchases.sharedInstance.logOutWith(
                        onError = { continuation.resume(Unit) }, onSuccess = { continuation.resume(Unit) })
                }
            }
        }
    }

    private fun accepts(revision: Int) = gate.accepts(revision, Clerk.user?.id)

    fun loadOffering() {
        val revision = gate.revision
        if (!_state.value.configured || !accepts(revision)) {
            _state.update { it.copy(errorMessage = "Sign in to your Hadithly account before purchasing or restoring.") }
            return
        }
        _state.update { it.copy(loading = true, errorMessage = null) }
        Purchases.sharedInstance.getOfferingsWith(
            onError = { if (accepts(revision)) _state.update { it.copy(loading = false, errorMessage = "Plans could not be loaded. Try again.") } },
            onSuccess = { offerings ->
                if (accepts(revision)) {
                    val packages = offerings.current?.availablePackages.orEmpty()
                        .filter { allowedProduct(it.product.id, it.packageType) }
                        .sortedBy { if (it.packageType == PackageType.ANNUAL) 0 else 1 }
                    _state.update { it.copy(packages = packages, loading = false,
                        errorMessage = if (packages.isEmpty()) "No subscription plans are available right now." else null) }
                }
            })
    }

    fun purchase(activity: Activity, packageToPurchase: Package, onUnlocked: () -> Unit) {
        val revision = gate.revision
        if (!_state.value.configured || _state.value.purchasing || !accepts(revision) || !_state.value.packages.contains(packageToPurchase)) return
        val ownerId = gate.accountId ?: return
        val hadPendingOperation = pendingStore.pending != null
        if (!pendingStore.begin(ownerId, packageToPurchase.product.id, true)) {
            _state.update { it.copy(errorMessage = "Finish or restore the pending purchase with your original Hadithly account first.") }; return
        }
        _state.update { it.copy(purchasing = true, errorMessage = null) }
        scope.launch {
            val purchased = operations.run {
                if (!accepts(revision)) { if (!hadPendingOperation) pendingStore.clear(ownerId); return@run false }
                suspendCoroutine<Boolean> { continuation ->
                    Purchases.sharedInstance.purchaseWith(PurchaseParams.Builder(activity, packageToPurchase).build(),
                        onError = { _, userCancelled ->
                            if (userCancelled && !hadPendingOperation) pendingStore.clear(ownerId)
                            if (accepts(revision)) _state.update { it.copy(purchasing = false, errorMessage = if (userCancelled) null else "Purchase could not be completed. Try again.") }
                            continuation.resume(false)
                        }, onSuccess = { _, _ -> pendingStore.clear(ownerId); continuation.resume(true) })
                }
            }
            if (purchased && accepts(revision)) confirmBackend(revision) { if (it) onUnlocked() }
            else if (!accepts(revision) && pendingStore.pending == null) Clerk.user?.id?.let(::logIn)
        }
    }

    fun restore(onComplete: (Boolean) -> Unit) {
        val revision = gate.revision
        if (!_state.value.configured && accepts(revision) && verifyBackendAccess != null) {
            scope.launch { confirmBackend(revision, onComplete) }; return
        }
        if (!_state.value.configured || _state.value.purchasing || !accepts(revision)) {
            _state.update { it.copy(errorMessage = "Sign in to your original Hadithly account before restoring.") }
            onComplete(false)
            return
        }
        val ownerId = gate.accountId ?: run { onComplete(false); return }
        val hadPendingOperation = pendingStore.pending != null
        if (!pendingStore.begin(ownerId, null, false)) { onComplete(false); return }
        _state.update { it.copy(purchasing = true, errorMessage = null) }
        scope.launch {
            val restored = operations.run {
                if (!accepts(revision)) { if (!hadPendingOperation) pendingStore.clear(ownerId); return@run false }
                suspendCoroutine<Boolean> { continuation ->
                    Purchases.sharedInstance.restorePurchasesWith(
                        onError = {
                            if (accepts(revision)) _state.update { it.copy(purchasing = false,
                                errorMessage = "Restore failed. Use the original Hadithly account and store account, then try again.") }
                            continuation.resume(false)
                        }, onSuccess = { info ->
                            val pending = pendingStore.pending
                            if (pending != null && (!pending.purchase || info.activeSubscriptions.contains(pending.productId) ||
                                info.entitlements["pro"]?.let { ent -> ent.isActive && (ent.productIdentifier + (ent.productPlanIdentifier?.let { ":$it" } ?: "")) == pending.productId } == true)) pendingStore.clear(ownerId)
                            continuation.resume(true) })
                }
            }
            if (restored && accepts(revision)) confirmBackend(revision, onComplete) else {
                onComplete(false)
                if (!accepts(revision) && pendingStore.pending == null) Clerk.user?.id?.let(::logIn)
            }
        }
    }

    private suspend fun confirmBackend(revision: Int, onComplete: (Boolean) -> Unit) {
        val active = runCatching { verifyBackendAccess?.invoke() ?: false }
        if (!accepts(revision)) { onComplete(false); return }
        _state.update { it.copy(purchasing = false, hasProEntitlement = active.getOrDefault(false), errorMessage =
            if (active.isFailure) "Your subscription could not be checked. Try Restore purchases again shortly."
            else if (!active.getOrDefault(false)) "No active Pro purchase was found for this Hadithly account. Use the account that purchased Pro."
            else null) }
        onComplete(active.getOrDefault(false))
    }

    companion object {
        fun allowedProduct(id: String, type: PackageType): Boolean = when (type) {
            PackageType.MONTHLY -> id == "hadithly_pro_monthly:monthly"
            PackageType.ANNUAL -> id == "hadithly_pro_annual:annual"
            else -> false
        }
    }
}
