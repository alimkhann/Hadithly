@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.hadithly.app.features.purchases

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.hadithly.app.BuildConfig
import com.hadithly.app.core.purchases.PurchaseManager
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.revenuecat.purchases.Package
import com.revenuecat.purchases.PackageType

/** The only subscription entry point: shown after the backend rejects AI at quota. */
@Composable
fun QuotaPaywallSheet(
    purchases: PurchaseManager,
    onDismiss: () -> Unit,
    onUnlocked: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    val state by purchases.state.collectAsStateWithLifecycle()
    val activity = LocalContext.current.findActivity()
    val uriHandler = LocalUriHandler.current

    LaunchedEffect(Unit) { purchases.loadOffering() }

    ModalBottomSheet(
        onDismissRequest = { if (!state.purchasing) onDismiss() },
        containerColor = colors.background,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(20.dp),
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(horizontal = 24.dp, vertical = 18.dp),
        ) {
            Text("✦", fontSize = 28.sp, color = colors.accent)
            Text(
                text = "More AI translations",
                fontSize = 22.sp,
                fontWeight = FontWeight.SemiBold,
                color = colors.textPrimary,
            )
            Text(
                text = "You reached this month’s free AI limit. Reading, saved items, and existing translations stay free.",
                fontSize = 14.sp,
                lineHeight = 20.sp,
                color = colors.textSecondary,
                textAlign = TextAlign.Center,
            )

            when {
                state.hasProEntitlement -> ActiveAccess(onUnlocked = {
                    onUnlocked()
                    onDismiss()
                })
                state.loading -> CircularProgressIndicator(color = colors.textSecondary)
                else -> state.packages.forEach { packageToShow ->
                    PackageButton(
                        packageToShow = packageToShow,
                        purchasing = state.purchasing,
                        onPurchase = {
                            if (activity != null) {
                                purchases.purchase(activity, packageToShow) {
                                    onUnlocked()
                                    onDismiss()
                                }
                            }
                        },
                    )
                }
            }

            state.errorMessage?.let { message ->
                Text(message, fontSize = 12.sp, color = colors.textSecondary, textAlign = TextAlign.Center)
            }

            TextButton(
                enabled = !state.purchasing,
                onClick = {
                    purchases.restore {
                        onUnlocked()
                        onDismiss()
                    }
                },
            ) {
                Text("Restore purchases", color = colors.textSecondary)
            }

            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                TextButton(onClick = { uriHandler.openUri(BuildConfig.PRIVACY_POLICY_URL) }) {
                    Text("Privacy Policy", color = colors.textSecondary)
                }
                TextButton(onClick = { uriHandler.openUri(BuildConfig.TERMS_OF_USE_URL) }) {
                    Text("Terms of Use", color = colors.textSecondary)
                }
            }

            Text(
                text = "Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel in your store account.",
                fontSize = 11.sp,
                lineHeight = 15.sp,
                color = colors.textSecondary.copy(alpha = 0.75f),
                textAlign = TextAlign.Center,
            )
        }
    }
}

@Composable
private fun PackageButton(packageToShow: Package, purchasing: Boolean, onPurchase: () -> Unit) {
    val colors = LocalHadithlyColors.current
    Button(
        enabled = !purchasing,
        onClick = onPurchase,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
            Text(packageTitle(packageToShow), fontWeight = FontWeight.SemiBold)
            Spacer(modifier = Modifier.weight(1f))
            Text(packageToShow.product.price.formatted)
        }
    }
}

@Composable
private fun ActiveAccess(onUnlocked: () -> Unit) {
    val colors = LocalHadithlyColors.current
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
        modifier = Modifier
            .fillMaxWidth()
            .background(colors.surface)
            .padding(18.dp),
    ) {
        Text("Hadithly Pro is active", fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
        Button(onClick = onUnlocked) { Text("Continue reading") }
    }
}

private fun packageTitle(packageToShow: Package): String = when (packageToShow.packageType) {
    PackageType.ANNUAL -> "Yearly"
    PackageType.SIX_MONTH -> "Six months"
    PackageType.THREE_MONTH -> "Three months"
    PackageType.TWO_MONTH -> "Two months"
    PackageType.MONTHLY -> "Monthly"
    PackageType.WEEKLY -> "Weekly"
    PackageType.LIFETIME -> "Lifetime"
    else -> packageToShow.product.title
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
