package com.risingpadel.core.model

/**
 * El repertorio que la app le **enseña** al jugador, que no es el mismo que el que
 * distingue el detector por dentro.
 *
 * ### Por qué existe esta capa
 *
 * El detector separa nueve tipos; la app enseña siete. La diferencia no es cosmética,
 * es una decisión medida. Con las dos tandas limpias de pista (82 golpes etiquetados,
 * ago 2026) el acierto es:
 *
 * | | ocho tipos | repertorio visible |
 * |---|---|---|
 * | tanda de 42 | 71 % | **85 %** |
 * | tanda de 40 (calibrada) | 80 % | **82 %** |
 * | las dos juntas | 68 % | **79 %** |
 *
 * Las dos distinciones que se pliegan son justo las dos que los datos dicen que hoy no
 * se pueden sostener:
 *
 * - **Víbora dentro de bandeja.** Las dos tandas se contradicen: en una la bandeja se
 *   golpea más alta que la víbora y en la otra más baja. Mientras un jugador no calibre
 *   con sus propias tandas, separarlas es echar una moneda al aire con dos nombres.
 * - **El lado de la volea.** Una volea es un bloqueo sin muñeca, y el efecto que
 *   decidiría el lado sencillamente no está en la señal: las diez voleas de la tanda de
 *   42 midieron entre 0,1 y 3,9 de rotación axial, que es ruido.
 *
 * Nada de esto se pierde: el detector **sigue** produciendo los nueve tipos y las tandas
 * se graban con ellos, que es lo que alimenta al modelo entrenado. Esto solo decide qué
 * se le enseña a una persona. Cuando el modelo sepa separar víbora de bandeja con datos
 * de verdad, aquí se deshace el pliegue y ya está.
 */
enum class GolpeVisible(val etiqueta: String) {
    DERECHA("Derecha"),
    REVES("Revés"),
    VOLEA("Volea"),
    GLOBO("Globo"),
    BANDEJA("Bandeja"),
    REMATE("Remate"),
    SAQUE("Saque");

    companion object {
        /** El golpe que se le enseña al jugador, o null si no hay nada que enseñar. */
        fun de(tipo: ShotType): GolpeVisible? = when (tipo) {
            ShotType.FOREHAND -> DERECHA
            ShotType.BACKHAND -> REVES
            ShotType.FOREHAND_VOLLEY, ShotType.BACKHAND_VOLLEY -> VOLEA
            ShotType.LOB -> GLOBO
            // La víbora se pliega dentro de la bandeja: las dos son el golpe alto de
            // control y hoy no se separan con garantías. Ver la cabecera.
            ShotType.BANDEJA, ShotType.VIBORA -> BANDEJA
            ShotType.SMASH -> REMATE
            ShotType.SERVE -> SAQUE
            ShotType.UNKNOWN -> null
        }

        /**
         * Agrupa notas por golpe visible **promediando**, no sumando: una nota de 1 a 7
         * no se acumula. Si un jugador dio bandejas de 3,0 y víboras de 3,4, su bandeja
         * visible es 3,2.
         *
         * El promedio es simple y no ponderado por cantidad a propósito: ponderar haría
         * que dos víboras sueltas movieran menos la nota que veinte bandejas, lo cual es
         * defendible, pero la nota por tipo ya viene promediada desde el estimador y
         * volver a ponderar aquí exigiría arrastrar los recuentos hasta este punto para
         * ganar una diferencia de centésimas.
         */
        fun agruparNotas(porTipo: Map<ShotType, Float>): Map<GolpeVisible, Float> {
            val acumulado = LinkedHashMap<GolpeVisible, MutableList<Float>>()
            for ((tipo, nota) in porTipo) {
                val visible = de(tipo) ?: continue
                acumulado.getOrPut(visible) { mutableListOf() }.add(nota)
            }
            return entries
                .mapNotNull { visible ->
                    acumulado[visible]?.let { visible to it.average().toFloat() }
                }
                .toMap()
        }

        /** Agrupa recuentos **sumando**: doce bandejas y tres víboras son quince. */
        fun agruparRecuentos(porTipo: Map<ShotType, Int>): Map<GolpeVisible, Int> {
            val acumulado = LinkedHashMap<GolpeVisible, Int>()
            for ((tipo, cuantos) in porTipo) {
                if (cuantos <= 0) continue
                val visible = de(tipo) ?: continue
                acumulado[visible] = (acumulado[visible] ?: 0) + cuantos
            }
            return entries.mapNotNull { v -> acumulado[v]?.let { v to it } }.toMap()
        }
    }
}
