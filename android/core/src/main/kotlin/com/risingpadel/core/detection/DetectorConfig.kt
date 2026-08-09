package com.risingpadel.core.detection

import com.risingpadel.core.model.Vector3
import kotlinx.serialization.Serializable

@Serializable
enum class Sensitivity(val factor: Float) {
    /** Menos falsos positivos, se pierden golpeos suaves. */
    LOW(1.25f),
    MEDIUM(1.0f),

    /** Detecta golpeos más flojos a cambio de más falsos positivos. */
    HIGH(0.75f),
}

/**
 * Todos los umbrales del detector y del clasificador. Ver `docs/shot-detection.md`.
 *
 * Los valores por defecto están fijados para un jugador adulto de nivel medio con el
 * reloj en la muñeca de la pala.
 */
data class DetectorConfig(
    val sampleRateHz: Int = 50,

    // --- detección ---
    /**
     * rad/s a partir de los cuales se considera que ha empezado un swing.
     *
     * 3.5 rad/s deja fuera el braceo de correr y de colocarse (≈2 rad/s) pero no una
     * volea bloqueada, que es el golpeo con menos velocidad angular de todos.
     */
    val swingOnsetRadS: Float = 3.5f,
    /** Muestras consecutivas por encima de [swingOnsetRadS] para confirmar el swing. */
    val onsetSamples: Int = 2,
    /**
     * Pico mínimo de |gyro| en el swing para que cuente como golpeo. Referencia: una
     * volea ronda 5-10 rad/s, una derecha 15-25 y un smash 25-35.
     */
    val minPeakGyroRadS: Float = 5.5f,
    /** Pico mínimo de |accel| (en g) para considerar que hubo impacto. */
    val impactG: Float = 3.2f,
    /** Tiempo muerto tras un golpeo, para no contar el rebote del impacto. */
    val refractoryMs: Long = 320,
    /** Si un swing dura más que esto sin impacto, era desplazamiento, no golpeo. */
    val maxSwingMs: Long = 900,
    /** Un swing más corto que esto es ruido. */
    val minSwingMs: Long = 80,

    // --- clasificación ---
    /**
     * Grados sobre la horizontal que tiene que alcanzar el brazo
     * ([ShotFeatures.peakElevationDeg]) para que el golpeo sea por encima de la cabeza.
     *
     * Se compara contra el recorrido del swing y no contra la postura en el impacto:
     * medida sobre el impacto, la elevación de una tanda de derechas (+41..+77 en pista,
     * ago 2026) y la de una tanda de víboras (−20..+56) se solapaban por completo, así
     * que ningún umbral sobre ese valor podía separarlas.
     */
    val overheadElevationDeg: Float = 50f,
    /** Por debajo de este ángulo barrido el golpeo es una volea. */
    val volleySweptDeg: Float = 70f,
    /**
     * La segunda firma de la volea, validada en pista (ago 2026): swing medio con la
     * pala quieta. Una tanda de voleas de revés reales barría 147-170° (por encima de
     * volleySweptDeg) pero con axial 0.3-3.8, mientras las derechas de fondo reales
     * promediaban 7.9-10.5: el efecto separa lo que el barrido solapa.
     */
    val volleyAxialMaxRadS: Float = 4.5f,
    /** Techo de barrido para esa segunda firma: más allá ya es un swing completo. */
    val volleyMaxSweptDeg: Float = 190f,
    /** Ángulo barrido a partir del cual un golpeo alto es un saque y no una bandeja. */
    val serveSweptDeg: Float = 220f,
    /** Pico de |gyro| adicional que exige el saque. */
    val servePeakGyroRadS: Float = 18f,
    /**
     * Pico de |gyro| a partir del cual un golpeo alto es un smash.
     *
     * 16 y no 24: recalibrado con remates reales de pista (ago 2026), que picaron
     * 10.6-21.4 rad/s — con el umbral en 24 casi ningún remate de nivel amateur
     * llegaba. Las víboras reales de la misma tanda picaron 9.2-14.3.
     */
    val smashPeakGyroRadS: Float = 16f,
    /**
     * Rotación axial media (rad/s, en valor absoluto) a partir de la cual un golpeo
     * alto que no es smash se considera víbora: el efecto lateral es su seña de
     * identidad, la bandeja se pega mucho más plana.
     *
     * 4 y no 9: recalibrado con víboras reales de pista (ago 2026), que promediaron
     * |4.1-5.4| de axial — con el umbral en 9 ninguna llegaba. Las derechas de fondo
     * (axial 7.9-10.5) no compiten aquí: no pasan el filtro de golpe alto. El riesgo
     * son las bandejas con algo de efecto; falta su tanda de pista para afinar.
     */
    val viboraAxialRadS: Float = 4f,
    /** Ventana previa al impacto sobre la que se promedia la rotación axial. */
    val axialWindowMs: Long = 200,
    /**
     * Ventana previa al **arranque del swing** sobre la que se mide la elevación de
     * preparación, con el brazo aún calmado (la gravedad ahí sí es fiable).
     */
    val prepWindowMs: Long = 400,
    /** Elevación de preparación a partir de la cual el golpe se armó en alto. */
    val prepOverheadElevationDeg: Float = 45f,
    /** Escala para normalizar la rotación axial al calcular la confianza. */
    val axialConfidenceScaleRadS: Float = 4.0f,
    /** Por debajo de esta confianza el tipo se reporta como UNKNOWN (el golpeo sigue contando). */
    val minConfidence: Float = 0.45f,

    // --- geometría ---
    /**
     * Eje longitudinal del antebrazo en coordenadas del dispositivo, apuntando del codo
     * hacia la mano, **con el reloj en la muñeca derecha**. Para la muñeca izquierda el
     * detector lo invierte solo (el reloj va girado 180° respecto al brazo).
     *
     * El valor por defecto (+Y) vale para la orientación estándar de Apple Watch y de
     * la mayoría de Wear OS. Si en la validación en pista los golpeos de derecha salen
     * clasificados como revés, la corrección es [invertAxialSign], no tocar este eje.
     */
    val forearmAxis: Vector3 = Vector3(0f, 1f, 0f),
    /**
     * Invierte el signo de la rotación axial. El convenio de signos del giróscopo debe
     * validarse en pista una vez por plataforma; esta bandera es la corrección.
     */
    val invertAxialSign: Boolean = false,
    /** Brazo de palanca muñeca → centro del cordaje, en metros, para estimar velocidad de pala. */
    val armLeverM: Float = 0.65f,
) {
    val sampleIntervalMs: Long get() = (1000L / sampleRateHz).coerceAtLeast(1L)

    /** Escala los umbrales de energía según la sensibilidad elegida por el usuario. */
    fun withSensitivity(sensitivity: Sensitivity): DetectorConfig = copy(
        swingOnsetRadS = swingOnsetRadS * sensitivity.factor,
        minPeakGyroRadS = minPeakGyroRadS * sensitivity.factor,
        impactG = impactG * sensitivity.factor,
    )

    /**
     * La configuración con los umbrales personales del jugador encima. Lo que la
     * calibración no sostiene se queda de fábrica.
     */
    fun aplicando(calibracion: DetectorCalibration): DetectorConfig = copy(
        prepOverheadElevationDeg =
            calibracion.prepOverheadElevationDeg ?: prepOverheadElevationDeg,
        smashPeakGyroRadS = calibracion.smashPeakGyroRadS ?: smashPeakGyroRadS,
        viboraAxialRadS = calibracion.viboraAxialRadS ?: viboraAxialRadS,
        volleyAxialMaxRadS = calibracion.volleyAxialMaxRadS ?: volleyAxialMaxRadS,
        // Girar el eje del antebrazo invierte la elevación medida, que es justo lo que
        // hay que corregir cuando las tandas dicen que este reloj la lee al revés.
        forearmAxis = if (calibracion.ejeDeElevacionInvertido == true) {
            Vector3(-forearmAxis.x, -forearmAxis.y, -forearmAxis.z)
        } else {
            forearmAxis
        },
    )

    companion object {
        val DEFAULT = DetectorConfig()
    }
}
