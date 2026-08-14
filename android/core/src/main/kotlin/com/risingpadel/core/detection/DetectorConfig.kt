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
     * Se compara contra el recorrido del swing y no contra la postura en el impacto.
     *
     * **+14, medido con una tanda limpia de 42 golpes** (ago 2026), grabada ya con el
     * eje de elevación corregido. La separación es de las que no dejan lugar a dudas:
     * los diecisiete golpes altos —remate, bandeja, víbora— picaron entre +15° y +56°, y
     * los veinte de fondo y volea entre −82° y +14°. No se solapa ni un golpe.
     *
     * El −5 anterior salió de la tanda anterior, que se grabó con el eje aún girándose y
     * llevaba las elevaciones contaminadas. Con −5 las voleas se colaban en la rama alta
     * —una volea de revés pica a +2° y ya pasaba por remate— y de ahí venía la mitad de
     * los fallos: tres voleas de revés seguidas clasificadas como smash.
     *
     * Sigue teniendo sentido físico: un golpe alto de pádel es aquel en el que la pala
     * pasa claramente por encima de la horizontal, no el que la roza.
     */
    val overheadElevationDeg: Float = 14f,
    /** Por debajo de este ángulo barrido el golpeo es una volea. */
    val volleySweptDeg: Float = 50f,
    /**
     * La segunda firma de la volea, validada en pista (ago 2026): swing medio con la
     * pala quieta. Una tanda de voleas de revés reales barría 147-170° (por encima de
     * volleySweptDeg) pero con axial 0.3-3.8, mientras las derechas de fondo reales
     * promediaban 7.9-10.5: el efecto separa lo que el barrido solapa.
     *
     * 4,0 es la única ventana que satisface las dos tandas de pista: la volea más
     * rotada de agosto llevaba 3,8, y el revés de fondo menos rotado de la tanda de
     * ocho tipos llevaba 4,5. Entre medias no cabe nada más.
     */
    val volleyAxialMaxRadS: Float = 4f,
    /**
     * Techo de barrido para esa segunda firma: más allá ya es un swing completo.
     *
     * 310, subido desde 210 con la tanda de 40 en bloques (ago 2026): una volea de
     * revés real barrió 301° con la pala quieta (3,1 de axial) — una volea con mucho
     * acompañamiento sigue siendo una volea, y lo que la delata es la pala quieta, no
     * el arco. Ningún golpe de fondo de las dos tandas limpias baja de 4 de axial, así
     * que subir el techo no les abre la puerta.
     */
    val volleyMaxSweptDeg: Float = 310f,
    /**
     * Barrido mínimo del saque: 270°.
     *
     * Los saques reales barrieron 181-307°, así que 175 los cogería los cinco... y de
     * paso las derechas de fondo, que barren ~190 y rotan 7,9-10,5 rad/s — por encima
     * del umbral de rotación del saque. Con estos rasgos, un saque flojo y una derecha
     * son indistinguibles, y equivocarse hacia "todas las derechas son saques" es mucho
     * peor que perder el saque más corto de cada cinco.
     */
    val serveSweptDeg: Float = 270f,
    /**
     * Rotación axial mínima del saque. **Es lo que de verdad lo define.**
     *
     * El saque del pádel se arma por debajo de la cintura y se pega con pronación: no
     * tiene la violencia del saque de tenis, pero sí un giro sobre el eje del antebrazo
     * que ningún otro golpe alcanza. En una tanda real de saques salió entre 6,2 y 8,7
     * rad/s, cuando el siguiente golpe más rotado de las otras cinco tandas llegó a 6,9
     * (una víbora, con 59° de barrido) y a 5,7 (una volea, con 172°). Exigiendo las dos
     * cosas —barrido largo y mucha rotación— los saques salen los cinco y no entra nadie.
     *
     * El umbral anterior pedía un pico de 18 rad/s, de saque de tenis: los saques reales
     * picaron entre 9,5 y 15,3 y no llegaba ninguno.
     */
    val serveAxialRadS: Float = 5.5f,
    /**
     * La segunda firma del saque: **el brazo armado en alto antes de golpear**.
     *
     * De la tanda de 40 en bloques (ago 2026), donde la primera firma solo pescaba uno
     * de cinco saques: los otros cuatro rotaban 4,0-5,7 —por debajo del umbral— o
     * barrían menos de 270°. Lo que los cinco compartían, y ningún otro golpe bajo de
     * las dos tandas limpias: la preparación por ENCIMA de la horizontal (+10..+27°,
     * el gesto de armar el saque llevando la pala arriba y atrás) con el impacto a la
     * altura de la cintura y pronación clara. Las voleas se preparan como mucho a +6°,
     * y la única derecha que se armó en alto (+26°, tanda de 42) impactó a −37° — por
     * eso la firma exige además que el golpeo no sea bajo.
     *
     * Umbrales: preparación sobre [serveArmedPrepDeg], pronación (con signo, lado de
     * derecha) sobre [serveArmedAxialRadS], impacto por encima de
     * [serveArmedImpactFloorDeg] y barrido mínimo [serveArmedSweptDeg] de cordura.
     */
    val serveArmedPrepDeg: Float = 8f,
    val serveArmedAxialRadS: Float = 3.5f,
    val serveArmedImpactFloorDeg: Float = -20f,
    val serveArmedSweptDeg: Float = 90f,
    /**
     * Pico de |gyro| a partir del cual un golpeo alto es un smash.
     *
     * 14, de la tanda limpia de 42 golpes (ago 2026): los seis remates picaron
     * 14.5-18.7 y ninguna bandeja ni víbora pasó de 13.6. La frontera cae justo en el
     * hueco, y en 16 se quedaba fuera el remate más flojo de los seis.
     *
     * El valor anterior (16) venía de una tanda con la elevación corrupta, donde el
     * reparto de golpes entre las ramas era otro. Dos tandas reales han dado picos de
     * remate distintos (10.6-21.4 la primera, 14.5-18.7 esta), así que este umbral es de
     * los que más gana con la calibración por jugador.
     */
    val smashPeakGyroRadS: Float = 14f,
    /**
     * Altura del golpeo que separa la bandeja de la víbora.
     *
     * Las dos empiezan igual —brazo arriba, misma preparación— pero **la víbora se
     * golpea más baja**: es un golpe cortado que sale más plano, mientras la bandeja se
     * impacta arriba. Con la tanda limpia de 42 golpes (ago 2026) la bandeja picó a
     * +39..+56° (mediana +50) y la víbora a +15..+44° (mediana +38); el punto medio de
     * las medianas cae en +44.
     *
     * Es la frontera más floja de las tres: las dos familias se rozan (una bandeja a
     * +39 y una víbora a +44), así que de once golpes altos se colocan bien nueve. Se
     * queda como está en vez de forzarla, porque el que la puede afinar de verdad es el
     * calibrador con las tandas de cada jugador.
     *
     * Antes se intentaba separarlas por el efecto, y no funcionaba porque no puede: la
     * rotación axial media de las víboras (−2,0) y la de las bandejas (−1,9) son el
     * mismo número. Una víbora no rota todo el swing, da un latigazo al final, y
     * promediarlo sobre 200° de arco lo borra.
     */
    val viboraElevationDeg: Float = 44f,
    /**
     * Umbral alternativo para separar víbora de bandeja: **la pronación, con signo**.
     * Rotación axial media por encima de esto → víbora; por debajo → bandeja.
     *
     * Null de fábrica, y a propósito: las dos tandas limpias se contradicen. En la de
     * 42 (ago 2026) las separaba la altura y el efecto no distinguía nada; en la de 40
     * en bloques, la altura no separaba nada (bandejas a +4..+20 y víboras a +6..+29,
     * mezcladas) y el efecto las partía limpio: bandejas planas (−0,3..+2,3) contra
     * víboras cortadas (+2,8..+6,0). Es una frontera de técnica personal, así que la
     * fija el calibrador con las tandas de cada jugador — y solo si en SUS datos el
     * efecto separa mejor que la altura.
     */
    val viboraAxialRadS: Float? = null,
    /** Ventana previa al impacto sobre la que se promedia la rotación axial. */
    val axialWindowMs: Long = 200,
    /**
     * Ventana previa al **arranque del swing** sobre la que se mide la elevación de
     * preparación, con el brazo aún calmado (la gravedad ahí sí es fiable).
     */
    val prepWindowMs: Long = 400,
    /**
     * Elevación de preparación a partir de la cual el golpe se armó en alto.
     *
     * **90 = prácticamente apagado, y a propósito.** Este testigo se añadió cuando el
     * pico de elevación llegaba corrupto y no servía para nada; con el eje del antebrazo
     * ya bien orientado, el pico separa altos de bajos 38 veces de 40 y la preparación
     * solo mete falsos: en la tanda de ocho tipos, los saques se preparan a +56..+64 —
     * más alto que las víboras— porque el saque de pádel se arma con el brazo recogido.
     *
     * Se deja el campo porque la calibración por jugador puede bajarlo si sus tandas
     * demuestran que en su técnica la preparación sí distingue.
     */
    val prepOverheadElevationDeg: Float = 90f,
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
        overheadElevationDeg = calibracion.overheadElevationDeg ?: overheadElevationDeg,
        prepOverheadElevationDeg =
            calibracion.prepOverheadElevationDeg ?: prepOverheadElevationDeg,
        smashPeakGyroRadS = calibracion.smashPeakGyroRadS ?: smashPeakGyroRadS,
        viboraElevationDeg = calibracion.viboraElevationDeg ?: viboraElevationDeg,
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
