package com.hadithly.app.features.widgets

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import com.hadithly.app.MainActivity
import com.hadithly.app.core.links.CanonicalHadithUrl
import com.hadithly.app.core.widgets.WidgetSnapshotStore

/**
 * Private relays keep widget data out of external URLs. They exist only to
 * turn a host click into the same canonical/Continue Reading intents the app
 * already understands, then immediately finish.
 */
class DailyWidgetEntryActivity : Activity() {
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        WidgetSnapshotStore(this).daily()?.let { snapshot ->
            startActivity(Intent(this, MainActivity::class.java).apply {
                data = Uri.parse(CanonicalHadithUrl.build(snapshot.collectionSlug, snapshot.providerHadithId))
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            })
        }
        finish()
    }
}

class ContinueWidgetEntryActivity : Activity() {
    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        startActivity(Intent(this, MainActivity::class.java).apply {
            putExtra("widgetContinue", true)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        })
        finish()
    }
}
