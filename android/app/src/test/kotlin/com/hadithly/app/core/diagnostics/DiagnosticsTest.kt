package com.hadithly.app.core.diagnostics

import io.sentry.JsonSerializer
import io.sentry.SentryEvent
import io.sentry.SentryLevel
import io.sentry.SentryOptions
import io.sentry.protocol.Message
import io.sentry.protocol.User
import io.sentry.protocol.SentryException
import io.sentry.protocol.SentryStackFrame
import io.sentry.protocol.SentryStackTrace
import org.junit.Assert.*
import org.junit.Test
import java.io.StringWriter

class DiagnosticsTest {
    @Test fun actualSdkSerializationRemovesSensitiveDataAndPreservesCodeFrame() {
        val marker = "PRIVATE_TEST_CANARY"
        val event = SentryEvent().apply {
            level = SentryLevel.FATAL
            user = User().apply { id = marker; email = marker }
            message = Message().apply { formatted = marker }
            setExtra("note", marker); setTag("account", marker)
            contexts["reading"] = mapOf("arabicText" to "نص الاختبار")
            exceptions = listOf(SentryException().apply {
                type = marker; value = marker
                stacktrace = SentryStackTrace(listOf(SentryStackFrame().apply {
                    module = "com.hadithly.app.Reader"; function = "load"; filename = "Reader.kt"; lineno = 42
                    contextLine = marker; vars = mapOf("token" to marker)
                }))
            })
            release = "hadithly@123456abcdef"; environment = "development"
        }
        val safe = CrashReporting.redacted(event)
        val writer = StringWriter(); JsonSerializer(SentryOptions()).serialize(safe, writer)
        val body = writer.toString()
        assertFalse(body.contains(marker)); assertFalse(body.contains("نص الاختبار"))
        assertTrue(body.contains("Reader.kt")); assertTrue(body.contains("42"))
        assertEquals(event.release, safe.release); assertEquals("android", safe.getTag("surface"))
        assertNull(safe.user); assertNull(safe.throwable)
    }
}
