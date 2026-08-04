package com.risingpadel.mobile.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.risingpadel.core.detection.Sensitivity
import com.risingpadel.core.model.Hand
import com.risingpadel.mobile.data.AppPreferences

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    preferences: AppPreferences,
    onBack: () -> Unit,
    onBaseUrlChange: (String) -> Unit,
    onTokenChange: (String) -> Unit,
    onShareHealthChange: (Boolean) -> Unit,
    onShareEventsChange: (Boolean) -> Unit,
    onHandChange: (Hand) -> Unit,
    onWristChange: (Hand) -> Unit,
    onSensitivityChange: (Sensitivity) -> Unit,
    onCollectTrainingDataChange: (Boolean) -> Unit,
    onPlayerAliasChange: (String) -> Unit,
    onExportTrainingData: () -> Unit,
    onDeleteTrainingData: () -> Unit,
    onVersionTapped: () -> Unit,
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Ajustes") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Volver")
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            LeagueCard(preferences, onBaseUrlChange, onTokenChange)
            PrivacyCard(preferences, onShareHealthChange, onShareEventsChange)
            PlayerCard(preferences, onHandChange, onWristChange)
            SensitivityCard(preferences, onSensitivityChange)
            // El modo de recogida de datos es una herramienta de quien construye el
            // dataset, no de quien juega: para un usuario normal no existe. Se
            // desbloquea con siete toques en la versión, y cuando la app tenga cuentas
            // de la liga pasará a depender de un rol de verdad.
            if (preferences.developerMode) {
                TrainingDataCard(
                    preferences = preferences,
                    onCollectChange = onCollectTrainingDataChange,
                    onAliasChange = onPlayerAliasChange,
                    onExport = onExportTrainingData,
                    onDelete = onDeleteTrainingData,
                )
            }
            AboutCard(
                developerMode = preferences.developerMode,
                onVersionTapped = onVersionTapped,
            )
        }
    }
}

@Composable
private fun LeagueCard(
    preferences: AppPreferences,
    onBaseUrlChange: (String) -> Unit,
    onTokenChange: (String) -> Unit,
) {
    var baseUrl by remember(preferences.leagueBaseUrl) { mutableStateOf(preferences.leagueBaseUrl) }
    var token by remember { mutableStateOf("") }

    SettingsCard("Liga") {
        Text(
            "La URL base de tu app de liga. La app enviará las sesiones a " +
                "<URL>/v1/padel-sessions.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        OutlinedTextField(
            value = baseUrl,
            onValueChange = { baseUrl = it },
            label = { Text("URL de la liga") },
            placeholder = { Text("https://mi-liga.example.com/api") },
            singleLine = true,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 8.dp),
        )
        Button(
            onClick = { onBaseUrlChange(baseUrl) },
            modifier = Modifier
                .align(Alignment.End)
                .padding(top = 4.dp),
        ) { Text("Guardar URL") }

        OutlinedTextField(
            value = token,
            onValueChange = { token = it },
            label = { Text(if (preferences.hasToken) "Token (ya guardado)" else "Token") },
            singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 12.dp),
        )
        Text(
            "El token se guarda cifrado en el dispositivo y no se muestra nunca.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Button(
            onClick = {
                onTokenChange(token)
                token = ""
            },
            modifier = Modifier
                .align(Alignment.End)
                .padding(top = 4.dp),
        ) { Text("Guardar token") }
    }
}

@Composable
private fun PrivacyCard(
    preferences: AppPreferences,
    onShareHealthChange: (Boolean) -> Unit,
    onShareEventsChange: (Boolean) -> Unit,
) {
    SettingsCard("Privacidad") {
        SwitchRow(
            title = "Compartir datos de salud con la liga",
            subtitle = "Frecuencia cardiaca, calorías, pasos y distancia. Si lo desactivas, " +
                "el reloj ni siquiera los mide.",
            checked = preferences.shareHealth,
            onCheckedChange = onShareHealthChange,
        )
        SwitchRow(
            title = "Compartir el detalle de cada golpeo",
            subtitle = "Si lo desactivas solo se suben los totales por tipo, no la secuencia.",
            checked = preferences.shareShotEvents,
            onCheckedChange = onShareEventsChange,
        )
    }
}

@Composable
private fun PlayerCard(
    preferences: AppPreferences,
    onHandChange: (Hand) -> Unit,
    onWristChange: (Hand) -> Unit,
) {
    SettingsCard("Jugador") {
        Text("Mano de la pala", style = MaterialTheme.typography.labelLarge)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Hand.entries.forEach { hand ->
                FilterChip(
                    selected = preferences.profile.hand == hand,
                    onClick = { onHandChange(hand) },
                    label = { Text(if (hand == Hand.RIGHT) "Diestro" else "Zurdo") },
                )
            }
        }
        Text(
            "Muñeca del reloj",
            style = MaterialTheme.typography.labelLarge,
            modifier = Modifier.padding(top = 12.dp),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Hand.entries.forEach { wrist ->
                FilterChip(
                    selected = preferences.profile.watchWrist == wrist,
                    onClick = { onWristChange(wrist) },
                    label = { Text(if (wrist == Hand.RIGHT) "Derecha" else "Izquierda") },
                )
            }
        }
        if (!preferences.profile.watchOnRacketArm) {
            Text(
                "Para contar golpeos el reloj tiene que ir en el brazo con el que juegas. " +
                    "En la otra muñeca no ve el swing.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.padding(top = 8.dp),
            )
        }
    }
}

@Composable
private fun SensitivityCard(preferences: AppPreferences, onSensitivityChange: (Sensitivity) -> Unit) {
    SettingsCard("Sensibilidad de detección") {
        Text(
            "Si la app cuenta golpeos de más, baja la sensibilidad. Si se deja golpeos " +
                "flojos sin contar, súbela.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.padding(top = 8.dp),
        ) {
            Sensitivity.entries.forEach { sensitivity ->
                FilterChip(
                    selected = preferences.sensitivity == sensitivity,
                    onClick = { onSensitivityChange(sensitivity) },
                    label = {
                        Text(
                            when (sensitivity) {
                                Sensitivity.LOW -> "Baja"
                                Sensitivity.MEDIUM -> "Media"
                                Sensitivity.HIGH -> "Alta"
                            }
                        )
                    },
                )
            }
        }
    }
}

@Composable
private fun TrainingDataCard(
    preferences: AppPreferences,
    onCollectChange: (Boolean) -> Unit,
    onAliasChange: (String) -> Unit,
    onExport: () -> Unit,
    onDelete: () -> Unit,
) {
    var alias by remember(preferences.playerAlias) { mutableStateOf(preferences.playerAlias) }

    SettingsCard("Datos de entrenamiento") {
        Text(
            "Graba tandas de golpes etiquetados en el reloj para entrenar un clasificador " +
                "propio. Guarda la señal cruda de los sensores, que en el resto de la app " +
                "nunca sale del dispositivo. No se sube a la liga: solo sale de aquí si lo " +
                "exportas tú.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        SwitchRow(
            title = "Recoger datos de entrenamiento",
            subtitle = "Activa el modo de grabación en el reloj.",
            checked = preferences.collectTrainingData,
            onCheckedChange = onCollectChange,
        )
        if (preferences.collectTrainingData) {
            OutlinedTextField(
                value = alias,
                onValueChange = { alias = it },
                label = { Text("Alias del jugador") },
                supportingText = { Text("Sirve para validar el modelo dejándote fuera.") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )
            Button(
                onClick = { onAliasChange(alias) },
                modifier = Modifier.align(Alignment.End),
            ) { Text("Guardar alias") }

            if (preferences.trainingDataBytes > 0) {
                Text(
                    "${preferences.trainingDataBytes / 1024} KB recogidos",
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(top = 8.dp),
                )
                Button(onClick = onExport, modifier = Modifier.fillMaxWidth()) {
                    Text("Exportar")
                }
                OutlinedButton(onClick = onDelete, modifier = Modifier.fillMaxWidth()) {
                    Text("Borrar datos recogidos")
                }
            } else {
                Text(
                    "Todavía no ha llegado ningún dato del reloj.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 8.dp),
                )
            }
        }
    }
}

@Composable
private fun AboutCard(developerMode: Boolean, onVersionTapped: () -> Unit) {
    SettingsCard("Acerca de") {
        Text(
            text = "Rising Padel ${com.risingpadel.mobile.BuildConfig.VERSION_NAME}",
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.clickable(onClick = onVersionTapped),
        )
        if (developerMode) {
            Text(
                "Modo desarrollador activado. Siete toques en la versión lo desactivan.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun SettingsCard(title: String, content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Column(modifier = Modifier.padding(top = 8.dp), content = content)
        }
    }
}

@Composable
private fun SwitchRow(
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}
