@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package com.hadithly.app.features.purchases

import com.hadithly.app.core.preferences.nativeText

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.hadithly.app.BuildConfig
import com.hadithly.app.HadithlyApplication
import com.hadithly.app.R
import com.hadithly.app.core.analytics.AnalyticsMetric
import com.hadithly.app.core.purchases.PurchaseManager
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.revenuecat.purchases.PackageType
import java.util.Locale

@Composable
fun QuotaPaywallSheet(purchases: PurchaseManager, onDismiss: () -> Unit, onUnlocked: () -> Unit) {
    val colors = LocalHadithlyColors.current
    val state by purchases.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val appLocale = LocalConfiguration.current.locales[0]
    val analytics = (context.applicationContext as HadithlyApplication).analytics
    val activity = context.findActivity()
    val uri = LocalUriHandler.current
    var selected by remember { mutableStateOf<String?>(null) }
    var reportedAvailability by remember { mutableStateOf<Set<Boolean>>(emptySet()) }
    var attemptedRevision by remember { mutableStateOf<Int?>(null) }
    var attemptedUnlock by remember { mutableStateOf(false) }
    var didUnlock by remember { mutableStateOf(false) }
    var restoring by remember { mutableStateOf(false) }
    var moreMenuExpanded by remember { mutableStateOf(false) }

    val displayPackages = state.packages.filter { option ->
        option.packageType != PackageType.ANNUAL || PaywallPricing.localizedAnnualMonthlyEquivalent(option.product, appLocale) != null
    }
    val monthlyPackage = displayPackages.firstOrNull { it.packageType == PackageType.MONTHLY }
    val annualPackage = displayPackages.firstOrNull { it.packageType == PackageType.ANNUAL }
    val annualSavings = if (monthlyPackage != null && annualPackage != null) {
        PaywallPricing.annualSavingsPercent(
            monthlyAmountMicros = monthlyPackage.product.price.amountMicros,
            monthlyCurrencyCode = monthlyPackage.product.price.currencyCode,
            annualAmountMicros = annualPackage.product.price.amountMicros,
            annualCurrencyCode = annualPackage.product.price.currencyCode,
        )
    } else null
    LaunchedEffect(Unit) {
        analytics.record(AnalyticsMetric.paywallResultShown)
        purchases.loadOffering()
    }
    LaunchedEffect(state.packages, displayPackages, state.loading, state.errorMessage) {
        if (!state.loading) {
            if (displayPackages.isNotEmpty() && displayPackages.none { it.identifier == selected }) {
                selected = displayPackages.firstOrNull { it.packageType == PackageType.ANNUAL }?.identifier
                    ?: displayPackages.firstOrNull { it.packageType == PackageType.MONTHLY }?.identifier
            }
            if (displayPackages.isNotEmpty() && true !in reportedAvailability) {
                reportedAvailability = reportedAvailability + true
                analytics.record(AnalyticsMetric.paywallResultAvailable)
                analytics.flush()
            } else if (displayPackages.isEmpty() && state.errorMessage != null && false !in reportedAvailability) {
                reportedAvailability = reportedAvailability + false
                analytics.record(AnalyticsMetric.paywallResultUnavailable)
                analytics.flush()
            }
        }
    }
    fun completeUnlock() {
        if (attemptedUnlock && !didUnlock && attemptedRevision == purchases.operationRevision && state.hasProEntitlement) {
            didUnlock = true
            if (state.outcome != PurchaseManager.Outcome.CONFIRMED) {
                analytics.record(if (restoring) AnalyticsMetric.purchaseResultRestoreConfirmed else AnalyticsMetric.purchaseResultConfirmed)
            }
            analytics.record(AnalyticsMetric.paywallResultConfirmed)
            onUnlocked()
            onDismiss()
        }
    }
    LaunchedEffect(state.hasProEntitlement) { if (state.hasProEntitlement) completeUnlock() }
    fun dismissMeasured() { analytics.record(AnalyticsMetric.paywallResultDismissed); onDismiss() }
    fun restorePurchases() {
        attemptedRevision = purchases.operationRevision
        attemptedUnlock = true
        restoring = true
        purchases.restore {
            if (it && !didUnlock && attemptedRevision == purchases.operationRevision) {
                didUnlock = true
                onUnlocked()
                onDismiss()
            }
        }
    }

    ModalBottomSheet(onDismissRequest = { if (!state.purchasing) dismissMeasured() }, containerColor = colors.background) {
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).navigationBarsPadding().padding(24.dp).testTag("paywall.quota"),
            verticalArrangement = Arrangement.spacedBy(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically) {
                Box {
                    IconButton(onClick = { moreMenuExpanded = true }, modifier = Modifier.testTag("paywall.more")) {
                        Icon(Icons.Filled.MoreVert, contentDescription = stringResource(R.string.q2_more), tint = colors.textPrimary)
                    }
                    DropdownMenu(expanded = moreMenuExpanded, onDismissRequest = { moreMenuExpanded = false }) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.la2_restore)) },
                            onClick = { moreMenuExpanded = false; restorePurchases() },
                            enabled = !state.purchasing,
                            modifier = Modifier.testTag("paywall.restore"),
                        )
                        DropdownMenuItem(text = { Text(stringResource(R.string.la2_privacy)) }, onClick = {
                            moreMenuExpanded = false
                            uri.openUri(BuildConfig.PRIVACY_POLICY_URL)
                        })
                        DropdownMenuItem(text = { Text(stringResource(R.string.la2_terms)) }, onClick = {
                            moreMenuExpanded = false
                            uri.openUri(BuildConfig.TERMS_OF_USE_URL)
                        })
                    }
                }
                TextButton(onClick = ::dismissMeasured) { Text(stringResource(R.string.la2_close), color = colors.textPrimary) }
            }
            Text(stringResource(R.string.la2_more_translations), style = MaterialTheme.typography.headlineLarge, color = colors.textPrimary, textAlign = TextAlign.Center)
            Text(stringResource(R.string.q1_quota_exhausted), style = MaterialTheme.typography.bodyLarge, color = colors.textSecondary, textAlign = TextAlign.Center)
            Text(stringResource(R.string.la2_reading_free), style = MaterialTheme.typography.titleSmall, color = colors.textPrimary)
            Text(stringResource(R.string.la2_allowance), style = MaterialTheme.typography.bodyMedium, color = colors.textSecondary, textAlign = TextAlign.Center)
            Text(stringResource(R.string.q2_devices), style = MaterialTheme.typography.bodySmall, color = colors.textSecondary, textAlign = TextAlign.Center)
            when {
                state.hasProEntitlement -> Text(nativeText("Hadithly Pro is active"), color = colors.textPrimary)
                state.loading -> CircularProgressIndicator(color = colors.textSecondary)
                else -> {
                    displayPackages.sortedByDescending { it.packageType == PackageType.ANNUAL }.forEach { option ->
                        val isAnnual = option.packageType == PackageType.ANNUAL
                        val isSelected = selected == option.identifier
                        val price = if (isAnnual) PaywallPricing.localizedAnnualMonthlyEquivalent(option.product, appLocale) else option.product.price.formatted
                        if (price != null) PaywallPlanOption(isAnnual, isSelected, price, annualSavings, !state.purchasing) {
                            selected = option.identifier
                            analytics.record(if (isAnnual) AnalyticsMetric.paywallResultSelectedAnnual else AnalyticsMetric.paywallResultSelectedMonthly)
                        }
                    }
                    val packageToBuy = displayPackages.firstOrNull { it.identifier == selected }
                    if (packageToBuy != null) Button(enabled = !state.purchasing && activity != null,
                        colors = ButtonDefaults.buttonColors(containerColor = colors.interactive, contentColor = colors.onInteractive),
                        onClick = {
                            attemptedRevision = purchases.operationRevision
                            attemptedUnlock = true
                            analytics.record(AnalyticsMetric.paywallResultPurchaseStarted)
                            activity?.let { purchases.purchase(it, packageToBuy) { if (!didUnlock && attemptedRevision == purchases.operationRevision) { didUnlock = true; analytics.record(AnalyticsMetric.paywallResultConfirmed); onUnlocked(); onDismiss() } } }
                        }, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp).testTag("paywall.subscribe")) {
                        Text(stringResource(if (packageToBuy.packageType == PackageType.ANNUAL) R.string.la2_subscribe_annual else R.string.la2_subscribe_monthly))
                    }
                }
            }
            if (state.purchasing) { CircularProgressIndicator(color = colors.textSecondary); Text(stringResource(R.string.la2_checking), color = colors.textPrimary) }
            when (state.outcome) {
                PurchaseManager.Outcome.CANCELLED -> Text(stringResource(R.string.la2_cancelled), color = colors.textSecondary)
                PurchaseManager.Outcome.PENDING -> Text(stringResource(R.string.la2_pending), color = colors.textSecondary)
                PurchaseManager.Outcome.SYNCING -> Text(stringResource(R.string.q2_wait), color = colors.textSecondary)
                else -> state.errorMessage?.let { Text(it, color = colors.textSecondary, textAlign = TextAlign.Center) }
            }
            if (!state.loading && displayPackages.isEmpty()) TextButton(onClick = { purchases.loadOffering() }, modifier = Modifier.testTag("paywall.retryPlans")) {
                Text(stringResource(R.string.la2_retry))
            }
            TextButton(onClick = ::dismissMeasured, modifier = Modifier.testTag("paywall.keepReading")) {
                Text(stringResource(R.string.la2_keep_reading), color = colors.textPrimary)
            }
            Text(stringResource(R.string.la2_renewal), style = MaterialTheme.typography.bodySmall, color = colors.textSecondary, textAlign = TextAlign.Center)
        }
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

/** Actual native pricing choice; fixtures supply sample store amounts. */
@Composable
internal fun PaywallPlanOption(
    annual: Boolean,
    isSelected: Boolean,
    price: String,
    savingsPercent: Int?,
    enabled: Boolean = true,
    onSelect: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
                        Column(
                            Modifier.fillMaxWidth()
                                .clip(RoundedCornerShape(14.dp))
                                .background(if (isSelected) colors.surfaceElevated else colors.surface)
                                .border(if (isSelected) 1.5.dp else 1.dp, if (isSelected) colors.interactive else colors.divider, RoundedCornerShape(14.dp))
                                .selectable(selected = isSelected, role = Role.RadioButton, enabled = enabled, onClick = onSelect)
                                .padding(14.dp)
                                .testTag(if (annual) "paywall.annual" else "paywall.monthly"),
                            verticalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                RadioButton(selected = isSelected, onClick = null)
                                Text(stringResource(if (annual) R.string.la2_annual else R.string.la2_monthly),
                                    style = MaterialTheme.typography.titleMedium, color = colors.textPrimary, modifier = Modifier.weight(1f))
                            }
                            if (annual) {
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically,
                                    modifier = Modifier.padding(start = 48.dp)) {
                                    Text(stringResource(R.string.q2_recommended), style = MaterialTheme.typography.labelSmall, color = colors.onInteractive,
                                        modifier = Modifier.clip(RoundedCornerShape(50.dp)).background(colors.interactive).padding(horizontal = 8.dp, vertical = 5.dp))
                                    if (savingsPercent != null) Text(stringResource(R.string.q2_savings_percent, savingsPercent),
                                        style = MaterialTheme.typography.labelSmall, color = colors.textPrimary)
                                }
                            }
                            Row(Modifier.fillMaxWidth().padding(start = 48.dp), verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                                Text(price, style = MaterialTheme.typography.titleMedium, color = colors.textPrimary)
                                Text(stringResource(R.string.q2_per_month), style = MaterialTheme.typography.bodySmall, color = colors.textSecondary)
                                if (annual) {
                                    Spacer(Modifier.weight(1f))
                                    Text(stringResource(R.string.q2_billed_yearly), style = MaterialTheme.typography.bodySmall, color = colors.textSecondary)
                                }
                            }
                        }
}
