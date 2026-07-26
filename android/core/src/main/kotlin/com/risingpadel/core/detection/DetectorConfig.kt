package com.risingpadel.core.detection

import com.risingpadel.core.model.Vector3

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
    /** Grados sobre la horizontal a partir de los cuales el golpeo es por encima de la cabeza. */
    val overheadElevationDeg: Float = 45f,
    /** Por debajo de este ángulo barrido el golpeo es una volea. */
    val volleySweptDeg: Float = 70f,
    /** Ángulo barrido a partir del cual un golpeo alto es un saque y no una bandeja. */
    val serveSweptDeg: Float = 220f,
    /** Pico de |gyro| adicional que exige el saque. */
    val servePeakGyroRadS: Float = 18f,
    /** Ventana previa al impacto sobre la que se promedia la rotación axial. */
    val axialWindowMs: Long = 200,
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

    companion object {
        val DEFAULT = DetectorConfig()
    }
}
