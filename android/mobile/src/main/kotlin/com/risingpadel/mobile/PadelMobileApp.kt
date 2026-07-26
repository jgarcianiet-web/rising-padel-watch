package com.risingpadel.mobile

import android.app.Application
import android.content.Context
import com.risingpadel.core.net.JdkHttpTransport
import com.risingpadel.core.storage.FileSessionStore
import com.risingpadel.core.sync.LeagueApiClient
import com.risingpadel.core.sync.SyncQueue
import com.risingpadel.mobile.data.AppSettings
import com.risingpadel.mobile.data.SessionRepository
import com.risingpadel.mobile.sync.SyncScheduler
import java.io.File

class AppContainer(context: Context) {
    val settings = AppSettings(context)

    private val store = FileSessionStore(File(context.filesDir, "sessions"))
    val sessions = SessionRepository(store)

    val leagueClient = LeagueApiClient(JdkHttpTransport())
    val syncQueue = SyncQueue(store = store, client = leagueClient)
}

class PadelMobileApp : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
        SyncScheduler.schedulePeriodic(this)
    }
}
