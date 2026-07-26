package com.risingpadel.core.model

/**
 * Una muestra de los sensores de la muñeca.
 *
 * Las unidades están normalizadas para que Android y watchOS entreguen exactamente lo
 * mismo al detector:
 *
 * @param timestampMs instante monótono en milisegundos (no epoch: no debe saltar si el
 *   reloj corrige su hora).
 * @param accel aceleración del usuario en **g**, ya sin gravedad
 *   (`CMDeviceMotion.userAcceleration` / `TYPE_LINEAR_ACCELERATION` dividido por 9.81).
 * @param gyro velocidad angular en **rad/s** (`rotationRate` / `TYPE_GYROSCOPE`).
 * @param gravity vector gravedad en **g** (`CMDeviceMotion.gravity` / `TYPE_GRAVITY`
 *   dividido por 9.81). Apunta hacia abajo.
 */
data class MotionSample(
    val timestampMs: Long,
    val accel: Vector3,
    val gyro: Vector3,
    val gravity: Vector3,
)
