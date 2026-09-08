package com.hadithly.app.core.purchases

import android.app.Activity
import android.content.Context
import com.hadithly.app.BuildConfig
import com.revenuecat.purchases.CustomerInfo
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
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update

/** RevenueCat lifecycle and paywall state, keyed to the verified Clerk user. */
class PurchaseManager(context: Context, apiKey: String) {

    data class State(
        val packages: List<Package> = emptyList(),
        val configured: Boolean = false,
        val loading: Boolean = false,
        val purchasing: Boolean = false,
        val hasProEntitlement: Boolean = false,
        val errorMessage: String? = null,
    )

    private val _state = MutableStateFlow(State())
    val state: StateFlow<State> = _state

    init {
        val trimmed = apiKey.trim()
        if (
            trimmed.isNotEmpty() &&
            !trimmed.contains("placeholder", ignoreCase = true) &&
            !trimmed.contains("your_", ignoreCase = true)
        ) {
            Purchases.logLevel = if (BuildConfig.DEBUG) LogLevel.DEBUG else LogLevel.WARN
            Purchases.configure(PurchasesConfiguration.Builder(context, trimmed).build())
            _state.update { it.copy(configured = true) }
        }
    }

    fun logIn(appUserId: String) {
        if (!_state.value.configured) return
        Purchases.sharedInstance.logInWith(
            appUserId,
            onError = { error -> _state.update { it.copy(errorMessage = error.message) } },
            onSuccess = { customerInfo, _ -> apply(customerInfo) },
        )
    }

    fun logOut() {
        if (!_state.value.configured || Purchases.sharedInstance.isAnonymous) return
        Purchases.sharedInstance.logOutWith(
            onError = { error -> _state.update { it.copy(errorMessage = error.message) } },
            onSuccess = ::apply,
        )
    }

    fun loadOffering() {
        if (!_state.value.configured) {
            _state.update { it.copy(errorMessage = "Subscriptions are not configured for this build.") }
            return
        }
        _state.update { it.copy(loading = true, errorMessage = null) }
        Purchases.sharedInstance.getOfferingsWith(
            onError = { error -> _state.update { it.copy(loading = false, errorMessage = error.message) } },
            onSuccess = { offerings ->
                val packages = offerings.current?.availablePackages.orEmpty().sortedBy(::packagePriority)
                _state.update {
                    it.copy(
                        packages = packages,
                        loading = false,
                        errorMessage = if (packages.isEmpty()) "No subscription plans are available right now." else null,
                    )
                }
            },
        )
    }

    fun purchase(activity: Activity, packageToPurchase: Package, onUnlocked: () -> Unit) {
        if (!_state.value.configured) return
        _state.update { it.copy(purchasing = true, errorMessage = null) }
        Purchases.sharedInstance.purchaseWith(
            PurchaseParams.Builder(activity, packageToPurchase).build(),
            onError = { error, userCancelled ->
                _state.update {
                    it.copy(purchasing = false, errorMessage = if (userCancelled) null else error.message)
                }
            },
            onSuccess = { _, customerInfo ->
                apply(customerInfo)
                _state.update { it.copy(purchasing = false) }
                if (_state.value.hasProEntitlement) onUnlocked()
            },
        )
    }

    fun restore(onUnlocked: () -> Unit) {
        if (!_state.value.configured) return
        _state.update { it.copy(purchasing = true, errorMessage = null) }
        Purchases.sharedInstance.restorePurchasesWith(
            onError = { error -> _state.update { it.copy(purchasing = false, errorMessage = error.message) } },
            onSuccess = { customerInfo ->
                apply(customerInfo)
                _state.update { it.copy(purchasing = false) }
                if (_state.value.hasProEntitlement) onUnlocked()
            },
        )
    }

    private fun apply(customerInfo: CustomerInfo) {
        _state.update {
            it.copy(hasProEntitlement = customerInfo.entitlements["pro"]?.isActive == true)
        }
    }

    private fun packagePriority(packageToSort: Package): Int = when (packageToSort.packageType) {
        PackageType.ANNUAL -> 0
        PackageType.SIX_MONTH -> 1
        PackageType.THREE_MONTH -> 2
        PackageType.TWO_MONTH -> 3
        PackageType.MONTHLY -> 4
        PackageType.WEEKLY -> 5
        else -> 99
    }
}
