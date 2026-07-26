package com.risingpadel.mobile.data

import android.content.Context
import android.content.SharedPreferences
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.risingpadel.core.detection.Sensitivity
import com.risingpadel.core.model.Hand
import com.risingpadel.core.model.PlayerProfile
import com.risingpadel.core.sync.LeagueConfig
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "padel_settings")

data class AppPreferences(
    val leagueBaseUrl: String = "",
    val profile: PlayerProfile = PlayerProfile(),
    val sensitivity: Sensitivity = Sensitivity.MEDIUM,
    /** Consentimiento explícito de compartir datos de salud con la liga. */
    val shareHealth: Boolean = false,
    /** Subir la serie de golpeos, no solo los agregados. */
    val shareShotEvents: Boolean = true,
    val hasToken: Boolean = false,
)

/**
 * Ajustes de la app.
 *
 * El token de la liga va aparte, en [EncryptedSharedPreferences], y nunca en DataStore:
 * es una credencial, no una preferencia, y no debe acabar en un backup en claro ni en
 * los volcados de diagnóstico.
 */
class AppSettings(private val context: Context) {

    private val secure: SharedPreferences by lazy {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            "padel_secure",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    val preferences: Flow<AppPreferences> = context.dataStore.data.map { prefs ->
        AppPreferences(
            leagueBaseUrl = prefs[KEY_BASE_URL].orEmpty(),
            profile = PlayerProfile(
                hand = Hand.fromWire(prefs[KEY_HAND] ?: Hand.RIGHT.wireName),
                watchWrist = Hand.fromWire(prefs[KEY_WRIST] ?: Hand.RIGHT.wireName),
                birthYear = prefs[KEY_BIRTH_YEAR],
                maxHeartRate = prefs[KEY_MAX_HR],
                restingHeartRate = prefs[KEY_RESTING_HR],
            ),
            sensitivity = runCatching { Sensitivity.valueOf(prefs[KEY_SENSITIVITY].orEmpty()) }
                .getOrDefault(Sensitivity.MEDIUM),
            shareHealth = prefs[KEY_SHARE_HEALTH] ?: false,
            shareShotEvents = prefs[KEY_SHARE_EVENTS] ?: true,
            hasToken = token() != null,
        )
    }

    suspend fun setLeagueBaseUrl(baseUrl: String) {
        context.dataStore.edit { it[KEY_BASE_URL] = baseUrl.trim() }
    }

    suspend fun setProfile(profile: PlayerProfile) {
        context.dataStore.edit { prefs ->
            prefs[KEY_HAND] = profile.hand.wireName
            prefs[KEY_WRIST] = profile.watchWrist.wireName
            profile.birthYear?.let { prefs[KEY_BIRTH_YEAR] = it }
            profile.maxHeartRate?.let { prefs[KEY_MAX_HR] = it }
            profile.restingHeartRate?.let { prefs[KEY_RESTING_HR] = it }
        }
    }

    suspend fun setSensitivity(sensitivity: Sensitivity) {
        context.dataStore.edit { it[KEY_SENSITIVITY] = sensitivity.name }
    }

    suspend fun setShareHealth(share: Boolean) {
        context.dataStore.edit { it[KEY_SHARE_HEALTH] = share }
    }

    suspend fun setShareShotEvents(share: Boolean) {
        context.dataStore.edit { it[KEY_SHARE_EVENTS] = share }
    }

    fun token(): String? = secure.getString(KEY_TOKEN, null)?.takeIf { it.isNotBlank() }

    fun setToken(token: String?) {
        secure.edit().apply {
            if (token.isNullOrBlank()) remove(KEY_TOKEN) else putString(KEY_TOKEN, token.trim())
        }.apply()
    }

    /** null si falta la URL o el token: sin los dos no hay a dónde sincronizar. */
    fun leagueConfig(baseUrl: String): LeagueConfig? {
        val token = token() ?: return null
        if (baseUrl.isBlank()) return null
        return LeagueConfig(baseUrl = baseUrl, token = token)
    }

    private companion object {
        val KEY_BASE_URL = stringPreferencesKey("league_base_url")
        val KEY_HAND = stringPreferencesKey("hand")
        val KEY_WRIST = stringPreferencesKey("watch_wrist")
        val KEY_BIRTH_YEAR = intPreferencesKey("birth_year")
        val KEY_MAX_HR = intPreferencesKey("max_hr")
        val KEY_RESTING_HR = intPreferencesKey("resting_hr")
        val KEY_SENSITIVITY = stringPreferencesKey("sensitivity")
        val KEY_SHARE_HEALTH = booleanPreferencesKey("share_health")
        val KEY_SHARE_EVENTS = booleanPreferencesKey("share_shot_events")
        const val KEY_TOKEN = "league_token"
    }
}
