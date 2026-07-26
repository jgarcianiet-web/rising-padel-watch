package com.risingpadel.core.model

import kotlin.math.acos
import kotlin.math.sqrt

/** Vector 3D inmutable en el marco de referencia del dispositivo. */
data class Vector3(val x: Float, val y: Float, val z: Float) {

    fun magnitude(): Float = sqrt(x * x + y * y + z * z)

    fun dot(other: Vector3): Float = x * other.x + y * other.y + z * other.z

    /** Devuelve el vector unitario. Si la magnitud es 0 devuelve ZERO en vez de NaN. */
    fun normalized(): Vector3 {
        val m = magnitude()
        return if (m < 1e-6f) ZERO else Vector3(x / m, y / m, z / m)
    }

    operator fun plus(other: Vector3) = Vector3(x + other.x, y + other.y, z + other.z)

    operator fun minus(other: Vector3) = Vector3(x - other.x, y - other.y, z - other.z)

    operator fun times(scalar: Float) = Vector3(x * scalar, y * scalar, z * scalar)

    operator fun unaryMinus() = Vector3(-x, -y, -z)

    /** Ángulo en radianes con otro vector, en [0, PI]. */
    fun angleTo(other: Vector3): Float {
        val cos = normalized().dot(other.normalized()).coerceIn(-1f, 1f)
        return acos(cos)
    }

    companion object {
        val ZERO = Vector3(0f, 0f, 0f)
    }
}
