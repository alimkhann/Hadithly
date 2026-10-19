package com.hadithly.app

import android.app.Application
import android.content.Context
import androidx.test.runner.AndroidJUnitRunner

class HadithlyVerificationRunner : AndroidJUnitRunner() {
    override fun newApplication(classLoader: ClassLoader, className: String, context: Context): Application {
        System.setProperty("hadithly.disableAutomaticLibrarySync", "true")
        return super.newApplication(classLoader, className, context)
    }
}
