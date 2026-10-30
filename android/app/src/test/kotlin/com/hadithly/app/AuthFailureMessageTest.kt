package com.hadithly.app

import com.clerk.api.network.model.error.ClerkErrorResponse
import com.clerk.api.network.model.error.Error
import com.clerk.api.network.serialization.ClerkResult
import com.hadithly.app.features.auth.AuthFailureMessage
import org.junit.Assert.assertEquals
import org.junit.Test

class AuthFailureMessageTest {
    @Test fun codesSelectMessagesWithoutProviderText() {
        val cases = listOf(
            "form_password_incorrect" to AuthFailureMessage.PASSWORD,
            "form_code_incorrect" to AuthFailureMessage.CODE,
            "totp_incorrect_code" to AuthFailureMessage.CODE,
            "verification_expired" to AuthFailureMessage.EXPIRED,
            "form_password_length_too_short" to AuthFailureMessage.LONGER,
            "form_password_not_strong_enough" to AuthFailureMessage.STRONGER,
            "form_password_pwned" to AuthFailureMessage.BREACHED,
            "form_identifier_exists" to AuthFailureMessage.EXISTING,
            "form_identifier_not_found" to AuthFailureMessage.MISSING,
            "too_many_requests" to AuthFailureMessage.RATE,
            "verification_code_too_many_requests" to AuthFailureMessage.RATE,
            "verification_code_too_many_attempts" to AuthFailureMessage.RATE,
            "unknown_code" to AuthFailureMessage.ACTION,
        )
        for ((code, expected) in cases) {
            val failure = ClerkResult.Failure(error = ClerkErrorResponse(errors = listOf(Error(message = "Provider internal text %@", longMessage = "Private diagnostic", code = code))))
            assertEquals(expected, AuthFailureMessage.from(failure))
        }
        assertEquals(AuthFailureMessage.RATE, AuthFailureMessage.from(ClerkResult.Failure(error = null, code = 429)))
        assertEquals(AuthFailureMessage.CONNECTION, AuthFailureMessage.from(ClerkResult.Failure(error = null, throwable = java.io.IOException("Private detail"))))
    }

    @Test fun localStatesAndUnknownDetailsStayBounded() {
        assertEquals(AuthFailureMessage.ACTION, AuthFailureMessage.local("Unknown provider detail with secrets"))
        assertEquals(AuthFailureMessage.SESSION, AuthFailureMessage.local("The reset session expired. Please start again."))
        assertEquals(AuthFailureMessage.STEP, AuthFailureMessage.local("Sign-in needs another step. Please try again."))
        for (message in AuthFailureMessage.entries) assertEquals(message, AuthFailureMessage.local(message.source))
    }
}
