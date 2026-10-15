@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
package com.hadithly.app.features.purchases

import com.hadithly.app.core.preferences.nativeText

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.selection.selectable
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
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

@Composable
fun QuotaPaywallSheet(purchases: PurchaseManager, onDismiss: () -> Unit, onUnlocked: () -> Unit) {
    val colors = LocalHadithlyColors.current
    val state by purchases.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val analytics = (context.applicationContext as HadithlyApplication).analytics
    val activity = context.findActivity()
    val uri = LocalUriHandler.current
    var selected by remember { mutableStateOf<String?>(null) }
    var reportedAvailability by remember { mutableStateOf<Set<Boolean>>(emptySet()) }
    var attemptedRevision by remember { mutableStateOf<Int?>(null) }
    var attemptedUnlock by remember { mutableStateOf(false) }
    var didUnlock by remember { mutableStateOf(false) }
    var restoring by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { analytics.record(AnalyticsMetric.paywallResultShown); purchases.loadOffering() }
    LaunchedEffect(state.packages, state.loading, state.errorMessage) {
        if (!state.loading && state.packages.isNotEmpty()) {
            if (selected == null) selected = state.packages.firstOrNull { it.packageType == PackageType.MONTHLY }?.identifier
            if (true !in reportedAvailability) { reportedAvailability = reportedAvailability + true; analytics.record(AnalyticsMetric.paywallResultAvailable); analytics.flush() }
        } else if (!state.loading && state.errorMessage != null && false !in reportedAvailability) {
            reportedAvailability = reportedAvailability + false; analytics.record(AnalyticsMetric.paywallResultUnavailable); analytics.flush()
        }
    }
    fun completeUnlock() {
        if (attemptedUnlock && !didUnlock && attemptedRevision == purchases.operationRevision && state.hasProEntitlement) {
            didUnlock = true
            if (state.outcome != PurchaseManager.Outcome.CONFIRMED) analytics.record(if (restoring) AnalyticsMetric.purchaseResultRestoreConfirmed else AnalyticsMetric.purchaseResultConfirmed)
            analytics.record(AnalyticsMetric.paywallResultConfirmed); onUnlocked(); onDismiss()
        }
    }
    LaunchedEffect(state.hasProEntitlement) { if (state.hasProEntitlement) completeUnlock() }
    fun dismissMeasured() { analytics.record(AnalyticsMetric.paywallResultDismissed); onDismiss() }
    ModalBottomSheet(onDismissRequest = { if (!state.purchasing) dismissMeasured() }, containerColor = colors.background) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).navigationBarsPadding().padding(24.dp).testTag("paywall.quota"),
            verticalArrangement = Arrangement.spacedBy(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                TextButton(onClick = ::dismissMeasured) { Text(stringResource(R.string.la2_close), color = colors.textPrimary) }
            }
            Text(stringResource(R.string.la2_more_translations), style = MaterialTheme.typography.headlineMedium, color = colors.textPrimary, textAlign = TextAlign.Center)
            Text(stringResource(R.string.q1_quota_exhausted), style = MaterialTheme.typography.bodyLarge, color = colors.textSecondary, textAlign = TextAlign.Center)
            Text(stringResource(R.string.la2_reading_free), style = MaterialTheme.typography.titleSmall, color = colors.textPrimary)
            Text(stringResource(R.string.la2_allowance), style = MaterialTheme.typography.bodyMedium, color = colors.textSecondary, textAlign = TextAlign.Center)
            Text(stringResource(R.string.q2_devices), style = MaterialTheme.typography.bodySmall, color = colors.textSecondary, textAlign = TextAlign.Center)
            when {
                state.hasProEntitlement -> Text(nativeText("Hadithly Pro is active"), color = colors.textPrimary)
                state.loading -> CircularProgressIndicator(color = colors.textSecondary)
                else -> {
                    state.packages.forEach { option ->
                        Row(Modifier.fillMaxWidth().selectable(selected = selected == option.identifier, role = Role.RadioButton,
                            enabled = !state.purchasing, onClick = {
                                selected = option.identifier
                                analytics.record(if (option.packageType == PackageType.ANNUAL) AnalyticsMetric.paywallResultSelectedAnnual else AnalyticsMetric.paywallResultSelectedMonthly)
                            }).heightIn(min = 56.dp).testTag(if (option.packageType == PackageType.ANNUAL) "paywall.annual" else "paywall.monthly"),
                            verticalAlignment = Alignment.CenterVertically) {
                            RadioButton(selected = selected == option.identifier, onClick = null)
                            Text(stringResource(if (option.packageType == PackageType.ANNUAL) R.string.la2_annual else R.string.la2_monthly), color = colors.textPrimary, modifier = Modifier.weight(1f))
                            Text(option.product.price.formatted, style = MaterialTheme.typography.titleMedium, color = colors.textPrimary)
                        }
                    }
                    val packageToBuy = state.packages.firstOrNull { it.identifier == selected }
                    if (packageToBuy != null) Button(enabled = !state.purchasing && activity != null,
                        colors = ButtonDefaults.buttonColors(containerColor = colors.interactive, contentColor = colors.onInteractive),
                        onClick = {
                            attemptedRevision = purchases.operationRevision; attemptedUnlock = true
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
            if (!state.loading && state.packages.isEmpty()) TextButton(onClick = { purchases.loadOffering() }) { Text(stringResource(R.string.la2_retry)) }
            TextButton(onClick = ::dismissMeasured, modifier = Modifier.testTag("paywall.keepReading")) { Text(stringResource(R.string.la2_keep_reading), color = colors.textPrimary) }
            TextButton(enabled = !state.purchasing, onClick = { attemptedRevision = purchases.operationRevision; attemptedUnlock = true; restoring = true; purchases.restore { if (it && !didUnlock && attemptedRevision == purchases.operationRevision) { didUnlock = true; onUnlocked(); onDismiss() } } }, modifier = Modifier.testTag("paywall.restore")) {
                Text(stringResource(R.string.la2_restore), color = colors.textSecondary)
            }
            Row(horizontalArrangement = Arrangement.spacedBy(24.dp)) {
                TextButton(onClick = { uri.openUri(BuildConfig.PRIVACY_POLICY_URL) }) { Text(stringResource(R.string.la2_privacy), color = colors.textSecondary) }
                TextButton(onClick = { uri.openUri(BuildConfig.TERMS_OF_USE_URL) }) { Text(stringResource(R.string.la2_terms), color = colors.textSecondary) }
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
