package com.risingpadel.core.detection

/**
 * El modelo entrenado que lleva la app, o null si todavía no hay ninguno.
 *
 * **Este fichero lo genera `tools/exportar_modelo.py`** desde el workflow
 * `entrenar-modelo.yml`, y su gemelo Swift sale de la misma ejecución con los mismos
 * números. No se edita a mano: lo que se edita a mano es el generador.
 *
 * Arranca vacío a propósito. La heurística es lo que hay hasta que haya tandas de varias
 * personas —el propio entrenador pide 4-5 jugadores y unos 2.000 golpeos—, y un modelo
 * entrenado con una sola muñeca aprende esa muñeca, no el golpe: daría números preciosos
 * en el ordenador y se caería con el primer usuario nuevo.
 */
object ModeloEntrenado {

    /** El modelo de fábrica, o null si esta versión no lleva ninguno. */
    val actual: ModeloDeGolpes? = null

    /**
     * Qué clasificó este golpe, para poder responder dentro de un año a "¿por qué el
     * reloj decía esto en septiembre?".
     *
     * **Nunca se sustituye un modelo en silencio.** Cada golpeo guarda la versión que lo
     * clasificó ([com.risingpadel.core.model.Shot.modelVersion]) y cada análisis del
     * entrenador guarda la suya. Sin esto, el día que el modelo 0.2 empeore un tipo de
     * golpe, el historial sería una mezcla de dos criterios sin forma de separarlos: las
     * notas de antes y las de después no se podrían comparar, que es justo lo que la app
     * promete hacer.
     *
     * La versión la escribe `tools/exportar_modelo.py` junto al bosque. Mientras no haya
     * modelo, clasifica la heurística y la versión es la suya — que también cambia
     * cuando se mueven los umbrales, por el mismo motivo.
     */
    const val VERSION = "heuristica-2026.09"

    /**
     * Cuánto tiene que votar el bosque para que se le haga caso.
     *
     * Por debajo manda la heurística. No es desconfianza gratuita: la heurística sabe
     * decir *por qué* clasificó como clasificó, y un golpe que el modelo no tiene claro
     * es justo el que hay que poder explicar.
     */
    const val MIN_VOTOS = 0.6f
}
