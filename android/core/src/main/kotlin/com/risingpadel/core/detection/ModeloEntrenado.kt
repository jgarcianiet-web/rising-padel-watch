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
     * Cuánto tiene que votar el bosque para que se le haga caso.
     *
     * Por debajo manda la heurística. No es desconfianza gratuita: la heurística sabe
     * decir *por qué* clasificó como clasificó, y un golpe que el modelo no tiene claro
     * es justo el que hay que poder explicar.
     */
    const val MIN_VOTOS = 0.6f
}
