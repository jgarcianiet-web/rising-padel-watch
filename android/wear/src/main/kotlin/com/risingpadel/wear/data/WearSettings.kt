package com.risingpadel.wear.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.risingpadel.core.detection.Sensitivity
import com.risingpadel.core.model.Hand
import com.risingpadel.core.model.PlayerProfile
import com.risingpadel.core.score.DeuceFormat
import com.risingpadel.core.settings.DeviceSettings
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "padel_wear_settings")

data class WearPreferences(
    val profile: PlayerProfile = PlayerProfile(),
    val sensitivity: Sensitivity = Sensitivity.MEDIUM,
    /** Consentimiento explícito para que los datos de salud salgan del reloj. */
    val shareHealth: Boolean = false,
    /** Llevar el marcador del partido. Un entreno suelto no lo necesita. */
    val trackScore: Boolean = false,
    val deuceFormat: DeuceFormat = DeuceFormat.GOLDEN_POINT,
    val setsToWin: Int = 2,
    /**
     * Modo de recogida de datos de entrenamiento. Apagado por defecto: guarda la señal
     * cruda de los sensores, que en el resto de la app nunca sale del reloj.
     */
    val collectTrainingData: Boolean = false,
    /** Alias del jugador, para poder validar el modelo dejándolo fuera. */
    val playerAlias: String = DeviceSettings.DEFAULT_ALIAS,
    /** Nivel de pádel del jugador (1-7), si se conoce. Para calibrar la escala. */
    val playerLevel: Int? = null,
    /** Marca de tiempo de la última edición, para resolver la replicación. */
    val updatedAtEpochMs: Long = 0L,
) {
    /** La parte que se replica desde el móvil. El marcador se queda fuera a propósito. */
    fun toDeviceSettings(): DeviceSettings = DeviceSettings(
        profile = profile,
        sensitivity = sensitivity,
        shareHealth = shareHealth,
        collectTrainingData = collectTrainingData,
        playerAlias = playerAlias,
        playerLevel = playerLevel,
        updatedAtEpochMs = updatedAtEpochMs,
    )

    /** Aplica lo replicado dejando intactos los ajustes de partido, que son del reloj. */
    fun withDeviceSettings(settings: DeviceSettings): WearPreferences = copy(
        profile = settings.profile,
        sensitivity = settings.sensitivity,
        shareHealth = settings.shareHealth,
        collectTrainingData = settings.collectTrainingData,
        playerAlias = settings.playerAlias,
        playerLevel = settings.playerLevel,
        updatedAtEpochMs = settings.updatedAtEpochMs,
    )
}

/**
 * Ajustes del reloj. Se replican desde el móvil por el Data Layer, pero el reloj tiene
 * su propia copia para poder medir una sesión sin el móvil delante.
 */
class WearSettings(private val context: Context) {

    val preferences: Flow<WearPreferences> = context.dataStore.data.map { prefs ->
        WearPreferences(
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
            trackScore = prefs[KEY_TRACK_SCORE] ?: false,
            deuceFormat = DeuceFormat.fromWire(prefs[KEY_DEUCE_FORMAT].orEmpty()),
            setsToWin = prefs[KEY_SETS_TO_WIN] ?: 2,
            collectTrainingData = prefs[KEY_COLLECT_TRAINING] ?: false,
            playerAlias = prefs[KEY_PLAYER_ALIAS] ?: DeviceSettings.DEFAULT_ALIAS,
            playerLevel = prefs[KEY_PLAYER_LEVEL],
            updatedAtEpochMs = prefs[KEY_UPDATED_AT] ?: 0L,
        )
    }

    /**
     * Aplica los ajustes replicados desde el móvil.
     *
     * El merge por marca de tiempo lo decide [DeviceSettings]: si lo que llega es más
     * viejo que lo que hay, no se toca nada. Hace falta porque el Data Layer reentrega el
     * último item al reconectar, y sin esto una reconexión revertiría un cambio posterior.
     */
    suspend fun applyRemote(incoming: DeviceSettings) {
        val current = preferences.first()
        val merged = current.toDeviceSettings().mergedWith(incoming)
        if (merged.updatedAtEpochMs == current.updatedAtEpochMs) return
        update(current.withDeviceSettings(merged))
    }

    suspend fun update(preferences: WearPreferences) {
        context.dataStore.edit { prefs ->
            prefs[KEY_HAND] = preferences.profile.hand.wireName
            prefs[KEY_WRIST] = preferences.profile.watchWrist.wireName
            preferences.profile.birthYear?.let { prefs[KEY_BIRTH_YEAR] = it }
            preferences.profile.maxHeartRate?.let { prefs[KEY_MAX_HR] = it }
            preferences.profile.restingHeartRate?.let { prefs[KEY_RESTING_HR] = it }
            prefs[KEY_SENSITIVITY] = preferences.sensitivity.name
            prefs[KEY_SHARE_HEALTH] = preferences.shareHealth
            prefs[KEY_TRACK_SCORE] = preferences.trackScore
            prefs[KEY_DEUCE_FORMAT] = preferences.deuceFormat.wireName
            prefs[KEY_SETS_TO_WIN] = preferences.setsToWin
            prefs[KEY_COLLECT_TRAINING] = preferences.collectTrainingData
            prefs[KEY_PLAYER_ALIAS] = preferences.playerAlias
            preferences.playerLevel?.let { prefs[KEY_PLAYER_LEVEL] = it }
                ?: prefs.remove(KEY_PLAYER_LEVEL)
            prefs[KEY_UPDATED_AT] = preferences.updatedAtEpochMs
        }
    }

    private companion object {
        val KEY_HAND = stringPreferencesKey("hand")
        val KEY_WRIST = stringPreferencesKey("watch_wrist")
        val KEY_BIRTH_YEAR = intPreferencesKey("birth_year")
        val KEY_MAX_HR = intPreferencesKey("max_hr")
        val KEY_RESTING_HR = intPreferencesKey("resting_hr")
        val KEY_SENSITIVITY = stringPreferencesKey("sensitivity")
        val KEY_SHARE_HEALTH = booleanPreferencesKey("share_health")
        val KEY_TRACK_SCORE = booleanPreferencesKey("track_score")
        val KEY_DEUCE_FORMAT = stringPreferencesKey("deuce_format")
        val KEY_SETS_TO_WIN = intPreferencesKey("sets_to_win")
        val KEY_COLLECT_TRAINING = booleanPreferencesKey("collect_training_data")
        val KEY_PLAYER_ALIAS = stringPreferencesKey("player_alias")
        val KEY_PLAYER_LEVEL = intPreferencesKey("player_level")
        val KEY_UPDATED_AT = longPreferencesKey("settings_updated_at")
    }
}
